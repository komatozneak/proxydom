package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NetBindLogTest {
    @Test
    fun `a fail followed by success inside the window is one debug line`() {
        val emitted = mutableListOf<String>()
        val pending = mutableListOf<Runnable>()
        val log = NetBindLog(
            emit = { level, event, fields -> emitted.add("$level $event $fields") },
            postDelayed = { _, task -> pending.add(task) },
            cancel = { task -> pending.remove(task) },
        )
        log.record("rmnet1", ok = false)
        log.record("rmnet1", ok = true)
        assertEquals(listOf("debug net.bind iface=rmnet1 ok=true retries=1"), emitted)
        assertTrue(pending.isEmpty())
    }

    @Test
    fun `a fail that is not retried becomes an error`() {
        val emitted = mutableListOf<String>()
        var scheduled: Runnable? = null
        val log = NetBindLog(
            emit = { level, event, fields -> emitted.add("$level $event $fields") },
            postDelayed = { _, task -> scheduled = task },
            cancel = { scheduled = null },
        )
        log.record("rmnet1", ok = false)
        assertTrue(emitted.isEmpty())
        scheduled?.run()
        assertEquals(listOf("error net.bind iface=rmnet1 ok=false retries=1"), emitted)
    }

    @Test
    fun `a second success inside the window is dropped`() {
        val emitted = mutableListOf<String>()
        var clock = 5_000L
        val log = NetBindLog(
            emit = { level, event, fields -> emitted.add("$level $event $fields") },
            postDelayed = { _, _ -> },
            cancel = {},
            now = { clock },
        )
        log.record("rmnet1", ok = true)
        clock += 1
        log.record("rmnet1", ok = true)
        assertEquals(listOf("debug net.bind iface=rmnet1 ok=true retries=0"), emitted)
    }
}
