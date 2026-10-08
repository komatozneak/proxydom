package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelAcceptanceTest {
    @Test
    fun `connect without a response is not acceptance`() {
        // #313 treated a finished SOCKS CONNECT as proof the tunnel carries
        // data. Hy2 FastOpen returns that CONNECT before the server confirms
        // the destination, so a dead exit looks alive. A response is required.
        val accepted = acceptTunnel(
            listOf(
                HttpProbeSample(
                    target = "1.1.1.1:443",
                    tcp = true,
                    httpStatus = null,
                    exitIp = null,
                    detail = "reset",
                ),
            ),
        )
        assertFalse(accepted.carriesData)
        assertNull(accepted.exitIp)
        assertNull(accepted.target)
        assertTrue(accepted.detail.contains("1.1.1.1:443"))
    }

    @Test
    fun `any parsed http status is a response`() {
        val accepted = acceptTunnel(
            listOf(
                HttpProbeSample(
                    target = "cp.cloudflare.com:443",
                    tcp = true,
                    httpStatus = 403,
                    exitIp = null,
                    detail = "http=403",
                ),
            ),
        )
        assertTrue(accepted.carriesData)
        assertEquals("cp.cloudflare.com:443", accepted.target)
        assertNull(accepted.exitIp)
    }

    @Test
    fun `an exit address alone is a response`() {
        val accepted = acceptTunnel(
            listOf(
                HttpProbeSample(
                    target = "1.1.1.1:443",
                    tcp = true,
                    httpStatus = null,
                    exitIp = "203.0.113.8",
                    detail = "http=none",
                ),
            ),
        )
        assertTrue(accepted.carriesData)
        assertEquals("203.0.113.8", accepted.exitIp)
        assertEquals("1.1.1.1:443", accepted.target)
    }

    @Test
    fun `a later sample with a response wins over an earlier connect`() {
        val accepted = acceptTunnel(
            listOf(
                HttpProbeSample(
                    target = "1.1.1.1:443",
                    tcp = true,
                    httpStatus = null,
                    exitIp = null,
                    detail = "handshake",
                ),
                HttpProbeSample(
                    target = "cp.cloudflare.com:443",
                    tcp = true,
                    httpStatus = 204,
                    exitIp = null,
                    detail = "http=204",
                ),
            ),
        )
        assertTrue(accepted.carriesData)
        assertEquals("cp.cloudflare.com:443", accepted.target)
    }

    @Test
    fun `no response from any target is a refusal that names them`() {
        val accepted = acceptTunnel(
            listOf(
                HttpProbeSample(
                    target = "1.1.1.1:443",
                    tcp = true,
                    httpStatus = null,
                    exitIp = null,
                    detail = "handshake",
                ),
                HttpProbeSample(
                    target = "cp.cloudflare.com:443",
                    tcp = false,
                    httpStatus = null,
                    exitIp = null,
                    detail = "reset",
                ),
            ),
        )
        assertFalse(accepted.carriesData)
        assertNull(accepted.exitIp)
        assertTrue(accepted.detail.contains("1.1.1.1:443"))
        assertTrue(accepted.detail.contains("cp.cloudflare.com:443"))
    }

    @Test
    fun `a later target is not required after the first connect`() {
        val accepted = acceptTunnel(
            listOf(
                HttpProbeSample(
                    target = "1.1.1.1:443",
                    tcp = true,
                    httpStatus = 200,
                    exitIp = "194.48.250.199",
                    detail = "http=200",
                ),
                HttpProbeSample(
                    target = "cp.cloudflare.com:443",
                    tcp = false,
                    httpStatus = null,
                    exitIp = null,
                    detail = "unused",
                ),
            ),
        )
        assertTrue(accepted.carriesData)
        assertEquals("194.48.250.199", accepted.exitIp)
    }

    @Test
    fun `no connect is a refusal and not an unread ip`() {
        val accepted = acceptTunnel(
            listOf(
                HttpProbeSample(
                    target = "1.1.1.1:443",
                    tcp = false,
                    httpStatus = null,
                    exitIp = null,
                    detail = "reset",
                ),
            ),
        )
        assertFalse(accepted.carriesData)
        assertNull(accepted.exitIp)
        assertTrue(accepted.detail.contains("1.1.1.1:443=reset"))
    }

    @Test
    fun `matching the carrier is a warning and an unread ip is unread`() {
        assertEquals("egress ip unread", egressIpWarn(null, "1.2.3.4"))
        assertEquals("egress ip unread", egressIpWarn("  ", null))
        assertEquals(
            "egress ip matches carrier",
            egressIpWarn("194.48.250.199", "194.48.250.199"),
        )
        assertNull(egressIpWarn("194.48.250.199", "10.0.0.1"))
        assertNull(egressIpWarn("194.48.250.199", null))
    }
}
