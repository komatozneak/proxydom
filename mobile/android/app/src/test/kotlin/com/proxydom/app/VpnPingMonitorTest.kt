package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

class VpnPingMonitorTest {
    @Test
    fun `clampDelayMs accepts plausible range`() {
        // 5 ms is the floor: an HTTP round trip through the tunnel cannot be
        // faked locally, so only impossible values are rejected.
        assertEquals(5, VpnPingMonitor.clampDelayMs(5))
        assertEquals(245, VpnPingMonitor.clampDelayMs(245))
        assertEquals(5000, VpnPingMonitor.clampDelayMs(5000))
    }

    @Test
    fun `clampDelayMs rejects impossible samples`() {
        assertNull(VpnPingMonitor.clampDelayMs(0))
        assertNull(VpnPingMonitor.clampDelayMs(4))
        assertNull(VpnPingMonitor.clampDelayMs(5001))
        assertNull(VpnPingMonitor.clampDelayMs(12_000))
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
    fun `TunnelHttpProbe to dead socks has no sample`() {
        TunnelHttpProbe(socksPort = 1).use { probe ->
            assertNull(probe.sample(timeoutMs = 200))
        }
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

    /**
     * A node whose TLS/WebSocket dial never finishes keeps the SOCKS CONNECT
     * open. The gate must call that a node handshake failure after one probe,
     * not spend three target timeouts and report an exit timeout: v2ray's own
     * websocket dial budget is 8 s, and the old 1 s gate killed it first.
     */
    @Test
    fun `proveTunnel stops when the node CONNECT never completes`() {
        val server = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        val accepted = AtomicInteger(0)
        thread(isDaemon = true) {
            while (true) {
                val socket = try {
                    server.accept()
                } catch (_: Exception) {
                    return@thread
                }
                accepted.incrementAndGet()
                // Hold the socket: the SOCKS greeting gets no reply.
                socket.use { Thread.sleep(2_000) }
            }
        }
        val startedAt = System.nanoTime()
        val result = VpnPingMonitor.proveTunnel(
            socksHost = "127.0.0.1",
            socksPort = server.localPort,
            timeoutMs = 250,
        )
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000
        server.close()

        assertFalse(result.carriesData)
        assertTrue(result.nodeHandshakeFailed)
        assertTrue(result.detail.contains("1.1.1.1:443"))
        // The other targets would each open another WebSocket dial.
        assertFalse(result.detail.contains("cp.cloudflare.com"))
        assertTrue("elapsed=${elapsedMs}ms", elapsedMs < 1_500)
        assertTrue("accepted=${accepted.get()}", accepted.get() == 1)
    }
}
