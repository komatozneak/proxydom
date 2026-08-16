package com.teremok.connect.teremok_connect

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val REQUEST_VPN_PERMISSION = 1001
        private const val REQUEST_POST_NOTIFICATIONS = 1002
        private const val REQUEST_INTERNET = 1003
    }

    @Volatile
    private var pendingPermissionResult: MethodChannel.Result? = null

    @Volatile
    private var pendingNotificationResult: MethodChannel.Result? = null

    @Volatile
    private var pendingTileConnect = false

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleTileIntent(intent)
    }

    /**
     * QS tile collapsed here when [VpnService.prepare] is non-null or persisted
     * params are missing. Consent → start last session without waiting for Flutter.
     */
    private fun handleTileIntent(intent: Intent?) {
        if (intent?.action != TeremokTileService.ACTION_TILE_TOGGLE) return
        intent.action = Intent.ACTION_MAIN
        if (!TeremokVpnService.hasPersistedParams(this)) {
            Log.i(TAG, "QS tile: no persisted session — Home")
            return
        }
        val prepareIntent = TeremokVpnService.prepareVpn(this)
        if (prepareIntent == null) {
            TeremokVpnService.startFromPersistedSession(this)
            return
        }
        pendingTileConnect = true
        Log.i(TAG, "QS tile: launching VPN consent")
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(prepareIntent, REQUEST_VPN_PERMISSION)
        } catch (e: Exception) {
            pendingTileConnect = false
            Log.w(TAG, "QS tile: consent launch failed", e)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Android 15 edge-to-edge: draw behind system bars; SafeArea keeps insets.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // Android 17 (API 37) on this Pixel: INTERNET is prot=dangerous.
        // Without a runtime grant, Dart sockets fail with errno 13 (EACCES).
        ensureInternetPermission()
        super.onCreate(savedInstanceState)
    }

    /**
     * Request INTERNET when the platform treats it as dangerous (Android 17+).
     * On older builds where INTERNET is still normal/install-time, check returns
     * GRANTED and we no-op.
     */
    private fun ensureInternetPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.INTERNET)
            == PackageManager.PERMISSION_GRANTED
        ) {
            Log.i(TAG, "INTERNET already granted")
            return
        }
        Log.i(TAG, "Requesting runtime INTERNET (dangerous on Android 17+)")
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.INTERNET),
            REQUEST_INTERNET,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        VpnStatusBroadcaster.attachAppContext(applicationContext)
        // Prompt early so FGS notification is visible when VPN connects.
        ensureNotificationPermission(null)
        handleTileIntent(intent)

        VpnChannelRegistry.register(
            engine = flutterEngine,
            appContext = applicationContext,
            activityProvider = { this },
            serviceProvider = { TeremokVpnService.currentInstance() },
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
            onNotificationPermissionRequest = { result ->
                ensureNotificationPermission(result)
            },
        )
    }

    /** Android 13+: runtime POST_NOTIFICATIONS so VPN card appears in the shade. */
    private fun ensureNotificationPermission(result: MethodChannel.Result?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result?.success(true)
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result?.success(true)
            return
        }
        if (result != null) {
            if (pendingNotificationResult != null) {
                result.error("busy", "notification permission request in progress", null)
                return
            }
            pendingNotificationResult = result
        }
        Log.i(TAG, "Requesting POST_NOTIFICATIONS")
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
        if (result == null) {
            // Fire-and-forget from configureFlutterEngine — no Flutter Result to fill.
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_INTERNET -> {
                val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                Log.i(TAG, "INTERNET granted=$granted")
            }
            REQUEST_POST_NOTIFICATIONS -> {
                val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                Log.i(TAG, "POST_NOTIFICATIONS granted=$granted")
                pendingNotificationResult?.success(granted)
                pendingNotificationResult = null
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_VPN_PERMISSION) return

        val granted = resultCode == Activity.RESULT_OK && VpnService.prepare(this) == null
        val conflict = TeremokVpnService.queryVpnConflict(this)
        Log.i(
            TAG,
            "VPN permission resultCode=$resultCode, granted=$granted, conflict=$conflict",
        )
        if (pendingTileConnect) {
            pendingTileConnect = false
            if (granted) {
                TeremokVpnService.startFromPersistedSession(this)
            }
        }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }
}
