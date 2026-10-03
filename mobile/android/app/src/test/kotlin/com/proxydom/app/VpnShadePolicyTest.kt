package com.proxydom.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnShadePolicyTest {

    private val statuses = listOf(
        "idle", "connecting", "preparing", "connected", "error", "revoked",
    )
    private val flags = listOf(true, false, null)
    private val sdks = listOf(28, 34)

    @Test
    fun `tile is only ACTIVE or INACTIVE for every state combo`() {
        for (status in statuses) {
            val state = VpnShadePolicy.tileState(status)
            assertTrue(
                "$status → $state",
                state == VpnShadePolicy.TILE_ACTIVE ||
                    state == VpnShadePolicy.TILE_INACTIVE,
            )
            assertTrue(state != VpnShadePolicy.TILE_UNAVAILABLE)
        }
    }

    @Test
    fun `connected and connecting are ACTIVE even under lockdown flags`() {
        assertEquals(VpnShadePolicy.TILE_ACTIVE, VpnShadePolicy.tileState("connected"))
        assertEquals(VpnShadePolicy.TILE_ACTIVE, VpnShadePolicy.tileState("connecting"))
        assertEquals(VpnShadePolicy.TILE_ACTIVE, VpnShadePolicy.tileState("preparing"))
        assertEquals(VpnShadePolicy.TILE_INACTIVE, VpnShadePolicy.tileState("idle"))
    }

    @Test
    fun `connected notification always has an action`() {
        assertTrue(VpnShadePolicy.showConnectedAction("connected"))
        assertFalse(VpnShadePolicy.showConnectedAction("connecting"))
        assertFalse(VpnShadePolicy.showConnectedAction("idle"))
        assertEquals(VpnShadePolicy.SHADE_ACTION_STOP, VpnShadePolicy.shadeActionKind())
    }

    @Test
    fun `shade action is always STOP across always-on lockdown sdk`() {
        for (alwaysOn in flags) {
            for (lockdown in flags) {
                for (sdk in sdks) {
                    val owns = VpnShadePolicy.systemOwnsSession(
                        alwaysOnOnOurInstance = alwaysOn,
                        sdkInt = sdk,
                        appInitiated = true,
                    )
                    assertTrue(
                        "alwaysOn=$alwaysOn lockdown=$lockdown sdk=$sdk owns=$owns",
                        VpnShadePolicy.showConnectedAction("connected"),
                    )
                    assertEquals(
                        "alwaysOn=$alwaysOn lockdown=$lockdown sdk=$sdk owns=$owns",
                        VpnShadePolicy.SHADE_ACTION_STOP,
                        VpnShadePolicy.shadeActionKind(),
                    )
                    assertTrue(
                        VpnShadePolicy.shadeActionKind() !=
                            VpnShadePolicy.SHADE_ACTION_VPN_SETTINGS,
                    )
                    assertEquals(
                        VpnShadePolicy.TILE_ACTIVE,
                        VpnShadePolicy.tileState("connected"),
                    )
                }
            }
        }
    }

    @Test
    fun `always-on on our instance owns the session`() {
        assertTrue(
            VpnShadePolicy.systemOwnsSession(
                alwaysOnOnOurInstance = true,
                sdkInt = 34,
                appInitiated = true,
            ),
        )
        assertFalse(
            VpnShadePolicy.allowUserDisconnect(
                alwaysOnOnOurInstance = true,
                sdkInt = 34,
                appInitiated = true,
            ),
        )
    }

    @Test
    fun `ordinary user session can stop`() {
        assertTrue(
            VpnShadePolicy.allowUserDisconnect(
                alwaysOnOnOurInstance = false,
                sdkInt = 34,
                appInitiated = true,
            ),
        )
    }

    @Test
    fun `pre-Q unmarked start is system-owned`() {
        assertTrue(
            VpnShadePolicy.systemOwnsSession(
                alwaysOnOnOurInstance = null,
                sdkInt = 28,
                appInitiated = false,
            ),
        )
        assertFalse(
            VpnShadePolicy.systemOwnsSession(
                alwaysOnOnOurInstance = null,
                sdkInt = 28,
                appInitiated = true,
            ),
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
