package com.teremok.connect.teremok_connect

import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

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
            val component = ComponentName(context, TeremokTileService::class.java)
            val icon = Icon.createWithResource(context, R.drawable.ic_qs_vpn)
            sb.requestAddTileService(
                component,
                context.getString(R.string.qs_tile_label),
                icon,
                ContextCompat.getMainExecutor(context),
            ) { code ->
                reply(VpnShadePolicy.mapAddTileResult(code))
            }
        } catch (e: Exception) {
            Log.w(TAG, "requestAddTileService failed", e)
            reply(VpnShadePolicy.ADD_TILE_MANUAL)
        }
    }
}
