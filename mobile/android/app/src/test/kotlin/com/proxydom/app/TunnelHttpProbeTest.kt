package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Home `ms` has to wait for the first byte the exit produced — and, once it has
 * a connection, it must not pay the tunnel's stream setup on every sample.
 *
 * A core acknowledges a SOCKS CONNECT as soon as the stream is open, not when
 * the exit has dialled the target: on a 130 ms node the ack came back in ~10 ms
 * and Home showed a ping three times better than the path. The fake below
 * mirrors that — instant ack, status line held back.
 */
class TunnelHttpProbeTest {
    @Test
    fun `the clock runs to the status line, not to the CONNECT ack`() {
        FakeSocksServer(statusLine = "HTTP/1.0 204 No Content", holdBackMs = 150)
            .use { server ->
                TunnelHttpProbe(socksPort = server.port).use { probe ->
                    val rtt = probe.sample(timeoutMs = 3_000)
                    assertNotNull(rtt)
                    assertTrue(
                        "rtt=$rtt must include the 150 ms hold-back",
                        rtt!! >= 120,
                    )
                }
            }
    }

    @Test
    fun `a throttled answer still proves the round trip`() {
        FakeSocksServer(statusLine = "HTTP/1.0 403 Forbidden", holdBackMs = 0)
            .use { server ->
                TunnelHttpProbe(socksPort = server.port).use { probe ->
                    assertNotNull(
                        "any status line is a measured path",
                        probe.sample(timeoutMs = 3_000),
                    )
                }
            }
    }

    @Test
    fun `a tunnel that never answers has no sample`() {
        FakeSocksServer(statusLine = null, holdBackMs = 0).use { server ->
            TunnelHttpProbe(socksPort = server.port).use { probe ->
                assertNull(probe.sample(timeoutMs = 500))
            }
        }
    }

    /**
     * The bug behind "ping takes long": every sample opened a new connection,
     * and a fresh tunnel stream costs its setup before the first byte. Reusing
     * the connection makes the sample one round trip.
     */
    @Test
    fun `a kept connection is not rebuilt for the next sample`() {
        FakeSocksServer(
            statusLine = "HTTP/1.1 204 No Content",
            holdBackMs = 0,
            keepAlive = true,
        ).use { server ->
            TunnelHttpProbe(socksPort = server.port).use { probe ->
                val first = probe.sample(timeoutMs = 3_000)
                val second = probe.sample(timeoutMs = 3_000)
                assertNotNull(first)
                assertNotNull(second)
                assertEquals(
                    "the probe must reuse its tunnel stream",
                    1,
                    server.connections.get(),
                )
            }
        }
    }
}
