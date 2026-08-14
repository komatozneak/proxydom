package com.teremok.connect.teremok_connect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrustTunnelCoreSelectionTest {

    @Test
    fun `vpnCore trusttunnel selects the TT core`() {
        assertTrue(isTrustTunnelCore(mapOf("vpnCore" to "trusttunnel")))
    }

    @Test
    fun `missing or xray vpnCore stays on the Xray core`() {
        assertFalse(isTrustTunnelCore(emptyMap()))
        assertFalse(isTrustTunnelCore(mapOf("vpnCore" to "xray")))
        assertFalse(isTrustTunnelCore(mapOf("vpnCore" to null)))
        assertFalse(isTrustTunnelCore(mapOf("vpnCore" to "TrustTunnel")))
    }

    @Test
    fun `core constants are stable across the MethodChannel contract`() {
        assertEquals("xray", TeremokVpnService.VPN_CORE_XRAY)
        assertEquals("trusttunnel", TeremokVpnService.VPN_CORE_TRUSTTUNNEL)
        assertEquals("hysteria", TeremokVpnService.VPN_CORE_HYSTERIA)
    }

    @Test
    fun `vpnCore hysteria selects the Hy2 core`() {
        assertTrue(isHysteriaCore(mapOf("vpnCore" to "hysteria")))
        assertFalse(isHysteriaCore(mapOf("vpnCore" to "xray")))
        assertFalse(isHysteriaCore(mapOf("vpnCore" to "trusttunnel")))
    }
}
