package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HysteriaCoreSelectionTest {
    @Test
    fun `vpnCore hysteria selects Hy2`() {
        assertTrue(isHysteriaCore(mapOf("vpnCore" to "hysteria")))
        assertFalse(isHysteriaCore(emptyMap()))
        assertFalse(isHysteriaCore(mapOf("vpnCore" to "vless")))
        assertFalse(isHysteriaCore(mapOf("vpnCore" to "trusttunnel")))
        assertEquals("hysteria", ProxyDomVpnService.VPN_CORE_HYSTERIA)
    }
}
