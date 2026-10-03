package com.proxydom.app

import com.proxydom.app.session.AutoCandidate
import com.proxydom.app.session.AutoProveLoop
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AutoProveLoopTest {
    private fun cand(id: String) = AutoCandidate(
        nodeId = id,
        host = "$id.example",
        label = id,
        username = "u",
        protocol = "vless",
        params = emptyMap(),
    )

    @Test
    fun `first Fail then Ok is the winner`() {
        val eu = cand("eu-primary")
        val hy2 = cand("eu-hy2-1")
        val seen = mutableListOf<String>()
        val winner = AutoProveLoop.firstSuccess(listOf(eu, hy2)) { item ->
            seen.add(item.nodeId)
            item.nodeId == "eu-hy2-1"
        }
        assertEquals("eu-hy2-1", winner?.nodeId)
        assertEquals(listOf("eu-primary", "eu-hy2-1"), seen)
    }

    @Test
    fun `all Fail returns null`() {
        val winner = AutoProveLoop.firstSuccess(listOf(cand("a"), cand("b"))) { false }
        assertNull(winner)
    }

    @Test
    fun `manual nest is not this loop — single stored id stays first`() {
        // Locations pick is one mint; AutoProveLoop is Auto-only.
        val only = cand("eu-primary")
        val winner = AutoProveLoop.firstSuccess(listOf(only)) { true }
        assertEquals("eu-primary", winner?.nodeId)
    }
}
