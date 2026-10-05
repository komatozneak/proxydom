package com.proxydom.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.VpnService
import android.os.Handler
import android.os.Looper

/**
 * Bind TUN sockets to the **current OS default** underlying network.
 *
 * This is not a Wi‑Fi vs LTE picker: the user already chose the path in
 * Android. [VpnService.setUnderlyingNetworks] keeps lockdown from looping
 * VLESS into the TUN. Behavior lives in [DefaultNetworkMonitor].
 */
internal object VpnUnderlyingNetworkPolicy {
    private const val TAG = "VpnUnderlyingNetPolicy"

    private val bindLog: NetBindLog by lazy {
        val handler = Handler(Looper.getMainLooper())
        NetBindLog(
            emit = { level, event, fields ->
                DiagnosticRing.event(level, event, fields)
            },
            postDelayed = { delay, task -> handler.postDelayed(task, delay) },
            cancel = { task -> handler.removeCallbacks(task) },
        )
    }

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
     * Pin this process (Flutter Dio / Dart sockets) to Wi‑Fi/LTE, not tun0.
     *
     * VpnService.protect() is only for native Hy2 fds. Unprotected Dart
     * connect() to the control plane gets EACCES (errno 13) while a leftover
     * TUN / Always-on lockdown is up — even when INTERNET is granted.
     */
    fun bindProcess(context: Context, timeoutMs: Long = 3_000): Boolean {
        DefaultNetworkMonitor.prewarm(context)
        if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(context, timeoutMs)) {
            NativeLog.w(TAG, "bindProcess skipped — no underlying network")
            return false
        }
        val net = DefaultNetworkMonitor.defaultNetwork ?: return false
        val iface = DefaultNetworkMonitor.currentInterfaceName ?: "(unknown)"
        return bindProcessTo(context, net, iface)
    }

    /**
     * Pin Dart DNS/sockets to [network]. Call on every physical iface change:
     * a boot-time bind stays on the old [Network] after Wi‑Fi/LTE flap and
     * getaddrinfo then returns EAI_NODATA (errno 7).
     */
    fun bindProcessTo(context: Context, network: Network, iface: String): Boolean {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        return runCatching {
            val ok = cm.bindProcessToNetwork(network)
            NativeLog.i(TAG, "bindProcessToNetwork iface=$iface ok=$ok")
            bindLog.record(iface, ok)
            ok
        }.getOrElse {
            NativeLog.w(TAG, "bindProcessToNetwork failed iface=$iface", it)
            bindLog.record(iface, false)
            false
        }
    }

    /**
     * Drop the process bind so the OS default is used.
     * Only when TUN is down — null while the tunnel is up sends Dio into tun0.
     */
    fun clearProcessBind(context: Context): Boolean {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        return runCatching {
            val ok = cm.bindProcessToNetwork(null)
            NativeLog.i(TAG, "bindProcessToNetwork clear ok=$ok")
            DiagnosticRing.event(
                if (ok) "debug" else "error",
                "net.bind",
                "action=clear ok=$ok",
            )
            ok
        }.getOrElse {
            NativeLog.w(TAG, "bindProcessToNetwork clear failed", it)
            false
        }
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
            NativeLog.w(TAG, "applyTo skipped — no underlying network")
            return false
        }
        return runCatching {
            vpn.setUnderlyingNetworks(arrayOf(picked.network))
            NativeLog.i(TAG, "setUnderlyingNetworks iface=${picked.interfaceName}")
            DiagnosticRing.event("debug", "net.iface", "iface=${picked.interfaceName}")
            true
        }.getOrElse {
            NativeLog.w(TAG, "setUnderlyingNetworks failed iface=${picked.interfaceName}", it)
            DiagnosticRing.event(
                "error",
                "net.iface",
                "iface=${picked.interfaceName} ok=false",
            )
            false
        }
    }
}
