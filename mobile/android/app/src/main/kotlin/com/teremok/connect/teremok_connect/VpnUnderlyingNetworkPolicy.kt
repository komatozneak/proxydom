package com.teremok.connect.teremok_connect

import android.content.Context
import android.net.Network
import android.net.VpnService
import android.util.Log

/**
 * Bind TUN sockets to the **current OS default** underlying network.
 *
 * This is not a Wi‑Fi vs LTE picker: the user already chose the path in
 * Android. [VpnService.setUnderlyingNetworks] keeps lockdown from looping
 * VLESS into the TUN. Behavior lives in [DefaultNetworkMonitor].
 */
internal object VpnUnderlyingNetworkPolicy {
    private const val TAG = "VpnUnderlyingNetPolicy"

    data class Underlying(
        val network: Network,
        val interfaceName: String,
    )

    /**
     * Wait until a non-VPN underlying network is known (OS default).
     * Returns that iface or null on timeout.
     */
    fun awaitPreferred(context: Context, timeoutMs: Long = 5000): Underlying? {
        if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(context, timeoutMs)) {
            return null
        }
        val network = DefaultNetworkMonitor.defaultNetwork ?: return null
        val iface = DefaultNetworkMonitor.currentInterfaceName?.takeIf { it.isNotBlank() }
            ?: return null
        return Underlying(network, iface)
    }

    /**
     * Bind [vpn] outbound path to the current OS underlying network.
     * Must run after TUN [VpnService.Builder.establish] and before core dial.
     */
    fun applyTo(vpn: VpnService, underlying: Underlying? = null): Boolean {
        val picked = underlying
            ?: DefaultNetworkMonitor.defaultNetwork?.let { net ->
                val iface = DefaultNetworkMonitor.currentInterfaceName
                if (iface.isNullOrBlank()) null else Underlying(net, iface)
            }
        if (picked == null) {
            Log.w(TAG, "applyTo skipped — no underlying network")
            return false
        }
        return runCatching {
            vpn.setUnderlyingNetworks(arrayOf(picked.network))
            Log.i(TAG, "setUnderlyingNetworks iface=${picked.interfaceName}")
            DiagnosticRing.append(TAG, "net.iface ${picked.interfaceName}")
            true
        }.getOrElse {
            Log.w(TAG, "setUnderlyingNetworks failed iface=${picked.interfaceName}", it)
            false
        }
    }
}
