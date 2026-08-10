package com.teremok.connect.teremok_connect

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile «Теремок VPN»: click toggles connect/disconnect,
 * long-press opens the app. State mirrors TeremokVpnService status.
 *
 * Connect from the tile must go through the Flutter layer (needs /vpn/config),
 * so we launch MainActivity with ACTION_TILE_TOGGLE — the app starts the VPN.
 * Disconnect can stop the service directly.
 */
class TeremokTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        val status = VpnStatusBroadcaster.currentStatus()
        when (status) {
            "connected", "connecting", "preparing" -> {
                // Stop directly — no Flutter round-trip needed.
                TeremokVpnService.stopVpnService(applicationContext)
                setTile(Tile.STATE_INACTIVE)
            }
            else -> {
                // Start needs /vpn/config + consent → hand off to the app.
                val intent = Intent(applicationContext, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    action = ACTION_TILE_TOGGLE
                }
                @Suppress("DEPRECATION")
                if (android.os.Build.VERSION.SDK_INT >= 34) {
                    startActivityAndCollapse(
                        android.app.PendingIntent.getActivity(
                            applicationContext,
                            0,
                            intent,
                            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                                android.app.PendingIntent.FLAG_IMMUTABLE,
                        ),
                    )
                } else {
                    startActivityAndCollapse(intent)
                }
                setTile(Tile.STATE_UNAVAILABLE)
            }
        }
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val status = VpnStatusBroadcaster.currentStatus()
        tile.state = when (status) {
            "connected" -> Tile.STATE_ACTIVE
            "connecting", "preparing" -> Tile.STATE_UNAVAILABLE
            else -> Tile.STATE_INACTIVE
        }
        tile.updateTile()
    }

    private fun setTile(state: Int) {
        qsTile?.let {
            it.state = state
            it.updateTile()
        }
    }

    companion object {
        const val ACTION_TILE_TOGGLE = "com.teremok.connect.QS_TILE_TOGGLE"

        /** Ask the system to refresh tile state after VPN status changes. */
        fun requestListening(context: Context) {
            runCatching {
                requestListeningState(
                    context.applicationContext,
                    ComponentName(context.applicationContext, TeremokTileService::class.java),
                )
            }
        }
    }
}
