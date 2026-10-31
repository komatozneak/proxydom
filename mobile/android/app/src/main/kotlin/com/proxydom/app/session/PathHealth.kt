package com.proxydom.app.session

import com.proxydom.app.NativeLog

import android.os.SystemClock
import com.proxydom.app.DiagnosticRing
import com.proxydom.app.TunnelHttpProbe
import com.proxydom.app.VpnPingMonitor
import com.proxydom.app.XRAY_SOCKS_PROBE_ATTEMPTS
import com.proxydom.app.XRAY_SOCKS_PROBE_RETRY_SLEEP_MS
import com.proxydom.app.XRAY_SOCKS_PROBE_TIMEOUT_MS
import com.proxydom.app.XRAY_SOCKS_WARMUP_BUDGET_MS
import com.proxydom.app.XRAY_SOCKS_WARMUP_POLL_MS
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Pre-connect prove + continuous path health.
 *
 * One facade for triple-core: [CoreAdapter.XraySocks] / [CoreAdapter.HysteriaSocks]
 * use SOCKS CONNECT to 1.1.1.1:443; [CoreAdapter.TrustTunnel] uses the same
 * CONNECT (SOCKS on the port of the running core, else TUN-direct TCP).
 * Handshake is not a prove. PathIncompatible never swaps cores.
 *
 * The continuous cycle reports the HTTP round trip it measured, so Home `ms` is
 * this probe and not a second one: [HealthResult.Ok] carries the sample, and
 * [DEGRADED_THRESHOLD] misses clear it.
 */
class PathHealth {
    enum class CoreAdapter {
        XraySocks,
        TrustTunnel,
        HysteriaSocks,
        ShareSocks,
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

    /**
     * Bumped by every [startContinuous]. A loop from an earlier start sees a
     * newer generation and ends, instead of waking into the new run's
     * `continuousRunning = true` and probing beside it.
     */
    private val runGeneration = AtomicInteger(0)

    /** Wait between probes; [probeNow] and [stopContinuous] end it early. */
    private val pauseLock = Object()

    /** Whether someone can see the Home `ms`: the screen is on. */
    @Volatile
    private var interactive: () -> Boolean = { true }
    private val consecutiveFails = AtomicInteger(0)

    /**
     * Kept-alive HTTP connection the continuous probe samples on. Reopening it
     * every five seconds paid the tunnel's stream setup on every sample.
     */
    @Volatile
    private var httpProbe: TunnelHttpProbe? = null

    /**
     * Adapter-aware pre-prove. TT and Xray/Hy2 all require SOCKS/TUN CONNECT.
     */
    fun proveEgress(
        adapter: CoreAdapter,
        socksPort: Int,
        alive: () -> Boolean,
        underlyingIface: String?,
        candidateLabel: String,
    ): HealthResult {
        if (!alive()) {
            return HealthResult.Fail(SessionReason.Cancelled, "generation cancelled", 0)
        }
        return when (adapter) {
            CoreAdapter.TrustTunnel ->
                proveTrustTunnelEgress(alive, underlyingIface, candidateLabel, socksPort)
            CoreAdapter.XraySocks, CoreAdapter.HysteriaSocks, CoreAdapter.ShareSocks ->
                proveXrayEgress(alive, underlyingIface, candidateLabel, socksPort)
        }
    }

    /**
     * TT Auto/manual: TCP CONNECT through the tunnel, not handshake-skip.
     * Prefers SOCKS on [socksPort] when that port accepts; otherwise TUN-direct.
     */
    fun proveTrustTunnelEgress(
        alive: () -> Boolean,
        underlyingIface: String?,
        candidateLabel: String,
        socksPort: Int,
    ): HealthResult {
        if (!alive()) {
            return HealthResult.Fail(SessionReason.Cancelled, "generation cancelled", 0)
        }
        if (VpnPingMonitor.isSocksReachable(port = socksPort, timeoutMs = 400)) {
            return proveXrayEgress(alive, underlyingIface, candidateLabel, socksPort)
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
                NativeLog.i(
                    TAG,
                    "prove tun-connect ok candidate=$candidateLabel underlying=$iface " +
                        "attempt=$attempt latency_ms=$latencyMs",
                )
                return HealthResult.Ok(rttMs = latencyMs, attempt = attempt)
            }
            NativeLog.w(
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
        socksPort: Int,
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
                if (VpnPingMonitor.isSocksReachable(
                        port = socksPort,
                        timeoutMs = XRAY_SOCKS_WARMUP_POLL_MS,
                    )
                ) {
                    break
                }
                Thread.sleep(50)
            }
            for (attempt in 1..XRAY_SOCKS_PROBE_ATTEMPTS) {
                if (!alive()) {
                    return HealthResult.Fail(SessionReason.Cancelled, "cancelled", attempt)
                }
                if (!VpnPingMonitor.isSocksReachable(port = socksPort, timeoutMs = 800)) {
                    NativeLog.w(
                        TAG,
                        "prove socks not ready candidate=$candidateLabel " +
                            "underlying=$iface socks=$socksPort " +
                            "attempt=$attempt/$XRAY_SOCKS_PROBE_ATTEMPTS",
                    )
                    Thread.sleep(XRAY_SOCKS_PROBE_RETRY_SLEEP_MS)
                    continue
                }
                val startedAt = SystemClock.elapsedRealtime()
                val outcome = VpnPingMonitor.socksConnectProbe(
                    socksPort = socksPort,
                    timeoutMs = XRAY_SOCKS_PROBE_TIMEOUT_MS,
                )
                val latencyMs = SystemClock.elapsedRealtime() - startedAt
                if (outcome is VpnPingMonitor.SocksHttpsResult.Ok) {
                    NativeLog.i(
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
                NativeLog.w(
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
     * Continuous path probe while the TUN is up. [ProxyDomVpnService] must
     * start this after ConnectedHealthy — otherwise a dead Hy2 path still
     * paints Nest connected (screen-off Doze).
     *
     * The first probe runs immediately: Home shows a number while the session
     * is still settling, instead of an ellipsis for a whole interval.
     */
    fun startContinuous(
        adapter: CoreAdapter,
        socksPort: Int,
        listener: Listener,
        alive: () -> Boolean,
        interactive: () -> Boolean = { true },
    ) {
        stopContinuous()
        this.interactive = interactive
        val generation = runGeneration.incrementAndGet()
        consecutiveFails.set(0)
        continuousRunning.set(true)
        if (adapter == CoreAdapter.TrustTunnel) {
            continuousThread = Thread(
                {
                    while (continuousRunning.get() && runGeneration.get() == generation && alive()) {
                        val rtt = runCatching {
                            VpnPingMonitor.tcpConnectRttMs(
                                timeoutMs = CONTINUOUS_PROBE_TIMEOUT_MS,
                            )
                        }.getOrNull()
                        if (rtt != null) {
                            consecutiveFails.set(0)
                            listener.onHealth(
                                HealthResult.Ok(rttMs = rtt, attempt = 0),
                            )
                        } else {
                            val n = consecutiveFails.incrementAndGet()
                            val detail = "continuous TT http fail n=$n"
                            if (n >= DEAD_THRESHOLD) {
                                listener.onHealth(HealthResult.Dead(n, detail))
                            } else if (n >= DEGRADED_THRESHOLD) {
                                listener.onHealth(HealthResult.Degraded(n, detail))
                            }
                        }
                        pauseBetweenProbes()
                    }
                },
                "proxydom-path-health",
            ).apply { isDaemon = true }
            continuousThread?.start()
            return
        }
        consecutiveFails.set(0)
        continuousRunning.set(true)
        val probe = TunnelHttpProbe(socksPort = socksPort)
        httpProbe = probe
        continuousThread = Thread(
            {
                NativeLog.i(TAG, "continuous socks probe port=$socksPort")
                while (continuousRunning.get() && runGeneration.get() == generation && alive()) {
                    // One request on the kept-alive connection: a single round
                    // trip, without paying the tunnel's stream setup each time.
                    val rtt = probe.sample(CONTINUOUS_PROBE_TIMEOUT_MS)
                    if (rtt != null) {
                        consecutiveFails.set(0)
                        listener.onHealth(
                            HealthResult.Ok(rttMs = rtt, attempt = 0),
                        )
                    } else {
                        val n = consecutiveFails.incrementAndGet()
                        val detail = continuousSocksFailDetail(n, socksPort)
                        if (n >= DEAD_THRESHOLD) {
                            listener.onHealth(HealthResult.Dead(n, detail))
                        } else if (n >= DEGRADED_THRESHOLD) {
                            listener.onHealth(HealthResult.Degraded(n, detail))
                        }
                    }
                    pauseBetweenProbes()
                }
            },
            "proxydom-path-health",
        ).apply { isDaemon = true }
        continuousThread?.start()
    }

    /**
     * Wait one interval between probes.
     *
     * The probe is also the Home `ms`, so while the screen is on it keeps its
     * five seconds. With the screen off nobody reads the number and a healthy
     * path is checked every thirty seconds, which keeps the radio idle in
     * between. The first miss puts it back on five seconds until the path
     * answers again, so a dead path is still called within one long wait plus
     * three short ones (about 45 s) rather than four long ones. [probeNow] cuts
     * the wait short when the screen comes back, so Home never shows a stale
     * reading.
     *
     * One timed wait, not a loop of 200 ms sleeps: those woke the CPU five
     * times a second for the whole session.
     */
    private fun pauseBetweenProbes() {
        val interval = if (interactive() || consecutiveFails.get() > 0) {
            CONTINUOUS_INTERVAL_MS
        } else {
            SCREEN_OFF_INTERVAL_MS
        }
        synchronized(pauseLock) {
            if (!continuousRunning.get()) return
            try {
                pauseLock.wait(interval)
            } catch (_: InterruptedException) {
                return
            }
        }
    }

    /** Probe without waiting out the interval (the screen just came on). */
    fun probeNow() {
        synchronized(pauseLock) { pauseLock.notifyAll() }
    }

    fun stopContinuous() {
        continuousRunning.set(false)
        probeNow()
        continuousThread?.interrupt()
        continuousThread = null
        httpProbe?.close()
        httpProbe = null
        consecutiveFails.set(0)
    }

    companion object {
        private const val TAG = "PathHealth"
        private const val CONTINUOUS_INTERVAL_MS = 5_000L
        private const val SCREEN_OFF_INTERVAL_MS = 30_000L
        private const val CONTINUOUS_PROBE_TIMEOUT_MS = 2_500
        const val DEGRADED_THRESHOLD = 2
        const val DEAD_THRESHOLD = 4

        /** Fail line names the port that was probed, not the Hy2 constant. */
        fun continuousSocksFailDetail(consecutiveFails: Int, socksPort: Int): String =
            "continuous fail n=$consecutiveFails socks=$socksPort"
    }
}
