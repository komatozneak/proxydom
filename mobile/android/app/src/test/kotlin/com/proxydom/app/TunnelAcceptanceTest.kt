package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelAcceptanceTest {
    @Test
    fun `tcp through socks is enough when the exit ip is missing`() {
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
        assertTrue(accepted.carriesData)
        assertNull(accepted.exitIp)
        assertEquals("1.1.1.1:443", accepted.target)
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
