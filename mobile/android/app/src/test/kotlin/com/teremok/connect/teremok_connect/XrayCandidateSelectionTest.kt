package com.teremok.connect.teremok_connect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayCandidateSelectionTest {
    private fun candidate(id: String) =
        XrayRuntimeCandidate(id, "$id.example", id, "{}")

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
}
