package com.teremok.connect.teremok_connect

/**
 * Shade + QS tile: one connection state, two projections.
 *
 * Tile and shade action always start/stop (Amnezia contract). Always-on
 * does not rewrite the action to system VPN settings.
 */
object VpnShadePolicy {
    const val TILE_UNAVAILABLE = 0
    const val TILE_INACTIVE = 1
    const val TILE_ACTIVE = 2

    const val ADD_TILE_ADDED = "added"
    const val ADD_TILE_ALREADY = "already_added"
    const val ADD_TILE_NOT_ADDED = "not_added"
    const val ADD_TILE_MANUAL = "manual"

    const val SHADE_ACTION_STOP = "stop"
    const val SHADE_ACTION_VPN_SETTINGS = "vpn_settings"

    /** StatusBarManager.requestAddTileService callback codes (API 33). */
    const val TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED = 0
    const val TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED = 1
    const val TILE_ADD_REQUEST_RESULT_TILE_ADDED = 2

    /**
     * System owns the session lifecycle (Always-on on *our* instance).
     * Lockdown alone is not ownership. API 26–28: unmarked starts are system.
     */
    fun systemOwnsSession(
        alwaysOnOnOurInstance: Boolean?,
        sdkInt: Int,
        appInitiated: Boolean,
    ): Boolean {
        if (alwaysOnOnOurInstance == true) return true
        if (sdkInt < 29 && !appInitiated) return true
        return false
    }

    fun allowUserDisconnect(
        alwaysOnOnOurInstance: Boolean?,
        sdkInt: Int,
        appInitiated: Boolean,
    ): Boolean = !systemOwnsSession(alwaysOnOnOurInstance, sdkInt, appInitiated)

    /** VPN tile is a toggle. Connecting is ACTIVE, never UNAVAILABLE. */
    fun tileState(status: String): Int = when (status) {
        "connected", "connecting", "preparing" -> TILE_ACTIVE
        else -> TILE_INACTIVE
    }

    fun shadeActionKind(): String = SHADE_ACTION_STOP

    /** Connected FGS always has an action, including the quiet stub. */
    fun showConnectedAction(status: String): Boolean =
        status == "connected"

    fun mapAddTileResult(code: Int): String = when (code) {
        TILE_ADD_REQUEST_RESULT_TILE_ADDED -> ADD_TILE_ADDED
        TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED -> ADD_TILE_ALREADY
        else -> ADD_TILE_NOT_ADDED
    }

    /** Last-session JSON is enough to start without Flutter minting a new config. */
    fun isUsableParamsJson(paramsJson: String?): Boolean {
        if (paramsJson.isNullOrBlank()) return false
        val t = paramsJson.trim()
        if (t.length < 8 || t[0] != '{') return false
        return hasJsonKey(t, "vpnCore") ||
            hasJsonKey(t, "xrayCandidateConfigs") ||
            hasJsonKey(t, "address") ||
            hasJsonKey(t, "outboundServer")
    }

    private fun hasJsonKey(json: String, key: String): Boolean =
        json.contains("\"$key\"")
}
