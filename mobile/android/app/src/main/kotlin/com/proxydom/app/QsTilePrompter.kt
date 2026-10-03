package com.proxydom.app

import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Whether the user currently has the tile in Quick Settings.
 *
 * Android has no API for an app to remove a tile. [ProxyDomTileService]
 * updates this from [onTileAdded] / [onTileRemoved]; the add prompt sets it
 * when the system reports the tile is already there.
 */
object QsTilePresence {
    private const val PREFS = "qs_tile_presence"
    private const val KEY_ADDED = "added"

    fun isAdded(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ADDED, false)

    fun setAdded(context: Context, added: Boolean) {
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ADDED, added)
            .apply()
    }
}

/** API 33+ [StatusBarManager.requestAddTileService]; below 33 → `manual`. */
object QsTilePrompter {
    private const val TAG = "QsTilePrompter"

    fun requestAdd(context: Context, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(VpnShadePolicy.ADD_TILE_MANUAL)
            return
        }
        val sb = context.getSystemService(StatusBarManager::class.java)
        if (sb == null) {
            result.success(VpnShadePolicy.ADD_TILE_MANUAL)
            return
        }
        val replied = AtomicBoolean(false)
        val reply: (String) -> Unit = { value ->
            if (replied.compareAndSet(false, true)) {
                result.success(value)
            }
        }
        try {
            val component = ComponentName(context, ProxyDomTileService::class.java)
            // Same Living House as ic_launcher_monochrome (tight crop for the dialog).
            val icon = Icon.createWithResource(context, R.drawable.ic_qs_vpn)
            sb.requestAddTileService(
                component,
                context.getString(R.string.qs_tile_label),
                icon,
                ContextCompat.getMainExecutor(context),
            ) { code ->
                val mapped = VpnShadePolicy.mapAddTileResult(code)
                if (mapped == VpnShadePolicy.ADD_TILE_ADDED ||
                    mapped == VpnShadePolicy.ADD_TILE_ALREADY
                ) {
                    QsTilePresence.setAdded(context, true)
                }
                reply(mapped)
            }
        } catch (e: Exception) {
            Log.w(TAG, "requestAddTileService failed", e)
            reply(VpnShadePolicy.ADD_TILE_MANUAL)
        }
    }
}
