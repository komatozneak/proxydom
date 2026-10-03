package com.proxydom.app.session

import android.util.Log
import com.proxydom.app.DefaultNetworkMonitor
import com.proxydom.app.DiagnosticRing
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Sole VPN session owner (ADR 014): FSM + generation + serial start/stop.
 *
 * Host ([ProxyDomVpnService]) implements [Host] for TUN/core I/O; the engine
 * never blocks the main thread.
 */
class VpnSessionEngine(
    private val host: Host,
) {
    interface Host {
        fun onSnapshot(snapshot: SessionSnapshot)
        /** Establish TUN + core + pre-prove; return true if Healthy. */
        fun establishGeneration(
            generation: Long,
            username: String,
            protocol: String,
            params: Map<String, Any?>,
            alive: () -> Boolean,
            emit: (SessionSnapshot) -> Unit,
        ): Boolean
        fun teardownGeneration(generation: Long)
        fun onPathDegraded(generation: Long, detail: String)
        fun onPathDead(generation: Long, detail: String)
        fun onUnderlyingChangedWhileUp(generation: Long, iface: String?)
        /**
         * True while native is retrying a dead Hy2 path. Skip Error snapshot so
         * Flutter auto-reconnect does not fight the in-service recover.
         */
        fun suppressEstablishError(): Boolean = false
        /**
         * SOCKS-only (Xray/Hy2) or TUN+HTTPS (TT) prove. Must not leave a
         * Healthy session unless TT already has a live tunnel.
         */
        fun proveCandidateSocks(
            username: String,
            protocol: String,
            params: Map<String, Any?>,
            alive: () -> Boolean,
        ): Boolean
        /** Persist the Auto winner so Always-on restore is a single mint, not the pool. */
        fun persistAutoWinner(candidate: AutoCandidate) {}
        /** Auto pool missed — do not let Always-on resurrect the previous hop. */
        fun markPersistedInactive() {}

        /**
         * Text already stored by failStart (SOCKS probe, protect, Hy2).
         * Engine must not replace it with a generic establish failure.
         */
        fun lastStartFailure(): String? = null
    }

    private val dispatcher: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "proxydom-vpn-session").apply { isDaemon = true }
    }

    @Volatile
    private var snapshot: SessionSnapshot = SessionSnapshot.idle(0L)

    fun currentSnapshot(): SessionSnapshot = snapshot

    fun currentGeneration(): Long = generationClock.get()

    fun isAlive(gen: Long): Boolean = generationClock.get() == gen

    /**
     * Enqueue connect. Bumps generation (cancels in-flight establish).
     * Returns the generation Flutter must wait for.
     *
     * @param preferredGeneration when > 0, adopt this id (pre-allocated by
     *   MethodChannel before [android.app.Service] start).
     */
    fun enqueueStart(
        username: String,
        protocol: String,
        params: Map<String, Any?>,
        preferredGeneration: Long = 0L,
    ): Long {
        val gen = if (preferredGeneration > 0L) {
            generationClock.updateAndGet { cur -> maxOf(cur, preferredGeneration) }
        } else {
            generationClock.incrementAndGet()
        }
        Log.i(TAG, "enqueueStart generation=$gen preferred=$preferredGeneration")
        dispatcher.execute {
            runStart(gen, username, protocol, params)
        }
        return gen
    }

    /**
     * Auto: sequential data-plane prove. First Ok gets [Host.establishGeneration].
     */
    fun enqueueAutoStart(
        candidates: List<AutoCandidate>,
        preferredGeneration: Long = 0L,
    ): Long {
        val gen = if (preferredGeneration > 0L) {
            generationClock.updateAndGet { cur -> maxOf(cur, preferredGeneration) }
        } else {
            generationClock.incrementAndGet()
        }
        Log.i(TAG, "enqueueAutoStart generation=$gen n=${candidates.size}")
        dispatcher.execute {
            runAuto(gen, candidates)
        }
        return gen
    }

    /**
     * Enqueue stop on the **same** dispatcher as start (ADR 014).
     */
    fun enqueueStop(markInactive: Boolean = true): Long {
        val gen = generationClock.incrementAndGet()
        Log.i(TAG, "enqueueStop generation=$gen markInactive=$markInactive")
        dispatcher.execute {
            runStop(gen)
        }
        return gen
    }

    fun notifyUnderlyingChanged(iface: String?) {
        val gen = generationClock.get()
        val phase = snapshot.phase
        if (phase != SessionPhase.ConnectedHealthy && phase != SessionPhase.ConnectedDegraded) {
            return
        }
        if (iface.isNullOrBlank() || iface == snapshot.underlyingIface) {
            return
        }
        dispatcher.execute {
            if (!isAlive(gen)) return@execute
            host.onUnderlyingChangedWhileUp(gen, iface)
        }
    }

    fun notifyHealth(result: PathHealth.HealthResult) {
        val gen = generationClock.get()
        dispatcher.execute {
            if (!isAlive(gen)) return@execute
            when (result) {
                is PathHealth.HealthResult.Ok -> {
                    if (snapshot.phase == SessionPhase.ConnectedDegraded) {
                        publish(
                            snapshot.copy(
                                phase = SessionPhase.ConnectedHealthy,
                                reason = SessionReason.EgressOk,
                                detail = null,
                            ),
                        )
                    }
                }
                is PathHealth.HealthResult.Degraded -> {
                    publish(
                        snapshot.copy(
                            phase = SessionPhase.ConnectedDegraded,
                            reason = SessionReason.Degraded,
                            detail = result.detail,
                        ),
                    )
                    host.onPathDegraded(gen, result.detail)
                }
                is PathHealth.HealthResult.Dead -> {
                    publish(
                        snapshot.copy(
                            phase = SessionPhase.ConnectedDegraded,
                            reason = SessionReason.Dead,
                            detail = result.detail,
                        ),
                    )
                    host.onPathDead(gen, result.detail)
                }
                is PathHealth.HealthResult.Fail -> Unit
            }
        }
    }

    fun shutdown() {
        generationClock.incrementAndGet()
        dispatcher.shutdownNow()
    }

    private fun runStart(
        gen: Long,
        username: String,
        protocol: String,
        params: Map<String, Any?>,
    ) {
        if (!isAlive(gen)) {
            Log.i(TAG, "runStart skipped stale generation=$gen")
            return
        }
        // Tear down any previous tunnel before establish.
        host.teardownGeneration(gen)
        if (!isAlive(gen)) return

        publish(
            SessionSnapshot(
                phase = SessionPhase.Binding,
                generation = gen,
            ),
        )
        val ok = try {
            host.establishGeneration(
                generation = gen,
                username = username,
                protocol = protocol,
                params = params,
                alive = { isAlive(gen) },
                emit = { snap ->
                    if (isAlive(gen)) publish(snap.copy(generation = gen))
                },
            )
        } catch (e: Exception) {
            Log.e(TAG, "establishGeneration failed gen=$gen", e)
            if (isAlive(gen)) {
                publish(
                    SessionSnapshot(
                        phase = SessionPhase.Error,
                        generation = gen,
                        reason = SessionReason.Unknown,
                        detail = e.message ?: "establish failed",
                    ),
                )
                host.teardownGeneration(gen)
            }
            return
        }
        if (!isAlive(gen)) {
            host.teardownGeneration(gen)
            return
        }
        if (!ok) {
            // Host already published Error + tore down via failStart,
            // unless a silent dead-tunnel recover is already scheduled.
            if (isAlive(gen) &&
                snapshot.phase != SessionPhase.Error &&
                !host.suppressEstablishError()
            ) {
                publish(
                    SessionSnapshot(
                        phase = SessionPhase.Error,
                        generation = gen,
                        reason = SessionReason.EgressTimeout,
                        candidateId = nodeIdFromParams(params),
                        candidateHost = hostFromParams(params),
                        detail = establishFailureDetail(host.lastStartFailure()),
                    ),
                )
                host.teardownGeneration(gen)
            }
            return
        }
        publishConnectedHealthy(
            gen = gen,
            candidateId = nodeIdFromParams(params),
            candidateHost = hostFromParams(params),
            detail = "establish ok",
        )
    }

    private fun runAuto(gen: Long, candidates: List<AutoCandidate>) {
        if (!isAlive(gen)) return
        host.teardownGeneration(gen)
        if (!isAlive(gen)) return
        publish(
            SessionSnapshot(
                phase = SessionPhase.Binding,
                generation = gen,
                detail = "auto n=${candidates.size}",
            ),
        )
        val winner = AutoProveLoop.firstSuccess(candidates) { cand ->
            if (!isAlive(gen)) return@firstSuccess false
            publish(
                SessionSnapshot(
                    phase = SessionPhase.Proving,
                    generation = gen,
                    candidateId = cand.nodeId,
                    candidateHost = cand.host,
                    detail = cand.label,
                ),
            )
            host.teardownGeneration(gen)
            if (!isAlive(gen)) return@firstSuccess false
            val socksOk = try {
                host.proveCandidateSocks(
                    username = cand.username,
                    protocol = cand.protocol,
                    params = cand.params,
                    alive = { isAlive(gen) },
                )
            } catch (e: Exception) {
                Log.w(TAG, "auto prove ${cand.nodeId} threw: ${e.message}")
                false
            }
            if (!socksOk) {
                Log.i(TAG, "auto prove fail node=${cand.nodeId}")
                DiagnosticRing.event(
                    "debug",
                    "vpn.prove",
                    "id=${cand.nodeId} ok=false",
                )
                host.teardownGeneration(gen)
                return@firstSuccess false
            }
            Log.i(TAG, "auto prove ok node=${cand.nodeId} — establishing TUN")
            DiagnosticRing.event(
                "info",
                "vpn.prove",
                "id=${cand.nodeId} ok=true",
            )
            val up = try {
                host.establishGeneration(
                    generation = gen,
                    username = cand.username,
                    protocol = cand.protocol,
                    params = cand.params,
                    alive = { isAlive(gen) },
                    emit = { snap ->
                        if (isAlive(gen)) publish(snap.copy(generation = gen))
                    },
                )
            } catch (e: Exception) {
                Log.e(TAG, "auto establish ${cand.nodeId} failed", e)
                false
            }
            if (!up) {
                host.teardownGeneration(gen)
            }
            up
        }
        if (!isAlive(gen)) return
        if (winner == null) {
            host.markPersistedInactive()
            val iface = DefaultNetworkMonitor.currentInterfaceName
            publish(
                SessionSnapshot(
                    phase = SessionPhase.Error,
                    generation = gen,
                    reason = SessionReason.PathIncompatible,
                    detail = "path_incompatible: auto: no candidate passed data-plane prove",
                    underlyingIface = iface,
                    transport = PathTransport.fromIface(iface),
                ),
            )
        } else {
            host.persistAutoWinner(winner)
            publishConnectedHealthy(
                gen = gen,
                candidateId = winner.nodeId,
                candidateHost = winner.host,
                detail = winner.label,
            )
        }
    }

    private fun publishConnectedHealthy(
        gen: Long,
        candidateId: String?,
        candidateHost: String?,
        detail: String?,
    ) {
        if (!isAlive(gen)) return
        if (snapshot.phase == SessionPhase.ConnectedHealthy ||
            snapshot.phase == SessionPhase.ConnectedDegraded
        ) {
            return
        }
        val iface = DefaultNetworkMonitor.currentInterfaceName
        publish(
            SessionSnapshot(
                phase = SessionPhase.ConnectedHealthy,
                generation = gen,
                reason = SessionReason.EgressOk,
                candidateId = candidateId,
                candidateHost = candidateHost,
                underlyingIface = iface,
                transport = PathTransport.fromIface(iface),
                detail = detail,
            ),
        )
    }

    private fun nodeIdFromParams(params: Map<String, Any?>): String? {
        for (key in listOf("autoNodeId", "hysteriaNodeId")) {
            val value = (params[key] as? String)?.trim().orEmpty()
            if (value.isNotEmpty()) return value
        }
        return null
    }

    private fun hostFromParams(params: Map<String, Any?>): String? {
        for (key in listOf("hysteriaServer")) {
            val value = (params[key] as? String)?.trim().orEmpty()
            if (value.isNotEmpty()) return value
        }
        return null
    }

    private fun runStop(gen: Long) {
        if (snapshot.phase == SessionPhase.Stopping ||
            snapshot.phase == SessionPhase.Idle
        ) {
            Log.i(TAG, "runStop skipped already phase=${snapshot.phase} gen=$gen")
            if (isAlive(gen) && snapshot.phase != SessionPhase.Idle) {
                publish(SessionSnapshot.idle(gen))
            }
            return
        }
        publish(
            SessionSnapshot(
                phase = SessionPhase.Stopping,
                generation = gen,
            ),
        )
        host.teardownGeneration(gen)
        if (isAlive(gen)) {
            publish(SessionSnapshot.idle(gen))
        }
    }

    private fun publish(next: SessionSnapshot) {
        snapshot = next
        Log.i(
            TAG,
            "snapshot phase=${next.phase} gen=${next.generation} " +
                "reason=${next.reason} transport=${next.transport.toWire()} " +
                "iface=${next.underlyingIface}",
        )
        DiagnosticRing.event(
            tunnelPhaseLevel(next.phase, next.reason),
            "vpn.phase",
            "phase=${next.phase} gen=${next.generation} " +
                "reason=${next.reason} candidate=${next.candidateId.orEmpty()} " +
                "iface=${next.underlyingIface.orEmpty()}",
        )
        host.onSnapshot(next)
    }

    companion object {
        private const val TAG = "VpnSessionEngine"

        /**
         * Keep failStart text (SOCKS probe, protect). A blank prior is the
         * only case that becomes the generic establish failure.
         */
        fun establishFailureDetail(prior: String?): String {
            val trimmed = prior?.trim().orEmpty()
            return if (trimmed.isEmpty()) "establish returned false" else trimmed
        }

        /** Shared generation clock (MethodChannel allocate + Engine enqueue). */
        private val generationClock = AtomicLong(0L)

        /** Pre-allocate generation before VpnService onStartCommand. */
        fun allocateGeneration(): Long = generationClock.incrementAndGet().also { allocated ->
            Log.i(TAG, "allocateGeneration=$allocated")
        }

        fun peekGeneration(): Long = generationClock.get()
    }
}

/** One minted Auto hop (Flutter already called /vpn/config). */
data class AutoCandidate(
    val nodeId: String,
    val host: String,
    val label: String,
    val username: String,
    val protocol: String,
    val params: Map<String, Any?>,
    val paramsJson: String = "",
)
