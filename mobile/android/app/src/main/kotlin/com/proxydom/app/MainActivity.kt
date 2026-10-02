package com.teremok.connect.teremok_connect

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.util.Log
import androidx.activity.enableEdgeToEdge
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
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

    private val internetLock = Any()
    private val pendingInternetResults = mutableListOf<MethodChannel.Result>()
    @Volatile
    private var internetRequestInFlight = false
    @Volatile
    private var notifyAfterInternet = false
    @Volatile
    private var internetEmptyResultRetries = 0

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
        // Android 15+: FlutterActivity is not a ComponentActivity; FragmentActivity is.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    private fun hasInternetPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.INTERNET) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Request INTERNET when the platform treats it as dangerous (Android 17+).
     * On older builds where INTERNET is still normal/install-time, check returns
     * GRANTED and we no-op.
     *
     * Dart awaits this via MethodChannel before discovery/register so the
     * POST_NOTIFICATIONS dialog cannot race sockets (errno 13).
     */
    private fun ensureInternetPermission(flutterResult: MethodChannel.Result?) {
        if (hasInternetPermission()) {
            Log.i(TAG, "INTERNET already granted")
            flutterResult?.success(true)
            return
        }
        val shouldRequest: Boolean
        synchronized(internetLock) {
            if (flutterResult != null) {
                pendingInternetResults.add(flutterResult)
            }
            if (internetRequestInFlight) {
                shouldRequest = false
            } else {
                internetRequestInFlight = true
                shouldRequest = true
            }
        }
        if (!shouldRequest) return
        Log.i(TAG, "Requesting runtime INTERNET (dangerous on Android 17+)")
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.INTERNET),
            REQUEST_INTERNET,
        )
    }

    private fun onInternetPermissionResult(granted: Boolean) {
        val queued: List<MethodChannel.Result>
        val shouldNotify: Boolean
        synchronized(internetLock) {
            internetRequestInFlight = false
            queued = pendingInternetResults.toList()
            pendingInternetResults.clear()
            shouldNotify = notifyAfterInternet
            notifyAfterInternet = false
        }
        Log.i(TAG, "INTERNET granted=$granted queued=${queued.size}")
        for (pending in queued) {
            pending.success(granted)
        }
        if (shouldNotify) {
            ensureNotificationPermission(null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        VpnStatusBroadcaster.attachAppContext(applicationContext)
        // Android 17: INTERNET is dangerous. Prompt here (activity is ready),
        // not in onCreate before super — that dialog is dropped. Do not request
        // POST_NOTIFICATIONS until INTERNET is resolved: a second
        // requestPermissions() cancels the INTERNET dialog on API 37.
        if (hasInternetPermission()) {
            ensureNotificationPermission(null)
        } else {
            synchronized(internetLock) { notifyAfterInternet = true }
            ensureInternetPermission(flutterResult = null)
        }
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
            onInternetPermissionRequest = { result ->
                ensureInternetPermission(result)
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
                if (grantResults.isEmpty()) {
                    // Cancelled (activity not ready / overlapping prompt).
                    val waiting: Boolean
                    synchronized(internetLock) {
                        internetRequestInFlight = false
                        waiting = pendingInternetResults.isNotEmpty() ||
                            notifyAfterInternet
                    }
                    if (waiting && internetEmptyResultRetries < 2) {
                        internetEmptyResultRetries++
                        ensureInternetPermission(flutterResult = null)
                    } else {
                        onInternetPermissionResult(hasInternetPermission())
                    }
                    return
                }
                internetEmptyResultRetries = 0
                val granted = grantResults[0] == PackageManager.PERMISSION_GRANTED
                onInternetPermissionResult(granted)
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
