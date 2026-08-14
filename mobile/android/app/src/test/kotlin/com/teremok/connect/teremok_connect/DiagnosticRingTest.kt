package com.teremok.connect.teremok_connect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticRingTest {
    @Test
    fun `redact strips auth and bearer`() {
        val raw = "hysteriaAuth=super-secret-token Bearer abc.def TAG=ok"
        val out = DiagnosticRing.redact(raw)
        assertFalse(out.contains("super-secret-token"))
        assertFalse(out.contains("abc.def"))
        assertTrue(out.contains("hysteriaAuth=***"))
        assertTrue(out.contains("Bearer ***"))
        assertTrue(out.contains("TAG=ok"))
    }

    @Test
    fun `tail returns last N lines`() {
        DiagnosticRing.clear()
        repeat(5) { DiagnosticRing.append("TeremokVpn", "line $it") }
        val tail = DiagnosticRing.tail(2)
        assertTrue(tail.contains("line 3"))
        assertTrue(tail.contains("line 4"))
        assertFalse(tail.contains("line 0"))
        DiagnosticRing.clear()
        assertEquals("", DiagnosticRing.tail())
    }
}
