package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Test

/** SOCKS listen used by Hy2 PathHealth probes. */
class GvisorTun2SocksConfigTest {
    @Test
    fun socksProbeEndpointMatchesHy2() {
        assertEquals("127.0.0.1", GvisorTun2Socks.SOCKS_HOST)
        assertEquals(10808, GvisorTun2Socks.SOCKS_PORT)
    }
}
