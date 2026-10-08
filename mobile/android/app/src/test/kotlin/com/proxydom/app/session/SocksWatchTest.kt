package com.proxydom.app.session

import com.proxydom.app.GvisorTun2Socks
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class SocksWatchTest {
    @Test
    fun `vless share watches 10809`() {
        val watch = socksWatchFor(mapOf("vpnCore" to "vless"))
        assertNotNull(watch)
        assertEquals(PathHealth.CoreAdapter.ShareSocks, watch!!.adapter)
        assertEquals(GvisorTun2Socks.SHARE_SOCKS_PORT, watch.port)
        assertEquals(10809, watch.port)
    }

    @Test
    fun `vless does not fall back to the hy2 port`() {
        val watch = socksWatchFor(
            mapOf(
                "vpnCore" to "vless",
                "hysteriaSocksListen" to "127.0.0.1:10808",
            ),
        )
        assertNotNull(watch)
        assertEquals(10809, watch!!.port)
    }

    @Test
    fun `hysteria watches 10808`() {
        val watch = socksWatchFor(mapOf("vpnCore" to "hysteria"))
        assertNotNull(watch)
        assertEquals(PathHealth.CoreAdapter.HysteriaSocks, watch!!.adapter)
        assertEquals(GvisorTun2Socks.SOCKS_PORT, watch.port)
        assertEquals(10808, watch.port)
    }

    @Test
    fun `blank hysteria listen stays on 10808`() {
        val watch = socksWatchFor(
            mapOf(
                "vpnCore" to "hysteria",
                "hysteriaSocksListen" to "  ",
            ),
        )
        assertEquals(10808, watch!!.port)
    }

    @Test
    fun `explicit hysteria listen port is used`() {
        val watch = socksWatchFor(
            mapOf(
                "vpnCore" to "hysteria",
                "hysteriaSocksListen" to "127.0.0.1:10808",
            ),
        )
        assertEquals(10808, watch!!.port)
    }

    @Test
    fun `unknown core is not a silent hy2 port`() {
        assertNull(socksWatchFor(emptyMap()))
        assertNull(socksWatchFor(mapOf("vpnCore" to "trusttunnel")))
    }

    @Test
    fun `unparseable hysteria listen is an error`() {
        assertNull(
            socksWatchFor(
                mapOf(
                    "vpnCore" to "hysteria",
                    "hysteriaSocksListen" to "not-a-port",
                ),
            ),
        )
    }
}
