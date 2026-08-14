package com.teremok.connect.teremok_connect

/**
 * Pure rules for shade disconnect + Quick Settings tile.
 *
 * Always-on / lockdown: Android VPN UX requires hiding app-owned disconnect
 * UI when the system owns the session. API 26–28 has no [isAlwaysOn]; unmarked
 * (system) starts are treated as system-managed.
 */
object VpnShadePolicy {
    const val TILE_UNAVAILABLE = 0
    const val TILE_INACTIVE = 1
    const val TILE_ACTIVE = 2

    const val ADD_TILE_ADDED = "added"
    const val ADD_TILE_ALREADY = "already_added"
    const val ADD_TILE_NOT_ADDED = "not_added"
    const val ADD_TILE_MANUAL = "manual"

    /** StatusBarManager.requestAddTileService callback codes (API 33). */
    const val TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED = 0
    const val TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED = 1
    const val TILE_ADD_REQUEST_RESULT_TILE_ADDED = 2

    fun allowUserDisconnect(
        alwaysOn: Boolean?,
        lockdown: Boolean?,
        sdkInt: Int,
        appInitiated: Boolean,
    ): Boolean {
        if (lockdown == true) return false
        if (alwaysOn == true) return false
        if (sdkInt < 29 && !appInitiated) return false
        return true
    }

    fun tileState(status: String, lockdown: Boolean?): Int {
        if (lockdown == true) return TILE_UNAVAILABLE
        return when (status) {
            "connected" -> TILE_ACTIVE
            "connecting", "preparing" -> TILE_UNAVAILABLE
            else -> TILE_INACTIVE
        }
    }

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
