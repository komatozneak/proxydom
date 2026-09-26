package com.teremok.connect.teremok_connect.session

import android.os.SystemClock
import android.util.Log
import com.teremok.connect.teremok_connect.DiagnosticRing
import com.teremok.connect.teremok_connect.GvisorTun2Socks
import com.teremok.connect.teremok_connect.VpnPingMonitor
import com.teremok.connect.teremok_connect.XRAY_SOCKS_PROBE_ATTEMPTS
import com.teremok.connect.teremok_connect.XRAY_SOCKS_PROBE_RETRY_SLEEP_MS
import com.teremok.connect.teremok_connect.XRAY_SOCKS_PROBE_TIMEOUT_MS
import com.teremok.connect.teremok_connect.XRAY_SOCKS_WARMUP_BUDGET_MS
import com.teremok.connect.teremok_connect.XRAY_SOCKS_WARMUP_POLL_MS
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Pre-connect prove + continuous path health (ADR 014).
 *
 * One facade for triple-core: [CoreAdapter.XraySocks] / [CoreAdapter.HysteriaSocks]
 * use SOCKS CONNECT to 1.1.1.1:443; [CoreAdapter.TrustTunnel] uses the same
 * CONNECT (SOCKS if :10808 is up, else TUN-direct TCP). Handshake is not a
 * prove. PathIncompatible never swaps cores.
 */
class PathHealth {
    enum class CoreAdapter {
        XraySocks,
        TrustTunnel,
        HysteriaSocks,
    }

    fun interface Listener {
        fun onHealth(result: HealthResult)
    }

    sealed class HealthResult {
        data class Ok(val rttMs: Long, val attempt: Int) : HealthResult()
        data class Fail(
            val reason: SessionReason,
            val detail: String,
            val attempt: Int,
        ) : HealthResult()
        data class Degraded(val consecutiveFails: Int, val detail: String) : HealthResult()
        data class Dead(val consecutiveFails: Int, val detail: String) : HealthResult()
    }

    private val continuousRunning = AtomicBoolean(false)
    private var continuousThread: Thread? = null
    private val consecutiveFails = AtomicInteger(0)

    /**
     * Adapter-aware pre-prove. TT and Xray/Hy2 all require SOCKS/TUN CONNECT.
     */
    fun proveEgress(
        adapter: CoreAdapter,
        alive: () -> Boolean,
        underlyingIface: String?,
        candidateLabel: String,
    ): HealthResult {
        if (!alive()) {
            return HealthResult.Fail(SessionReason.Cancelled, "generation cancelled", 0)
        }
        return when (adapter) {
            CoreAdapter.TrustTunnel ->
                proveTrustTunnelEgress(alive, underlyingIface, candidateLabel)
            CoreAdapter.XraySocks, CoreAdapter.HysteriaSocks ->
                proveXrayEgress(alive, underlyingIface, candidateLabel)
        }
    }

    /**
     * TT Auto/manual: TCP CONNECT through the tunnel, not handshake-skip.
     * Prefers SOCKS when :10808 is up; otherwise TUN-direct (no protect).
     */
    fun proveTrustTunnelEgress(
        alive: () -> Boolean,
        underlyingIface: String?,
        candidateLabel: String,
    ): HealthResult {
        if (!alive()) {
            return HealthResult.Fail(SessionReason.Cancelled, "generation cancelled", 0)
        }
        if (VpnPingMonitor.isSocksReachable(timeoutMs = 400)) {
            return proveXrayEgress(alive, underlyingIface, candidateLabel)
        }
        val iface = underlyingIface ?: "(unknown)"
        for (attempt in 1..XRAY_SOCKS_PROBE_ATTEMPTS) {
            if (!alive()) {
                return HealthResult.Fail(SessionReason.Cancelled, "cancelled", attempt)
            }
            val startedAt = SystemClock.elapsedRealtime()
            val rtt = VpnPingMonitor.tcpConnectRttMs(
                timeoutMs = XRAY_SOCKS_PROBE_TIMEOUT_MS,
            )
            val latencyMs = rtt ?: (SystemClock.elapsedRealtime() - startedAt)
            if (rtt != null) {
                Log.i(
                    TAG,
                    "prove tun-connect ok candidate=$candidateLabel underlying=$iface " +
                        "attempt=$attempt latency_ms=$latencyMs",
                )
                return HealthResult.Ok(rttMs = latencyMs, attempt = attempt)
            }
            Log.w(
                TAG,
                "prove tun-connect fail candidate=$candidateLabel underlying=$iface " +
                    "attempt=$attempt",
            )
            Thread.sleep(XRAY_SOCKS_PROBE_RETRY_SLEEP_MS)
        }
        return HealthResult.Fail(
            SessionReason.PathIncompatible,
            "TT CONNECT prove exhausted underlying=$iface",
            XRAY_SOCKS_PROBE_ATTEMPTS,
        )
    }

    /**
     * Blocking pre-prove on caller (engine) thread. Checks [alive] between attempts.
     */
    fun proveXrayEgress(
        alive: () -> Boolean,
        underlyingIface: String?,
        candidateLabel: String,
    ): HealthResult {
        if (!alive()) {
            return HealthResult.Fail(SessionReason.Cancelled, "generation cancelled", 0)
        }
        val iface = underlyingIface ?: "(unknown)"
        try {
            val warmupDeadline = SystemClock.elapsedRealtime() + XRAY_SOCKS_WARMUP_BUDGET_MS
            while (SystemClock.elapsedRealtime() < warmupDeadline) {
                if (!alive()) {
                    return HealthResult.Fail(SessionReason.Cancelled, "cancelled warmup", 0)
                }
                if (VpnPingMonitor.isSocksReachable(timeoutMs = XRAY_SOCKS_WARMUP_POLL_MS)) {
                    break
                }
                Thread.sleep(50)
            }
            for (attempt in 1..XRAY_SOCKS_PROBE_ATTEMPTS) {
                if (!alive()) {
                    return HealthResult.Fail(SessionReason.Cancelled, "cancelled", attempt)
                }
                if (!VpnPingMonitor.isSocksReachable(timeoutMs = 800)) {
                    Log.w(
                        TAG,
                        "prove socks not ready candidate=$candidateLabel " +
                            "underlying=$iface attempt=$attempt/$XRAY_SOCKS_PROBE_ATTEMPTS",
                    )
                    Thread.sleep(XRAY_SOCKS_PROBE_RETRY_SLEEP_MS)
                    continue
                }
                val startedAt = SystemClock.elapsedRealtime()
                val outcome = VpnPingMonitor.socksConnectProbe(
                    timeoutMs = XRAY_SOCKS_PROBE_TIMEOUT_MS,
                )
                val latencyMs = SystemClock.elapsedRealtime() - startedAt
                if (outcome is VpnPingMonitor.SocksHttpsResult.Ok) {
                    Log.i(
                        TAG,
                        "prove ok candidate=$candidateLabel underlying=$iface " +
                            "attempt=$attempt latency_ms=$latencyMs",
                    )
                    DiagnosticRing.event(
                        "info",
                        "vpn.prove",
                        "ok=true candidate=$candidateLabel attempt=$attempt",
                    )
                    return HealthResult.Ok(rttMs = latencyMs, attempt = attempt)
                }
                Log.w(
                    TAG,
                    "prove fail candidate=$candidateLabel underlying=$iface " +
                        "attempt=$attempt/$XRAY_SOCKS_PROBE_ATTEMPTS " +
                        "latency_ms=$latencyMs err=${outcome.detail}",
                )
                DiagnosticRing.event(
                    "debug",
                    "vpn.prove",
                    "ok=false candidate=$candidateLabel reason=${outcome.detail}",
                )
                Thread.sleep(XRAY_SOCKS_PROBE_RETRY_SLEEP_MS)
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            return HealthResult.Fail(SessionReason.Cancelled, "interrupted", 0)
        }
        return HealthResult.Fail(
            SessionReason.EgressTimeout,
            "SOCKS CONNECT prove exhausted underlying=$iface",
            XRAY_SOCKS_PROBE_ATTEMPTS,
        )
    }

    /**
     * Continuous SOCKS CONNECT while the TUN is up. [TeremokVpnService] must
     * start this after ConnectedHealthy — otherwise a dead Hy2 path still
     * paints Nest connected (screen-off Doze).
     */
    fun startContinuous(
        adapter: CoreAdapter,
        listener: Listener,
        alive: () -> Boolean,
    ) {
        stopContinuous()
        consecutiveFails.set(0)
        continuousRunning.set(true)
        if (adapter == CoreAdapter.TrustTunnel) {
            continuousThread = Thread(
                {
                    while (continuousRunning.get() && alive()) {
                        try {
                            Thread.sleep(CONTINUOUS_INTERVAL_MS)
                        } catch (_: InterruptedException) {
                            break
                        }
                        if (!continuousRunning.get() || !alive()) break
                        val ok = runCatching {
                            VpnPingMonitor.tcpConnectRttMs(
                                timeoutMs = CONTINUOUS_PROBE_TIMEOUT_MS,
                            ) != null
                        }.getOrDefault(false)
                        if (ok) {
                            consecutiveFails.set(0)
                            listener.onHealth(HealthResult.Ok(rttMs = 0, attempt = 0))
                        } else {
                            val n = consecutiveFails.incrementAndGet()
                            val detail = "continuous TT http fail n=$n"
                            if (n >= DEAD_THRESHOLD) {
                                listener.onHealth(HealthResult.Dead(n, detail))
                            } else if (n >= DEGRADED_THRESHOLD) {
                                listener.onHealth(HealthResult.Degraded(n, detail))
                            }
                        }
                    }
                },
                "teremok-path-health",
            ).apply { isDaemon = true }
            continuousThread?.start()
            return
        }
        consecutiveFails.set(0)
        continuousRunning.set(true)
        continuousThread = Thread(
            {
                while (continuousRunning.get() && alive()) {
                    try {
                        Thread.sleep(CONTINUOUS_INTERVAL_MS)
                    } catch (_: InterruptedException) {
                        break
                    }
                    if (!continuousRunning.get() || !alive()) break
                    val ok = runCatching {
                        if (!VpnPingMonitor.isSocksReachable(timeoutMs = 800)) {
                            false
                        } else {
                            VpnPingMonitor.socksConnectOk(
                                timeoutMs = CONTINUOUS_PROBE_TIMEOUT_MS,
                            )
                        }
                    }.getOrDefault(false)
                    if (ok) {
                        consecutiveFails.set(0)
                        listener.onHealth(HealthResult.Ok(rttMs = 0, attempt = 0))
                    } else {
                        val n = consecutiveFails.incrementAndGet()
                        val detail = "continuous fail n=$n socks=${GvisorTun2Socks.SOCKS_PORT}"
                        if (n >= DEAD_THRESHOLD) {
                            listener.onHealth(HealthResult.Dead(n, detail))
                        } else if (n >= DEGRADED_THRESHOLD) {
                            listener.onHealth(HealthResult.Degraded(n, detail))
                        }
                    }
                }
            },
            "teremok-path-health",
        ).apply { isDaemon = true }
        continuousThread?.start()
    }

    fun stopContinuous() {
        continuousRunning.set(false)
        continuousThread?.interrupt()
        continuousThread = null
        consecutiveFails.set(0)
    }

    companion object {
        private const val TAG = "PathHealth"
        private const val CONTINUOUS_INTERVAL_MS = 5_000L
        private const val CONTINUOUS_PROBE_TIMEOUT_MS = 2_500
        const val DEGRADED_THRESHOLD = 2
        const val DEAD_THRESHOLD = 4
    }
}
