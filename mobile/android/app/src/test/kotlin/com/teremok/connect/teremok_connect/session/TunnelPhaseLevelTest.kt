package com.teremok.connect.teremok_connect.session

import org.junit.Assert.assertEquals
import org.junit.Test

class TunnelPhaseLevelTest {
    @Test
    fun `healthy is info and a terminal egress failure is error`() {
        assertEquals("debug", tunnelPhaseLevel(SessionPhase.Binding, SessionReason.None))
        assertEquals("debug", tunnelPhaseLevel(SessionPhase.ConnectedHealthy, SessionReason.EgressOk))
        assertEquals("warn", tunnelPhaseLevel(SessionPhase.ConnectedDegraded, SessionReason.Degraded))
        assertEquals(
            "error",
            tunnelPhaseLevel(SessionPhase.Error, SessionReason.EgressTimeout),
        )
        assertEquals("error", tunnelPhaseLevel(SessionPhase.Error, SessionReason.Revoked))
        assertEquals("debug", tunnelPhaseLevel(SessionPhase.Error, SessionReason.Cancelled))
        assertEquals("warn", tunnelPhaseLevel(SessionPhase.Error, SessionReason.PathIncompatible))
    }
}
