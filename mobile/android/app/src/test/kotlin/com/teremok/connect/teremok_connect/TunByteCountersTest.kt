package com.teremok.connect.teremok_connect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TunByteCountersTest {

    @Test
    fun `zero or backwards samples stay at 0 Bps`() {
        assertEquals(0L, TunByteCounters.bytesPerSecond(0, 1_000))
        assertEquals(0L, TunByteCounters.bytesPerSecond(500, 0))
        assertEquals(0L, TunByteCounters.bytesPerSecond(-10, 1_000))
    }

    @Test
    fun `one KiB in one second is 1024 Bps`() {
        assertEquals(1_024L, TunByteCounters.bytesPerSecond(1_024, 1_000))
    }

    @Test
    fun `formatSpeed matches monitor helper`() {
        assertEquals("0 B/s", VpnTrafficMonitor.formatSpeed(0))
        assertEquals("512 B/s", VpnTrafficMonitor.formatSpeed(512))
        assertEquals("1.00 KiB/s", VpnTrafficMonitor.formatSpeed(1_024L))
    }

    @Test
    fun `parseProcNetDev reads tun0 rx and tx bytes`() {
        val fixture =
            """
            Inter-|   Receive                                                |  Transmit
             face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
                lo: 100 1 0 0 0 0 0 0 100 1 0 0 0 0 0 0
              tun0: 2048 10 0 0 0 0 0 0 1024 5 0 0 0 0 0 0
            """.trimIndent()
        val sample = TunByteCounters.parseProcNetDev(fixture)!!
        assertEquals(2048L, sample.rxBytes)
        assertEquals(1024L, sample.txBytes)
    }

    @Test
    fun `parseProcNetDev ignores non-tun and empty`() {
        assertNull(TunByteCounters.parseProcNetDev(""))
        assertNull(
            TunByteCounters.parseProcNetDev(
                "lo: 1 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0",
            ),
        )
        assertNull(TunByteCounters.parseProcNetDev("tun0: not-numbers"))
    }
}
