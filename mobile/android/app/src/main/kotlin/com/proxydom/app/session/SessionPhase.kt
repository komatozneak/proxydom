package com.proxydom.app.session

/**
 * Session phases for [VpnSessionEngine].
 * Legacy string status maps via [toLegacyStatus].
 */
enum class SessionPhase {
    Idle,
    Binding,
    TunUp,
    CoreStarting,
    Proving,
    ConnectedHealthy,
    ConnectedDegraded,
    Stopping,
    Error,
    ;

    fun toLegacyStatus(): String = when (this) {
        Idle -> "idle"
        Binding, TunUp, CoreStarting -> "connecting"
        Proving -> "probing"
        ConnectedHealthy, ConnectedDegraded -> "connected"
        Stopping -> "disconnecting"
        Error -> "error"
    }

    /** Auto hop teardown must not broadcast idle — Nest would paint rest while TUN is coming up. */
    fun suppressTeardownIdleBroadcast(): Boolean = when (this) {
        Binding, TunUp, CoreStarting, Proving -> true
        else -> false
    }
}

/** Classified path / session outcomes (not wall-clock kludges). */
enum class SessionReason {
    None,
    UnderlyingBad,
    DialFail,
    EgressTimeout,
    EgressOk,
    Degraded,
    Dead,
    Cancelled,
    Revoked,
    ProtectFail,
    InvalidParams,
    /** Bound path cannot complete prove for this plan (after replan). */
    PathIncompatible,
    /** The node's own TLS/WebSocket (or QUIC) dial never completed. */
    NodeHandshake,
    Unknown,
    ;

    companion object {
        fun fromWire(raw: String?): SessionReason {
            if (raw.isNullOrBlank()) return None
            return entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: Unknown
        }
    }
}

/** Log level for a published session snapshot. Intermediate phases stay debug. */
fun tunnelPhaseLevel(phase: SessionPhase, reason: SessionReason): String = when (phase) {
    SessionPhase.ConnectedHealthy -> "debug"
    SessionPhase.ConnectedDegraded -> "warn"
    SessionPhase.Error -> when (reason) {
        SessionReason.Cancelled -> "debug"
        SessionReason.PathIncompatible -> "warn"
        else -> "error"
    }
    else -> "debug"
}
