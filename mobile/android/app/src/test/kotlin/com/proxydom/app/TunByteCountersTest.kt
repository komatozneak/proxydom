package com.proxydom.app

import org.junit.Assert.assertEquals
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
}
