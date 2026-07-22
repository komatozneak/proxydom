package com.teremok.connect.teremok_connect

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface

/**
 * Отслеживает underlying network (cellular/wifi), не VPN-туннель.
 * Без этого direct/proxy outbound на Android «пустой» — трафик не уходит.
 */
internal object DefaultNetworkMonitor {
    private const val TAG = "DefaultNetworkMonitor"

    var defaultNetwork: Network? = null
        private set

    /** Last known underlying (non-VPN) interface name, e.g. rmnet1 / wlan0. */
    var currentInterfaceName: String? = null
        private set

    private var listener: InterfaceUpdateListener? = null
    private var connectivity: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun setListener(context: Context, updateListener: InterfaceUpdateListener?) {
        listener = updateListener
        if (updateListener == null) {
            stop(context)
            return
        }
        start(context)
        notifyCurrent(context)
    }

    /**
     * Запускает монитор до [io.nekohasekai.libbox.CommandServer.start] — иначе race:
     * VLESS к VPS стартует с пустым default interface.
     */
    fun prewarm(context: Context) {
        start(context.applicationContext)
    }

    /**
     * Ждёт underlying network (cellular/wifi), не VPN. Возвращает false по таймауту.
     */
    fun awaitUnderlyingNetwork(context: Context, timeoutMs: Long = 3000): Boolean {
        prewarm(context)
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (hasUnderlyingNetwork(context)) return true
            Thread.sleep(50)
        }
        Log.e(TAG, "underlying network not ready after ${timeoutMs}ms")
        return false
    }

    private fun hasUnderlyingNetwork(context: Context): Boolean {
        val cm = connectivity ?: context.getSystemService(ConnectivityManager::class.java)
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
            val lp = cm.getLinkProperties(network) ?: continue
            val iface = lp.interfaceName
            if (iface.isNullOrBlank() || iface.startsWith("tun")) continue
            defaultNetwork = network
            Log.i(TAG, "underlying network ready: $iface")
            listener?.let { notifyNetwork(cm, network) }
            return true
        }
        return defaultNetwork != null
    }

    private fun start(context: Context) {
        if (callback != null) return
        val cm = context.getSystemService(ConnectivityManager::class.java)
        connectivity = cm

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            .apply {
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.M) {
                    removeCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                    removeCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)
                }
            }
            .build()

        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                notifyNetwork(cm, network)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                notifyNetwork(cm, network)
            }

            override fun onLost(network: Network) {
                if (defaultNetwork == network) {
                    defaultNetwork = null
                    currentInterfaceName = null
                }
                listener?.updateDefaultInterface("", -1, false, false)
            }
        }
        callback = cb

        try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                    cm.registerBestMatchingNetworkCallback(request, cb, mainHandler)
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.P -> {
                    cm.requestNetwork(request, cb, mainHandler)
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.N -> {
                    cm.registerDefaultNetworkCallback(cb, mainHandler)
                }
                else -> {
                    cm.requestNetwork(request, cb)
                }
            }
            Log.i(TAG, "network monitor started (sdk=${Build.VERSION.SDK_INT})")
        } catch (e: Exception) {
            Log.e(TAG, "failed to start network monitor", e)
            callback = null
        }
    }

    private fun stop(context: Context) {
        val cm = connectivity ?: context.getSystemService(ConnectivityManager::class.java)
        val cb = callback ?: return
        runCatching { cm.unregisterNetworkCallback(cb) }
            .onFailure { Log.w(TAG, "unregisterNetworkCallback: ${it.message}") }
        callback = null
        connectivity = null
    }

    private fun notifyCurrent(context: Context) {
        val cm = connectivity ?: context.getSystemService(ConnectivityManager::class.java)
        // activeNetwork при поднятом VPN = tun0; ждём callback от registerBestMatchingNetworkCallback.
        val network = defaultNetwork
        if (network != null) {
            notifyNetwork(cm, network)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val active = cm.activeNetwork
            val caps = active?.let { cm.getNetworkCapabilities(it) }
            if (active != null && caps != null &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            ) {
                notifyNetwork(cm, active)
            } else {
                listener?.updateDefaultInterface("", -1, false, false)
            }
        } else {
            listener?.updateDefaultInterface("", -1, false, false)
        }
    }

    private fun notifyNetwork(cm: ConnectivityManager, network: Network) {
        defaultNetwork = network
        val updateListener = listener ?: return
        repeat(10) {
            val linkProperties = cm.getLinkProperties(network)
            if (linkProperties == null) {
                Thread.sleep(100)
                return@repeat
            }
            val interfaceName = linkProperties.interfaceName
            if (interfaceName.isNullOrBlank()) {
                Thread.sleep(100)
                return@repeat
            }
            val interfaceIndex = try {
                NetworkInterface.getByName(interfaceName)?.index ?: -1
            } catch (e: Exception) {
                Thread.sleep(100)
                return@repeat
            }
            updateListener.updateDefaultInterface(interfaceName, interfaceIndex, false, false)
            currentInterfaceName = interfaceName
            Log.i(TAG, "default interface: $interfaceName (index=$interfaceIndex)")
            return
        }
        updateListener.updateDefaultInterface("", -1, false, false)
    }
}
