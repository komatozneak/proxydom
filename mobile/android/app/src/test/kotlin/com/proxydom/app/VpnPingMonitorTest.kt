package com.teremok.connect.teremok_connect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnPingMonitorTest {
    @Test
    fun `clampDelayMs accepts plausible range`() {
        assertEquals(30, VpnPingMonitor.clampDelayMs(30))
        assertEquals(245, VpnPingMonitor.clampDelayMs(245))
        assertEquals(5000, VpnPingMonitor.clampDelayMs(5000))
    }

    @Test
    fun `clampDelayMs rejects too fast and too slow`() {
        assertNull(VpnPingMonitor.clampDelayMs(5))
        assertNull(VpnPingMonitor.clampDelayMs(29))
        assertNull(VpnPingMonitor.clampDelayMs(5001))
        assertNull(VpnPingMonitor.clampDelayMs(12_000))
    }

    @Test
    fun `fail clear threshold is two consecutive failures`() {
        assertEquals(2, VpnPingMonitor.FAIL_CLEAR_THRESHOLD)
    }

    @Test
    fun `parseHttpStatusCode reads 204 and 200`() {
        assertEquals(204, VpnPingMonitor.parseHttpStatusCode("HTTP/1.1 204 No Content"))
        assertEquals(200, VpnPingMonitor.parseHttpStatusCode("HTTP/1.0 200 OK"))
        assertEquals(503, VpnPingMonitor.parseHttpStatusCode("HTTP/1.1 503"))
    }

    @Test
    fun `parseHttpStatusCode rejects garbage`() {
        assertNull(VpnPingMonitor.parseHttpStatusCode(""))
        assertNull(VpnPingMonitor.parseHttpStatusCode("OK 200"))
        assertNull(VpnPingMonitor.parseHttpStatusCode("HTTP/1.1"))
    }

    @Test
    fun `tcpConnectRttMs to closed local port returns null`() {
        assertNull(
            VpnPingMonitor.tcpConnectRttMs(
                host = "127.0.0.1",
                port = 1,
                timeoutMs = 200,
            ),
        )
    }

    @Test
    fun `socks5ConnectRttMs to dead socks returns null`() {
        assertNull(
            VpnPingMonitor.socks5ConnectRttMs(
                socksHost = "127.0.0.1",
                socksPort = 1,
                timeoutMs = 200,
            ),
        )
    }

    @Test
    fun `socksConnectOk to dead socks returns false`() {
        assertFalse(
            VpnPingMonitor.socksConnectOk(
                socksHost = "127.0.0.1",
                socksPort = 1,
                timeoutMs = 200,
            ),
        )
    }

    @Test
    fun `socksConnectProbe to dead socks returns Fail with reason`() {
        val result = VpnPingMonitor.socksConnectProbe(
            socksHost = "127.0.0.1",
            socksPort = 1,
            timeoutMs = 200,
        )
        assertTrue(result is VpnPingMonitor.SocksHttpsResult.Fail)
        assertFalse(result.isOk)
        assertTrue(result.detail.isNotBlank())
    }

    @Test
    fun `socksHttpOk to dead socks returns false`() {
        assertFalse(
            VpnPingMonitor.socksHttpOk(
                socksHost = "127.0.0.1",
                socksPort = 1,
                timeoutMs = 200,
            ),
        )
    }

    @Test
    fun `socksHttpProbe to dead socks returns Fail with reason`() {
        val result = VpnPingMonitor.socksHttpProbe(
            socksHost = "127.0.0.1",
            socksPort = 1,
            timeoutMs = 200,
        )
        assertTrue(result is VpnPingMonitor.SocksHttpsResult.Fail)
        assertFalse(result.isOk)
        assertTrue(result.detail.isNotBlank())
    }

    @Test
    fun `socksHttpsOk to dead socks returns false`() {
        assertFalse(
            VpnPingMonitor.socksHttpsOk(
                socksHost = "127.0.0.1",
                socksPort = 1,
                timeoutMs = 200,
            ),
        )
    }

    @Test
    fun `socksHttpsProbe to dead socks returns Fail with reason`() {
        val result = VpnPingMonitor.socksHttpsProbe(
            socksHost = "127.0.0.1",
            socksPort = 1,
            timeoutMs = 200,
        )
        assertTrue(result is VpnPingMonitor.SocksHttpsResult.Fail)
        assertFalse(result.isOk)
        assertTrue(result.detail.isNotBlank())
    }
}
