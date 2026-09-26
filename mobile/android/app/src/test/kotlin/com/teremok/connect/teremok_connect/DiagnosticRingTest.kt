package com.teremok.connect.teremok_connect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticRingTest {
    @Test
    fun `redact strips auth bearer and node address`() {
        val raw = "hysteriaAuth=super-secret-token Bearer abc.def candidate=45.91.248.91 TAG=ok"
        val out = DiagnosticRing.redact(raw)
        assertFalse(out.contains("super-secret-token"))
        assertFalse(out.contains("abc.def"))
        assertFalse(out.contains("45.91.248.91"))
        assertTrue(out.contains("hysteriaAuth=***"))
        assertTrue(out.contains("Bearer ***"))
        assertTrue(out.contains("45.91.***.***"))
        assertTrue(out.contains("TAG=ok"))
    }

    @Test
    fun `event line matches the dart contract`() {
        DiagnosticRing.clear()
        DiagnosticRing.event(
            level = "info",
            event = "vpn.phase",
            fields = "phase=ConnectedHealthy candidate=45.91.248.91",
            nowMs = 1_758_000_000_000,
        )
        val line = DiagnosticRing.tail(1)
        assertTrue(line.contains("[info] [vpn] vpn.phase"))
        assertTrue(line.contains("phase=ConnectedHealthy"))
        assertTrue(line.contains("45.91.***.***"))
        assertFalse(line.contains("45.91.248.91"))
        assertTrue(line.startsWith("2025-"))
        DiagnosticRing.clear()
    }

    @Test
    fun `tail returns last N lines`() {
        DiagnosticRing.clear()
        repeat(5) {
            DiagnosticRing.event("debug", "vpn.phase", "line=$it", nowMs = it.toLong())
        }
        val tail = DiagnosticRing.tail(2)
        assertTrue(tail.contains("line=3"))
        assertTrue(tail.contains("line=4"))
        assertFalse(tail.contains("line=0"))
        DiagnosticRing.clear()
        assertEquals("", DiagnosticRing.tail())
    }
}
