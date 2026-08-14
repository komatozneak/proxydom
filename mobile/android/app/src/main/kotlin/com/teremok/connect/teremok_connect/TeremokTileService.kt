package com.teremok.connect.teremok_connect

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

/**
 * Quick Settings tile «Теремок VPN».
 *
 * Idle + consent already granted → [TeremokVpnService.startFromPersistedSession].
 * Otherwise collapse into [MainActivity] (VPN prepare dialog / Nest).
 * Connected stop is skipped when Always-on / lockdown owns the session.
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
        val status = VpnStatusBroadcaster.currentStatus()
        val allowStop = TeremokVpnService.allowUserDisconnect(applicationContext)
        when (status) {
            "connected", "connecting", "preparing" -> {
                if (!allowStop) {
                    Log.i(TAG, "tile stop skipped always-on/lockdown status=$status")
                    updateTileState()
                    return
                }
                TeremokVpnService.stopVpnService(applicationContext)
                setTile(Tile.STATE_INACTIVE)
            }
            else -> {
                val prepared = VpnService.prepare(this) == null
                val started = prepared &&
                    TeremokVpnService.startFromPersistedSession(applicationContext)
                if (started) {
                    setTile(Tile.STATE_UNAVAILABLE)
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
        val tile = qsTile ?: return
        val snap = TeremokVpnService.queryAlwaysOnVpnSnapshot(applicationContext)
        val lockdown = snap["lockdown"] as? Boolean
        tile.state = TeremokVpnService.tileStateFor(
            VpnStatusBroadcaster.currentStatus(),
            lockdown,
        )
        tile.updateTile()
    }

    private fun setTile(state: Int) {
        qsTile?.let {
            it.state = state
            it.updateTile()
        }
    }

    companion object {
        private const val TAG = "TeremokTile"
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
