package com.teremok.connect.teremok_connect

import com.teremok.connect.teremok_connect.session.PathTransport
import com.teremok.connect.teremok_connect.session.SessionPhase
import com.teremok.connect.teremok_connect.session.SessionReason
import com.teremok.connect.teremok_connect.session.SessionSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit smoke for ADR 014 snapshot model (avoid org.json — not mocked on JVM).
 */
class SessionSnapshotTest {
    @Test
    fun `idle snapshot defaults`() {
        val snap = SessionSnapshot.idle(7L)
        assertEquals(SessionPhase.Idle, snap.phase)
        assertEquals(7L, snap.generation)
        assertEquals(SessionReason.None, snap.reason)
        assertNull(snap.underlyingIface)
        assertEquals("idle", snap.phase.toLegacyStatus())
    }

    @Test
    fun `healthy snapshot carries path fields`() {
        val snap = SessionSnapshot(
            phase = SessionPhase.ConnectedHealthy,
            generation = 3L,
            reason = SessionReason.EgressOk,
            candidateId = "eu-primary",
            candidateHost = "204.11.2.216",
            underlyingIface = "wlan0",
            rttMs = 420L,
        )
        assertEquals("connected", snap.phase.toLegacyStatus())
        assertEquals("eu-primary", snap.candidateId)
        assertEquals("wlan0", snap.underlyingIface)
        assertEquals(420L, snap.rttMs)
    }

    @Test
    fun `phase toLegacyStatus mapping`() {
        assertEquals("probing", SessionPhase.Proving.toLegacyStatus())
        assertEquals("connecting", SessionPhase.CoreStarting.toLegacyStatus())
        assertEquals("connecting", SessionPhase.Binding.toLegacyStatus())
        assertEquals("error", SessionPhase.Error.toLegacyStatus())
        assertEquals("disconnecting", SessionPhase.Stopping.toLegacyStatus())
        assertEquals("connected", SessionPhase.ConnectedDegraded.toLegacyStatus())
    }

    @Test
    fun `auto hop phases suppress idle broadcast`() {
        assertTrue(SessionPhase.Binding.suppressTeardownIdleBroadcast())
        assertTrue(SessionPhase.Proving.suppressTeardownIdleBroadcast())
        assertTrue(SessionPhase.TunUp.suppressTeardownIdleBroadcast())
        assertTrue(SessionPhase.CoreStarting.suppressTeardownIdleBroadcast())
        assertEquals(false, SessionPhase.ConnectedHealthy.suppressTeardownIdleBroadcast())
        assertEquals(false, SessionPhase.Idle.suppressTeardownIdleBroadcast())
        assertEquals(false, SessionPhase.Error.suppressTeardownIdleBroadcast())
    }

    @Test
    fun `path transport from iface`() {
        assertEquals(PathTransport.Wifi, PathTransport.fromIface("wlan0"))
        assertEquals(PathTransport.Cellular, PathTransport.fromIface("rmnet1"))
        assertEquals(PathTransport.Unknown, PathTransport.fromIface(null))
        assertEquals(PathTransport.Cellular, PathTransport.fromIface("ccmni0"))
    }

    @Test
    fun `session reason fromWire is case insensitive`() {
        assertEquals(SessionReason.EgressTimeout, SessionReason.fromWire("EgressTimeout"))
        assertEquals(SessionReason.EgressTimeout, SessionReason.fromWire("egresstimeout"))
        assertEquals(SessionReason.None, SessionReason.fromWire(null))
        assertEquals(SessionReason.Unknown, SessionReason.fromWire("not-a-reason"))
        assertTrue(SessionReason.fromWire("UnderlyingBad") == SessionReason.UnderlyingBad)
    }
}
