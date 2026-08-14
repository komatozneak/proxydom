package com.teremok.connect.teremok_connect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnShadePolicyTest {

    @Test
    fun `disconnect allowed for ordinary user session`() {
        assertTrue(
            VpnShadePolicy.allowUserDisconnect(
                alwaysOn = false,
                lockdown = false,
                sdkInt = 34,
                appInitiated = true,
            ),
        )
    }

    @Test
    fun `always-on hides disconnect`() {
        assertFalse(
            VpnShadePolicy.allowUserDisconnect(
                alwaysOn = true,
                lockdown = false,
                sdkInt = 34,
                appInitiated = true,
            ),
        )
    }

    @Test
    fun `lockdown hides disconnect`() {
        assertFalse(
            VpnShadePolicy.allowUserDisconnect(
                alwaysOn = false,
                lockdown = true,
                sdkInt = 34,
                appInitiated = true,
            ),
        )
    }

    @Test
    fun `pre-Q system start hides disconnect`() {
        assertFalse(
            VpnShadePolicy.allowUserDisconnect(
                alwaysOn = null,
                lockdown = null,
                sdkInt = 28,
                appInitiated = false,
            ),
        )
        assertTrue(
            VpnShadePolicy.allowUserDisconnect(
                alwaysOn = null,
                lockdown = null,
                sdkInt = 28,
                appInitiated = true,
            ),
        )
    }

    @Test
    fun `tile lockdown is unavailable`() {
        assertEquals(
            VpnShadePolicy.TILE_UNAVAILABLE,
            VpnShadePolicy.tileState("connected", lockdown = true),
        )
        assertEquals(
            VpnShadePolicy.TILE_ACTIVE,
            VpnShadePolicy.tileState("connected", lockdown = false),
        )
        assertEquals(
            VpnShadePolicy.TILE_UNAVAILABLE,
            VpnShadePolicy.tileState("connecting", lockdown = false),
        )
        assertEquals(
            VpnShadePolicy.TILE_INACTIVE,
            VpnShadePolicy.tileState("idle", lockdown = false),
        )
    }

    @Test
    fun `add-tile callback mapping`() {
        assertEquals(
            VpnShadePolicy.ADD_TILE_ADDED,
            VpnShadePolicy.mapAddTileResult(
                VpnShadePolicy.TILE_ADD_REQUEST_RESULT_TILE_ADDED,
            ),
        )
        assertEquals(
            VpnShadePolicy.ADD_TILE_ALREADY,
            VpnShadePolicy.mapAddTileResult(
                VpnShadePolicy.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED,
            ),
        )
        assertEquals(
            VpnShadePolicy.ADD_TILE_NOT_ADDED,
            VpnShadePolicy.mapAddTileResult(
                VpnShadePolicy.TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED,
            ),
        )
        assertEquals(VpnShadePolicy.ADD_TILE_NOT_ADDED, VpnShadePolicy.mapAddTileResult(1001))
    }

    @Test
    fun `persisted params require a core or endpoint`() {
        assertFalse(VpnShadePolicy.isUsableParamsJson(null))
        assertFalse(VpnShadePolicy.isUsableParamsJson(""))
        assertFalse(VpnShadePolicy.isUsableParamsJson("{}"))
        assertFalse(VpnShadePolicy.isUsableParamsJson("{not-json"))
        assertTrue(VpnShadePolicy.isUsableParamsJson("""{"vpnCore":"hysteria"}"""))
        assertTrue(VpnShadePolicy.isUsableParamsJson("""{"vpnCore":"xray"}"""))
        assertTrue(VpnShadePolicy.isUsableParamsJson("""{"address":"172.19.0.1"}"""))
        assertTrue(VpnShadePolicy.isUsableParamsJson("""{"outboundServer":"10.0.0.1"}"""))
        assertTrue(VpnShadePolicy.isUsableParamsJson("""{"xrayCandidateConfigs":[]}"""))
    }
}
