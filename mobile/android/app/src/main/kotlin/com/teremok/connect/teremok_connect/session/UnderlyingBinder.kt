package com.teremok.connect.teremok_connect.session

import android.content.Context
import android.net.Network
import android.net.VpnService
import com.teremok.connect.teremok_connect.DefaultNetworkMonitor
import com.teremok.connect.teremok_connect.VpnUnderlyingNetworkPolicy

/**
 * Public current OS underlying for establish (ADR 014).
 * Pinning mid-session is [DefaultNetworkMonitor] + [VpnUnderlyingNetworkPolicy].
 */
data class PreferredUnderlying(
    val network: Network,
    val interfaceName: String,
)

internal class UnderlyingBinder(
    private val appContext: Context,
) {
    fun awaitPreferred(timeoutMs: Long = 5_000): PreferredUnderlying? =
        VpnUnderlyingNetworkPolicy.awaitPreferred(appContext, timeoutMs)?.let {
            PreferredUnderlying(it.network, it.interfaceName)
        }

    fun applyTo(vpn: VpnService, underlying: PreferredUnderlying?): Boolean =
        VpnUnderlyingNetworkPolicy.applyTo(
            vpn,
            underlying?.let {
                VpnUnderlyingNetworkPolicy.Underlying(it.network, it.interfaceName)
            },
        )

    fun currentIface(): String? = DefaultNetworkMonitor.currentInterfaceName
}
