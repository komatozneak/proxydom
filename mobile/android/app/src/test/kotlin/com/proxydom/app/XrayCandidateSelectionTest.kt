package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayCandidateSelectionTest {
    private fun candidate(id: String) =
        SocksProbeCandidate(id, "$id.example", id, "{}")

    @Test
    fun `nest probes only the primary candidate`() {
        val candidates = listOf("a", "b", "c", "d").map(::candidate)

        assertEquals(
            listOf("a"),
            candidateProbeOrder(candidates, autoSelect = true).map { it.id },
        )
        assertEquals(
            listOf("a"),
            candidateProbeOrder(candidates, autoSelect = false).map { it.id },
        )
        assertEquals(1, AUTO_CANDIDATE_LIMIT)
    }

    @Test
    fun `fastestCandidate still picks min latency`() {
        val a = candidate("a")
        val b = candidate("b")
        val c = candidate("c")

        assertEquals(
            b,
            fastestCandidate(listOf(a to 420L, b to 180L, c to 260L))?.first,
        )
        assertEquals(1_000, XRAY_SOCKS_PROBE_TIMEOUT_MS)
        assertEquals(2, XRAY_SOCKS_PROBE_ATTEMPTS)
        assertEquals(150L, XRAY_SOCKS_PROBE_RETRY_SLEEP_MS)
        assertEquals(300L, XRAY_SOCKS_WARMUP_BUDGET_MS)
        assertTrue(socksHttpsProbeBudgetMs() <= 6_500L)
    }

    @Test
    fun `share server comes from the explicit fields`() {
        // A REALITY document has no address/port pair; the fields are the only
        // place its node is named.
        val params = mapOf(
            "vpnCore" to "vless",
            "vlessConfig" to """{"engine":"reality","server":"203.0.113.9","port":8443}""",
            "shareServerHost" to "203.0.113.9",
            "shareServerPort" to 8443,
        )
        assertEquals("203.0.113.9" to 8443, shareServerOf(params))
    }

    @Test
    fun `a session persisted by an older build still names its node`() {
        val params = mapOf(
            "vpnCore" to "vless",
            "vlessConfig" to
                """{"outbounds":[{"settings":{"vnext":[{"address":"node.example","port":443}]}}]}""",
        )
        assertEquals("node.example" to 443, shareServerOf(params))
    }

    @Test
    fun `no node at all is empty, not a crash`() {
        assertEquals("" to 0, shareServerOf(mapOf("vpnCore" to "vless")))
        assertEquals(
            "" to 0,
            shareServerOf(mapOf("shareServerHost" to "x.example", "shareServerPort" to 0)),
        )
    }
}
