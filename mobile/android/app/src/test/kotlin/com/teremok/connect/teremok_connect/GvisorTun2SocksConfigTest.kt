package com.teremok.connect.teremok_connect

import org.junit.Assert.assertEquals
import org.junit.Test

/** Constants for the gVisor-in-libXray path (SOCKS remains probe-only). */
class GvisorTun2SocksConfigTest {
    @Test
    fun socksProbeEndpointMatchesXrayInbound() {
        assertEquals("127.0.0.1", GvisorTun2Socks.SOCKS_HOST)
        assertEquals(10808, GvisorTun2Socks.SOCKS_PORT)
    }
}
