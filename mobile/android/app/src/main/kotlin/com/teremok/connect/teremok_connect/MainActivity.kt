package com.teremok.connect.teremok_connect

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val REQUEST_VPN_PERMISSION = 1001
    }

    /**
     * Текущий инстанс сервиса. На этом шаге сервис создаётся через
     * startService() (см. VpnChannelRegistry.start/stop), поэтому
     * ссылка может быть null — getStatus() вернёт "idle".
     * В Шаге 14 заменим на реальный binding через IBinder.
     */
    @Volatile
    private var activeService: TeremokVpnService? = null

    @Volatile
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        VpnChannelRegistry.register(
            engine = flutterEngine,
            appContext = applicationContext,
            serviceProvider = { activeService },
            onPermissionRequest = { result ->
                val prepareIntent: Intent? = TeremokVpnService.prepareVpn(this)
                if (prepareIntent == null) {
                    result.success(true)
                } else if (pendingPermissionResult != null) {
                    result.error("busy", "VPN permission request already in progress", null)
                } else {
                    pendingPermissionResult = result
                    Log.i(TAG, "Launching VPN consent dialog via VpnService.prepare()")
                    try {
                        @Suppress("DEPRECATION")
                        startActivityForResult(prepareIntent, REQUEST_VPN_PERMISSION)
                    } catch (e: Exception) {
                        pendingPermissionResult = null
                        result.error("launch_failed", e.message, null)
                    }
                }
            },
        )
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_VPN_PERMISSION) return

        val granted = resultCode == Activity.RESULT_OK && VpnService.prepare(this) == null
        Log.i(TAG, "VPN permission resultCode=$resultCode, granted=$granted")
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }
}