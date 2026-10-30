package com.proxydom.app

import com.proxydom.app.session.PathTransport
import com.proxydom.app.session.SessionPhase
import com.proxydom.app.session.SessionReason
import com.proxydom.app.session.SessionSnapshot
import com.proxydom.app.session.VpnSessionEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit smoke for snapshot model (avoid org.json — not mocked on JVM).
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
    fun `path incompatible snapshot carries wifi path fields`() {
        val snap = SessionSnapshot(
            phase = SessionPhase.Error,
            generation = 4L,
            reason = SessionReason.PathIncompatible,
            underlyingIface = "wlan0",
            transport = PathTransport.Wifi,
            detail = "path_incompatible: auto: no candidate passed data-plane prove",
        )
        assertEquals("wlan0", snap.underlyingIface)
        assertEquals(PathTransport.Wifi, snap.transport)
        assertEquals(SessionReason.PathIncompatible, snap.reason)
        assertEquals("error", snap.phase.toLegacyStatus())
    }

    @Test
    fun `session reason fromWire is case insensitive`() {
        assertEquals(SessionReason.EgressTimeout, SessionReason.fromWire("EgressTimeout"))
        assertEquals(SessionReason.EgressTimeout, SessionReason.fromWire("egresstimeout"))
        assertEquals(SessionReason.NodeHandshake, SessionReason.fromWire("NodeHandshake"))
        assertEquals(SessionReason.NodeHandshake, SessionReason.fromWire("nodehandshake"))
        assertEquals(SessionReason.None, SessionReason.fromWire(null))
        assertEquals(SessionReason.Unknown, SessionReason.fromWire("not-a-reason"))
        assertTrue(SessionReason.fromWire("UnderlyingBad") == SessionReason.UnderlyingBad)
    }

    /**
     * The node's own dial failing and the exit not answering are different
     * faults. Both used to publish EgressTimeout, which is why a dead TLS/WS
     * front was diagnosed as a slow exit.
     */
    @Test
    fun `a node handshake failure is not an egress timeout`() {
        assertEquals(
            SessionReason.NodeHandshake,
            VpnSessionEngine.establishFailureReason(
                "node handshake failed server=203.0.113.10:443 proto=tls/ws " +
                    "tcp=ok reason=1.1.1.1:443=SocketTimeoutException=Read timed out",
            ),
        )
        assertEquals(
            SessionReason.EgressTimeout,
            VpnSessionEngine.establishFailureReason(
                "tunnel carried no response server=203.0.113.10:443 reason=...",
            ),
        )
        assertEquals(
            SessionReason.EgressTimeout,
            VpnSessionEngine.establishFailureReason(null),
        )
    }

    @Test
    fun `establish failure keeps socks probe detail`() {
        val probe = "eu-hy2-1@217.60.3.9:443: SOCKS HTTPS probe failed"
        assertEquals(probe, VpnSessionEngine.establishFailureDetail(probe))
        assertEquals(
            "establish returned false",
            VpnSessionEngine.establishFailureDetail(null),
        )
        assertEquals(
            "establish returned false",
            VpnSessionEngine.establishFailureDetail("  "),
        )
    }
}
