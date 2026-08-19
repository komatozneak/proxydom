package com.teremok.connect.teremok_connect

/**
 * Native recovery when Hy2 QUIC dies while VpnService still shows connected.
 *
 * Settings → Auto-reconnect is Dart: it does not run while the screen is off
 * (Flutter paused) and it never fires while native status stays `connected`.
 * Screen-off Doze / Wi‑Fi sleep is that case — recover in [TeremokVpnService].
 */
object DeadTunnelReconnect {
    const val MAX_ATTEMPTS = 8
    const val MIN_INTERVAL_MS = 2_000L
    const val MAX_BACKOFF_MS = 60_000L

    fun backoffMs(attemptIndex: Int): Long {
        val shift = attemptIndex.coerceIn(0, 5)
        return (MIN_INTERVAL_MS * (1L shl shift)).coerceAtMost(MAX_BACKOFF_MS)
    }

    fun shouldAttempt(
        sessionActive: Boolean,
        userStopping: Boolean,
        recoverInFlight: Boolean,
        attempts: Int,
        elapsedSinceLastMs: Long,
    ): Boolean {
        if (!sessionActive || userStopping || recoverInFlight) return false
        if (attempts >= MAX_ATTEMPTS) return false
        if (attempts > 0 && elapsedSinceLastMs < backoffMs(attempts - 1)) return false
        return true
    }
}
