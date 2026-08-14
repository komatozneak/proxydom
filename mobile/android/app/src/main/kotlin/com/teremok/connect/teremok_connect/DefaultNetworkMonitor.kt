package com.teremok.connect.teremok_connect

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Tracks the OS physical underlying network (cellular/wifi), not the VPN tunnel.
 *
 * Same pattern as Огонь `XrayVpnService`: default callback + NOT_VPN callback,
 * skip VPN, keep last physical, [VpnService.setUnderlyingNetworks] when the
 * service is up. [NET_CAPABILITY_VALIDATED] is read, never requested.
 */
internal object DefaultNetworkMonitor {
    private const val TAG = "DefaultNetworkMonitor"

    var defaultNetwork: Network? = null
        private set

    /** Last known underlying (non-VPN) interface name, e.g. rmnet1 / wlan0. */
    var currentInterfaceName: String? = null
        private set

    private var connectivity: ConnectivityManager? = null
    private var defaultCallback: ConnectivityManager.NetworkCallback? = null
    private var physicalCallback: ConnectivityManager.NetworkCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun prewarm(context: Context) {
        start(context.applicationContext)
    }

    /**
     * Waits for a physical network (cellular/wifi), not VPN.
     * Returns false on timeout.
     */
    fun awaitUnderlyingNetwork(context: Context, timeoutMs: Long = 3000): Boolean {
        prewarm(context)
        val cm = connectivity ?: context.getSystemService(ConnectivityManager::class.java)
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (hasPhysical()) return true
            val active = cm.activeNetwork
            if (!isVpn(cm, active)) {
                consider(cm, active, allowReplace = true)
            }
            if (hasPhysical()) return true
            Thread.sleep(50)
        }
        Log.e(TAG, "underlying network not ready after ${timeoutMs}ms")
        return false
    }

    private fun hasPhysical(): Boolean =
        defaultNetwork != null && !currentInterfaceName.isNullOrBlank()

    private fun physicalRequest(): NetworkRequest =
        NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

    private fun start(context: Context) {
        if (defaultCallback != null) return
        val cm = context.getSystemService(ConnectivityManager::class.java)
        connectivity = cm

        val defaultCb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                consider(cm, network, allowReplace = true)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                consider(cm, network, allowReplace = true)
            }

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) {
                consider(cm, network, allowReplace = false)
            }

            override fun onLost(network: Network) {
                // Default moved (often onto the VPN). Last physical stays.
            }
        }

        val physicalCb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                consider(cm, network, allowReplace = true)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                consider(cm, network, allowReplace = true)
            }

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) {
                consider(cm, network, allowReplace = false)
            }

            override fun onLost(network: Network) {
                if (defaultNetwork == network) {
                    defaultNetwork = null
                    currentInterfaceName = null
                    Log.i(TAG, "physical underlying lost")
                    DiagnosticRing.append(TAG, "net.lost")
                }
                val active = cm.activeNetwork
                if (!isVpn(cm, active)) {
                    consider(cm, active, allowReplace = true)
                }
            }
        }

        defaultCallback = defaultCb
        physicalCallback = physicalCb

        try {
            cm.registerDefaultNetworkCallback(defaultCb, mainHandler)
            cm.registerNetworkCallback(physicalRequest(), physicalCb, mainHandler)
            Log.i(TAG, "network monitor started (default + NOT_VPN)")
        } catch (e: Exception) {
            Log.e(TAG, "failed to start network monitor", e)
            runCatching { cm.unregisterNetworkCallback(defaultCb) }
            runCatching { cm.unregisterNetworkCallback(physicalCb) }
            defaultCallback = null
            physicalCallback = null
        }
        val active = cm.activeNetwork
        if (!isVpn(cm, active)) {
            consider(cm, active, allowReplace = true)
        }
    }

    private fun isVpn(cm: ConnectivityManager, network: Network?): Boolean {
        if (network == null) return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        val iface = cm.getLinkProperties(network)?.interfaceName
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
            (iface?.startsWith("tun") == true)
    }

    /**
     * Ignore VPN. First physical INTERNET net is kept even if not yet validated.
     * Unvalidated Wi‑Fi does not replace an already pinned LTE (or other) net.
     * A validated different net may replace from [onAvailable] or
     * [onCapabilitiesChanged] ([allowReplace]); link-property updates do not.
     */
    private fun consider(
        cm: ConnectivityManager,
        network: Network?,
        allowReplace: Boolean,
    ) {
        if (network == null) return
        val caps = cm.getNetworkCapabilities(network) ?: return
        val iface = cm.getLinkProperties(network)?.interfaceName
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
            iface?.startsWith("tun") == true
        ) {
            Log.d(TAG, "skip vpn iface=${iface ?: "(none)"}")
            return
        }
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            Log.i(TAG, "skip no-internet iface=${iface ?: "(none)"}")
            return
        }
        if (iface.isNullOrBlank()) {
            Log.i(TAG, "skip no-iface")
            return
        }
        val validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        val current = defaultNetwork
        if (current != null && current != network) {
            if (!allowReplace) {
                Log.i(TAG, "skip link-only other iface=$iface current=$currentInterfaceName")
                return
            }
            if (!validated) {
                Log.i(TAG, "skip unvalidated replace iface=$iface current=$currentInterfaceName")
                return
            }
        }
        rememberAndPin(network, iface)
    }

    private fun rememberAndPin(network: Network, iface: String) {
        if (defaultNetwork == network && currentInterfaceName == iface) {
            Log.d(TAG, "skip same iface=$iface")
            return
        }
        defaultNetwork = network
        currentInterfaceName = iface
        Log.i(TAG, "default interface: $iface")
        DiagnosticRing.append(TAG, "net.iface $iface")
        val vpn = TeremokVpnService.currentInstance() ?: return
        VpnUnderlyingNetworkPolicy.applyTo(
            vpn,
            VpnUnderlyingNetworkPolicy.Underlying(network, iface),
        )
    }
}
