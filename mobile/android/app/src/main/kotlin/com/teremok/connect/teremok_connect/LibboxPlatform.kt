package com.teremok.connect.teremok_connect

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.system.OsConstants
import android.util.Log
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.Inet6Address
import java.net.InterfaceAddress
import java.net.NetworkInterface
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

/**
 * [PlatformInterface] для libbox [CommandServer].
 *
 * Network monitor + getInterfaces обязательны: без них outbound на Android «пустой»
 * и трафик не уходит (см. sing-box-for-android PlatformInterfaceWrapper).
 */
internal class LibboxPlatform(
    private val appContext: Context,
    private val tunFdProvider: () -> Int?,
    private val protectSocket: (Int) -> Boolean,
) : PlatformInterface {

    companion object {
        private const val TAG = "LibboxPlatform"
    }

    override fun localDNSTransport(): LocalDNSTransport? = LocalResolver

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        val ok = protectSocket(fd)
        if (!ok) {
            Log.e(TAG, "protect($fd) FAILED — direct/VLESS socket may loop through VPN")
            ProtectGuard.reportFailure(fd)
            return
        }
        Log.i(TAG, "protect($fd) ok")
    }

    override fun openTun(options: TunOptions): Int {
        val fd = tunFdProvider()
            ?: error("TUN fd not set — call SingBoxBridge.setTunFd() first")
        return fd
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner = ConnectionOwner()

    override fun getInterfaces(): io.nekohasekai.libbox.NetworkInterfaceIterator {
        val cm = appContext.getSystemService(ConnectivityManager::class.java)
        val networks = cm.allNetworks
        val systemInterfaces = NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
        val interfaces = mutableListOf<LibboxNetworkInterface>()

        for (network in networks) {
            val linkProperties = cm.getLinkProperties(network) ?: continue
            val networkCapabilities = cm.getNetworkCapabilities(network) ?: continue
            // VPN/tun в списке ломает direct outbound к VPS (петля через TUN).
            if (networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                continue
            }
            val interfaceName = linkProperties.interfaceName ?: continue
            if (interfaceName.startsWith("tun")) continue
            val systemInterface = systemInterfaces.find { it.name == interfaceName } ?: continue

            val boxInterface = LibboxNetworkInterface()
            boxInterface.name = interfaceName
            boxInterface.dnsServer = KotlinStringIterator(
                linkProperties.dnsServers.mapNotNull { it.hostAddress }.iterator(),
            )
            boxInterface.type = when {
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ->
                    Libbox.InterfaceTypeWIFI
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ->
                    Libbox.InterfaceTypeCellular
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ->
                    Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            boxInterface.index = systemInterface.index
            runCatching { boxInterface.mtu = systemInterface.mtu }
                .onFailure { Log.w(TAG, "mtu for $interfaceName: ${it.message}") }
            boxInterface.addresses = KotlinStringIterator(
                systemInterface.interfaceAddresses.map { it.toPrefix() }.iterator(),
            )

            var flags = 0
            if (networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (systemInterface.isLoopback) {
                flags = flags or OsConstants.IFF_LOOPBACK
            }
            if (systemInterface.isPointToPoint) {
                flags = flags or OsConstants.IFF_POINTOPOINT
            }
            if (systemInterface.supportsMulticast()) {
                flags = flags or OsConstants.IFF_MULTICAST
            }
            boxInterface.flags = flags
            boxInterface.metered =
                !networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            interfaces.add(boxInterface)
        }

        return if (interfaces.isEmpty()) {
            EmptyNetworkInterfaceIterator()
        } else {
            KotlinNetworkInterfaceIterator(interfaces.iterator())
        }
    }

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? = null

    override fun sendNotification(notification: Notification) {
        // no-op until foreground notification integration
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(appContext, listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(appContext, null)
    }

    override fun systemCertificates(): StringIterator = EmptyStringIterator()

    override fun underNetworkExtension(): Boolean = false

    override fun clearDNSCache() {
        // no-op
    }

    private fun InterfaceAddress.toPrefix(): String =
        if (address is Inet6Address) {
            "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
        } else {
            "${address.hostAddress}/$networkPrefixLength"
        }
}
