package com.teremok.connect.teremok_connect

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile «Теремок VPN».
 *
 * Toggle only: ACTIVE while up / bringing up, INACTIVE when idle.
 * Click always start/stop (Amnezia). Always-on may restart the tunnel.
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
        if (isLocked) {
            unlockAndRun { handleClick() }
        } else {
            handleClick()
        }
    }

    private fun handleClick() {
        val status = TeremokVpnService.resolveUiStatus(applicationContext)
        when (status) {
            "connected", "connecting", "preparing" -> {
                TeremokVpnService.stopVpnService(applicationContext)
                applyTile(Tile.STATE_INACTIVE, status = "idle")
            }
            else -> {
                val prepared = VpnService.prepare(this) == null
                val started = prepared &&
                    TeremokVpnService.startFromPersistedSession(applicationContext)
                if (started) {
                    applyTile(Tile.STATE_ACTIVE, status = "connecting")
                } else {
                    collapseToApp()
                }
            }
        }
    }

    private fun collapseToApp() {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            action = ACTION_TILE_TOGGLE
        }
        collapseWith(intent)
    }

    private fun collapseWith(intent: Intent) {
        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    applicationContext,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        } else {
            startActivityAndCollapse(intent)
        }
    }

    private fun updateTileState() {
        val status = TeremokVpnService.resolveUiStatus(applicationContext)
        applyTile(TeremokVpnService.tileStateFor(status), status)
    }

    private fun applyTile(state: Int, status: String) {
        val tile = qsTile ?: return
        tile.state = state
        tile.label = getString(R.string.qs_tile_label)
        tile.icon = Icon.createWithResource(
            this,
            if (state == Tile.STATE_ACTIVE) R.drawable.ic_qs_vpn else R.drawable.ic_qs_vpn_off,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = getString(
                when (status) {
                    "connected" -> R.string.qs_tile_subtitle_on
                    "connecting", "preparing" -> R.string.qs_tile_subtitle_busy
                    else -> R.string.qs_tile_subtitle_off
                },
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            tile.stateDescription = tile.subtitle
        }
        tile.updateTile()
    }

    companion object {
        const val ACTION_TILE_TOGGLE = "com.teremok.connect.QS_TILE_TOGGLE"

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
