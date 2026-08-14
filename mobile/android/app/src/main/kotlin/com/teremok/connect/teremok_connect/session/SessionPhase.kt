package com.teremok.connect.teremok_connect.session

/**
 * Session phases for [VpnSessionEngine] (ADR 014).
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
    Unknown,
    ;

    companion object {
        fun fromWire(raw: String?): SessionReason {
            if (raw.isNullOrBlank()) return None
            return entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: Unknown
        }
    }
}
