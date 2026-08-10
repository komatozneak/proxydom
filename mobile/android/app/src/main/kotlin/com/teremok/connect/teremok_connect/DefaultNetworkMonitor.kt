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
import java.net.NetworkInterface

/**
 * Tracks the underlying network (cellular/wifi), not the VPN tunnel.
 * Needed so outbound proxy sockets bind to a real interface and so
 * [VpnService.setUnderlyingNetworks] can keep the VPN validated.
 */
internal object DefaultNetworkMonitor {
    private const val TAG = "DefaultNetworkMonitor"

    var defaultNetwork: Network? = null
        private set

    /** Last known underlying (non-VPN) interface name, e.g. rmnet1 / wlan0. */
    var currentInterfaceName: String? = null
        private set

    private var connectivity: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Start monitoring before Xray/TT dial so protect() has a physical path. */
    fun prewarm(context: Context) {
        start(context.applicationContext)
    }

    /**
     * Waits for an underlying network (cellular/wifi), not VPN.
     * Returns false on timeout.
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
            currentInterfaceName = iface
            Log.i(TAG, "underlying network ready: $iface")
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
                rememberNetwork(cm, network)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                rememberNetwork(cm, network)
            }

            override fun onLost(network: Network) {
                if (defaultNetwork == network) {
                    defaultNetwork = null
                    currentInterfaceName = null
                }
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

    private fun rememberNetwork(cm: ConnectivityManager, network: Network) {
        val caps = cm.getNetworkCapabilities(network)
        if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
            return
        }
        defaultNetwork = network
        repeat(10) {
            val linkProperties = cm.getLinkProperties(network) ?: run {
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
            } catch (_: Exception) {
                Thread.sleep(100)
                return@repeat
            }
            currentInterfaceName = interfaceName
            Log.i(TAG, "default interface: $interfaceName (index=$interfaceIndex)")
            return
        }
    }
}
