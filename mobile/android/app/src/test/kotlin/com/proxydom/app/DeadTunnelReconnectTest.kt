package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeadTunnelReconnectTest {

    @Test
    fun `first attempt is allowed while session is active`() {
        assertTrue(
            DeadTunnelReconnect.shouldAttempt(
                sessionActive = true,
                userStopping = false,
                recoverInFlight = false,
                attempts = 0,
                elapsedSinceLastMs = 0L,
            ),
        )
    }

    @Test
    fun `does not recover after user stop or inactive session`() {
        assertFalse(
            DeadTunnelReconnect.shouldAttempt(
                sessionActive = false,
                userStopping = false,
                recoverInFlight = false,
                attempts = 0,
                elapsedSinceLastMs = Long.MAX_VALUE,
            ),
        )
        assertFalse(
            DeadTunnelReconnect.shouldAttempt(
                sessionActive = true,
                userStopping = true,
                recoverInFlight = false,
                attempts = 0,
                elapsedSinceLastMs = Long.MAX_VALUE,
            ),
        )
    }

    @Test
    fun `skips while a recover is already in flight`() {
        assertFalse(
            DeadTunnelReconnect.shouldAttempt(
                sessionActive = true,
                userStopping = false,
                recoverInFlight = true,
                attempts = 1,
                elapsedSinceLastMs = Long.MAX_VALUE,
            ),
        )
    }

    @Test
    fun `honours backoff between attempts`() {
        assertFalse(
            DeadTunnelReconnect.shouldAttempt(
                sessionActive = true,
                userStopping = false,
                recoverInFlight = false,
                attempts = 1,
                elapsedSinceLastMs = 500L,
            ),
        )
        assertTrue(
            DeadTunnelReconnect.shouldAttempt(
                sessionActive = true,
                userStopping = false,
                recoverInFlight = false,
                attempts = 1,
                elapsedSinceLastMs = DeadTunnelReconnect.MIN_INTERVAL_MS,
            ),
        )
    }

    @Test
    fun `caps attempts and backoff`() {
        assertFalse(
            DeadTunnelReconnect.shouldAttempt(
                sessionActive = true,
                userStopping = false,
                recoverInFlight = false,
                attempts = DeadTunnelReconnect.MAX_ATTEMPTS,
                elapsedSinceLastMs = Long.MAX_VALUE,
            ),
        )
        assertEquals(2_000L, DeadTunnelReconnect.backoffMs(0))
        assertEquals(4_000L, DeadTunnelReconnect.backoffMs(1))
        assertEquals(60_000L, DeadTunnelReconnect.backoffMs(99))
    }
}
