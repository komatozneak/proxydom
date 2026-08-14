package com.teremok.connect.teremok_connect.session

import org.json.JSONObject

/**
 * Typed session snapshot for Flutter (ADR 014).
 * Also drives legacy string status via [phase].toLegacyStatus().
 */
data class SessionSnapshot(
    val phase: SessionPhase,
    val generation: Long,
    val reason: SessionReason = SessionReason.None,
    val candidateId: String? = null,
    val candidateHost: String? = null,
    val underlyingIface: String? = null,
    /** PathPlan transport: wifi | cellular | unknown. */
    val transport: PathTransport = PathTransport.Unknown,
    val rttMs: Long? = null,
    val detail: String? = null,
) {
    fun toJsonObject(): JSONObject = JSONObject().apply {
        put("phase", phase.name)
        put("legacyStatus", phase.toLegacyStatus())
        put("generation", generation)
        put("reason", reason.name)
        put("transport", transport.toWire())
        if (candidateId != null) put("candidateId", candidateId)
        if (candidateHost != null) put("candidateHost", candidateHost)
        if (underlyingIface != null) put("underlyingIface", underlyingIface)
        if (rttMs != null) put("rttMs", rttMs)
        if (detail != null) put("detail", detail)
    }

    fun toJsonString(): String = toJsonObject().toString()

    companion object {
        fun idle(generation: Long = 0L) = SessionSnapshot(
            phase = SessionPhase.Idle,
            generation = generation,
        )
    }
}
