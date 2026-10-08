package com.proxydom.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.NetworkCapabilities
import android.net.VpnService
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.system.OsConstants
import hy2bind.Hy2bind
import java.net.InetAddress
import java.net.InetSocketAddress
import android.system.ErrnoException
import android.system.Os
import android.system.StructPollfd
import android.system.StructTimeval
import java.io.FileDescriptor
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import com.proxydom.app.session.AutoCandidate
import com.proxydom.app.session.PathHealth
import com.proxydom.app.session.SessionPhase
import com.proxydom.app.session.SessionSnapshot
import com.proxydom.app.session.SessionSnapshotBroadcaster
import com.proxydom.app.session.VpnSessionEngine
import com.proxydom.app.session.hysteriaSocksListen
import com.proxydom.app.session.socksWatchFor
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Android VpnService, Hysteria2-only (ADR 018):
 * VpnService TUN → hy2bind startTun + SOCKS prove on :10808.
 *
 * ADR 020: product opts out of Always-on (`SUPPORTS_ALWAYS_ON=false`).
 * Sticky restore / QS persist / foreign Always-on conflict / lockdown leftover
 * routing stay — they are not product Always-on promotion.
 */
class ProxyDomVpnService : VpnService() {

    companion object {
        const val TAG = "ProxyDomVpn"
        const val ACTION_START = "com.proxy.dom.START_VPN"
        const val ACTION_START_AUTO = "com.proxy.dom.START_VPN_AUTO"
        const val ACTION_STOP = "com.proxy.dom.STOP_VPN"
        const val EXTRA_AUTO_CANDIDATES = "autoCandidatesJson"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_PROTOCOL = "protocol"
        const val EXTRA_PARAMS_JSON = "paramsJson"
        const val EXTRA_APP_INITIATED = "appInitiated"

        /** Session payload schema from Flutter VpnServiceConfig / VpnController. */
        const val SESSION_SCHEMA_VERSION = 2

        /** paramsJson["vpnCore"] — Hysteria2 only (ADR 018). */
        const val VPN_CORE_HYSTERIA = "hysteria"

        const val PREFS_NAME = "proxydom_vpn_session"
        private const val KEY_PARAMS_JSON = "params_json"
        private const val KEY_USERNAME = "username"
        private const val KEY_PROTOCOL = "protocol"
        private const val KEY_ACTIVE = "active"
        private const val KEY_APP_INITIATED = "app_initiated"

        @Volatile
        private var instance: ProxyDomVpnService? = null

        fun currentInstance(): ProxyDomVpnService? = instance

        /**
         * Always-on "Block connections without VPN" — **preference / system setting**,
         * not "is the tunnel connected right now".
         *
         * [VpnService.isLockdownEnabled] is the preferred positive signal (API 29+):
         * true means lockdown is active for this app. false is **not** authoritative
         * when the service is idle / tunnel down (Always-on may keep the process
         * alive after Nest disconnect).
         *
         * [Settings.Secure] keys `always_on_vpn_*` are @hide; on Android 12+ (S)
         * non-system apps often get [SecurityException] ("is not readable"). Probes
         * are best-effort only — **never throw** into VPN start / MethodChannel.
         *
         * @return true/false when known; null when Secure is unreadable and runtime
         *         is not positively true (Settings tile → Unknown / open VPN settings).
         */
        fun queryAlwaysOnVpnLockdown(
            context: android.content.Context,
            service: ProxyDomVpnService? = currentInstance(),
        ): Boolean? {
            val snap = queryAlwaysOnVpnSnapshot(context, service)
            return snap["lockdown"] as Boolean?
        }

        /**
         * Rich Always-on / lockdown snapshot for Settings.
         *
         * Keys: lockdown (Boolean?), alwaysOn (Boolean?),
         * secureLockdown (Boolean?), runtimeLockdown (Boolean?).
         */
        fun queryAlwaysOnVpnSnapshot(
            context: android.content.Context,
            service: ProxyDomVpnService? = currentInstance(),
        ): Map<String, Any?> {
            var fromRuntime: Boolean? = null
            var alwaysOnRuntime: Boolean? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val svc = service ?: currentInstance()
                if (svc != null) {
                    fromRuntime = runCatching { svc.isLockdownEnabled }
                        .onFailure { NativeLog.w(TAG, "VpnService.isLockdownEnabled failed", it) }
                        .getOrNull()
                    alwaysOnRuntime = runCatching { svc.isAlwaysOn }
                        .onFailure { NativeLog.w(TAG, "VpnService.isAlwaysOn failed", it) }
                        .getOrNull()
                }
            }

            // Best-effort Secure probes. Never use getInt(…, default=0) — a missing
            // / blocked key would look like lockdown OFF (Pixel log: Secure=false
            // while Always-on lockdown was ON in UI → Settings tile stuck on Выкл).
            val alwaysOnPkg = readSecureString(context, "always_on_vpn_app")
            val fromSecure = readSecureLockdownEnabled(context)

            val alwaysOnForUs = when {
                alwaysOnRuntime == true -> true
                alwaysOnPkg != null && alwaysOnPkg == context.packageName -> true
                alwaysOnPkg != null && alwaysOnPkg != context.packageName -> false
                else -> alwaysOnRuntime
            }

            val lockdown: Boolean? = when {
                fromRuntime == true -> true
                fromSecure == true -> true
                // Explicit Secure 0 only when the key exists (not defaulted).
                fromSecure == false -> false
                // Runtime false is trustworthy when the service is alive.
                fromRuntime == false -> false
                // Idle + Secure unknown → do not claim "disabled".
                else -> null
            }

            NativeLog.i(
                TAG,
                "lockdown snap Secure=$fromSecure runtime=$fromRuntime " +
                    "alwaysOnRuntime=$alwaysOnRuntime alwaysOnPkg=$alwaysOnPkg " +
                    "svc=${service != null || currentInstance() != null} " +
                    "→ lockdown=$lockdown alwaysOn=$alwaysOnForUs pkg=${context.packageName}",
            )

            return mapOf(
                "lockdown" to lockdown,
                "alwaysOn" to alwaysOnForUs,
                "secureLockdown" to fromSecure,
                "runtimeLockdown" to fromRuntime,
            )
        }

        /**
         * Detect a VPN that blocks Proxy Dom: foreign Always-on / lockdown,
         * or another app's live VPN (system TRANSPORT_VPN without our TUN).
         *
         * Keys: foreignAlwaysOn (Boolean), foreignVpnActive (Boolean),
         * packageName (String?), appLabel (String?), lockdown (Boolean?).
         */
        fun queryVpnConflict(context: android.content.Context): Map<String, Any?> {
            val alwaysOnPkg = readSecureString(context, "always_on_vpn_app")?.trim()
                ?.takeIf { it.isNotEmpty() }
            val lockdown = readSecureLockdownEnabled(context)
            // VpnService.isAlwaysOn is only true while OUR service holds Always-on.
            val oursAlwaysOn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                currentInstance()?.let { svc ->
                    runCatching { svc.isAlwaysOn }.getOrNull()
                } == true
            } else {
                false
            }
            val foreignAlwaysOnPkg = alwaysOnPkg != null && alwaysOnPkg != context.packageName
            val occupying = isOurSessionOccupying()
            val foreignLockdown = lockdown == true && !oursAlwaysOn && !occupying
            // Live VPN from another app (no Always-on required). Skip while we
            // are establishing / already own the TUN / restoring an active session.
            val foreignVpn = isSystemVpnUp(context) && !occupying
            val foreign = foreignAlwaysOnPkg || foreignLockdown || foreignVpn
            val label = if (foreign && alwaysOnPkg != null && alwaysOnPkg != context.packageName) {
                resolveAppLabel(context, alwaysOnPkg)
            } else {
                null
            }
            NativeLog.i(
                TAG,
                "vpnConflict foreign=$foreign pkg=$alwaysOnPkg label=$label " +
                    "lockdown=$lockdown oursAlwaysOn=$oursAlwaysOn " +
                    "foreignVpn=$foreignVpn occupying=$occupying",
            )
            return mapOf(
                "foreignAlwaysOn" to foreign,
                "foreignVpnActive" to foreignVpn,
                "packageName" to if (foreignAlwaysOnPkg) alwaysOnPkg else null,
                "appLabel" to label,
                "lockdown" to lockdown,
            )
        }

        /** True while this app owns or is taking the system VPN slot. */
        fun isOurSessionOccupying(): Boolean {
            val svc = currentInstance() ?: return false
            if (svc.hasLiveTun() || svc.establishInProgress) return true
            return when (svc.currentStatus) {
                "connected", "connecting", "preparing", "probing" -> true
                else -> false
            }
        }

        private fun resolveAppLabel(context: android.content.Context, packageName: String): String {
            return try {
                val pm = context.packageManager
                val info = pm.getApplicationInfo(packageName, 0)
                pm.getApplicationLabel(info).toString().ifBlank { packageName }
            } catch (_: Exception) {
                packageName
            }
        }

        /** Best-effort [Settings.Secure] string; null on missing or S+ restriction. */
        private fun readSecureString(
            context: android.content.Context,
            key: String,
        ): String? =
            try {
                Settings.Secure.getString(context.contentResolver, key)
            } catch (e: SecurityException) {
                NativeLog.w(TAG, "Settings.Secure.$key not readable: ${e.message}")
                null
            } catch (e: IllegalArgumentException) {
                NativeLog.w(TAG, "Settings.Secure.$key invalid: ${e.message}")
                null
            }

        /**
         * Always-on lockdown flag from [Settings.Secure].
         *
         * @return true/false when the key is present and readable; null when
         *         missing, blocked (S+), or otherwise unknown — never invent OFF.
         */
        private fun readSecureLockdownEnabled(context: android.content.Context): Boolean? {
            val key = "always_on_vpn_lockdown"
            return try {
                Settings.Secure.getInt(context.contentResolver, key) == 1
            } catch (e: Settings.SettingNotFoundException) {
                // Fall back to string form some OEMs use; still no silent OFF.
                when (readSecureString(context, key)?.trim()) {
                    "1" -> true
                    "0" -> false
                    else -> null
                }
            } catch (e: SecurityException) {
                NativeLog.w(TAG, "Settings.Secure.$key not readable: ${e.message}")
                null
            } catch (e: IllegalArgumentException) {
                NativeLog.w(TAG, "Settings.Secure.$key invalid: ${e.message}")
                null
            }
        }

        /** Last successful connect still marked active (Always-on / UI sync). */
        fun hasActiveSession(context: android.content.Context): Boolean =
            sessionPrefs(context).getBoolean(KEY_ACTIVE, false)

        /** System reports a VPN transport (works even if [instance] is briefly null). */
        fun isSystemVpnUp(context: android.content.Context): Boolean {
            val cm = context.getSystemService(ConnectivityManager::class.java) ?: return false
            return cm.allNetworks.any { network ->
                val caps = cm.getNetworkCapabilities(network)
                caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            }
        }

        /**
         * Status for Flutter [getStatus] — prefer live TUN, then
         * active-session + system VPN (Always-on / process race).
         */
        fun resolveUiStatus(context: android.content.Context): String {
            val svc = instance
            if (svc != null && svc.hasLiveTun()) {
                val live = svc.currentStatus
                if (live == "idle") return "connected"
                return live
            }
            val live = svc?.currentStatus
            if (live != null && live != "idle") return live
            if (hasActiveSession(context) && isSystemVpnUp(context)) {
                return "connected"
            }
            if (live != null) return live
            val broadcast = VpnStatusBroadcaster.currentStatus()
            if (broadcast != "idle") return broadcast
            if (hasActiveSession(context) && isSystemVpnUp(context)) {
                return "connected"
            }
            return broadcast
        }

        /** Получить системный Intent для запроса VPN-разрешения, или null если уже есть. */
        fun prepareVpn(context: android.content.Context): Intent? {
            return VpnService.prepare(context)
        }

        /**
         * MethodChannel alias kept for Dart; returns Xray work-dir log tail when
         * present, otherwise empty string (libbox stderr removed).
         */
        fun readSingBoxStderrTail(context: android.content.Context, maxLines: Int): String {
            val ring = DiagnosticRing.tail(maxLines)
            val core = CoreLog.readTail(context, maxLines)
            val file = java.io.File(context.filesDir, "vless/stderr.log")
            val fileTail = if (!file.exists()) {
                ""
            } else {
                runCatching {
                    val lines = file.readLines()
                    if (lines.isEmpty()) "" else lines.takeLast(maxLines).joinToString("\n")
                }.getOrDefault("")
            }
            return listOf(ring, core, fileTail).filter { it.isNotBlank() }.joinToString("\n")
        }

        fun sessionPrefs(context: android.content.Context) =
            context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)

        /** Last successful connect params still on disk (survives intentional disconnect). */
        fun hasPersistedParams(context: android.content.Context): Boolean {
            val json = sessionPrefs(context).getString(KEY_PARAMS_JSON, null)
            return VpnShadePolicy.isUsableParamsJson(json)
        }

        fun isAppInitiatedSession(context: android.content.Context): Boolean =
            sessionPrefs(context).getBoolean(KEY_APP_INITIATED, true)

        /**
         * Always-on on *this* VpnService instance (API 29+).
         * Not [Settings.Secure] — that bit is global / foreign-VPN.
         */
        fun ourAlwaysOn(context: android.content.Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
            val svc = currentInstance() ?: return false
            return runCatching { svc.isAlwaysOn }.getOrNull() == true
        }

        fun systemOwnsSession(context: android.content.Context): Boolean =
            VpnShadePolicy.systemOwnsSession(
                alwaysOnOnOurInstance = ourAlwaysOn(context),
                sdkInt = Build.VERSION.SDK_INT,
                appInitiated = isAppInitiatedSession(context),
            )

        fun allowUserDisconnect(context: android.content.Context): Boolean =
            VpnShadePolicy.allowUserDisconnect(
                alwaysOnOnOurInstance = ourAlwaysOn(context),
                sdkInt = Build.VERSION.SDK_INT,
                appInitiated = isAppInitiatedSession(context),
            )

        fun tileStateFor(status: String): Int = VpnShadePolicy.tileState(status)

        fun isVpnRunning(): Boolean {
            val s = VpnStatusBroadcaster.currentStatus()
            return s == "connected" || s == "connecting" || s == "preparing"
        }

        /**
         * Start VPN from last saved params (Quick Settings tile / reconnect).
         * Returns false if no params — caller should open the app.
         */
        fun startFromPersistedSession(context: android.content.Context): Boolean {
            val store = sessionPrefs(context)
            val paramsJson = store.getString(KEY_PARAMS_JSON, null)
            if (paramsJson == null || !VpnShadePolicy.isUsableParamsJson(paramsJson)) {
                NativeLog.w(TAG, "startFromPersistedSession: no usable params")
                return false
            }
            val username = store.getString(KEY_USERNAME, "anonymous") ?: "anonymous"
            val protocol = store.getString(KEY_PROTOCOL, "unknown") ?: "unknown"
            val intent = Intent(context, ProxyDomVpnService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_USERNAME, username)
                putExtra(EXTRA_PROTOCOL, protocol)
                putExtra(EXTRA_PARAMS_JSON, paramsJson)
                putExtra(EXTRA_APP_INITIATED, true)
            }
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                NativeLog.w(TAG, "startFromPersistedSession: start failed", e)
                false
            }
        }

        fun stopVpnService(context: android.content.Context) {
            val intent = Intent(context, ProxyDomVpnService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        /**
         * Logout / identity change: wipe persisted VPN params so the QS tile
         * or an Always-on restart cannot resurrect the previous account's
         * tunnel (params_json contains dataplane passwords).
         */
        fun wipePersistedSession(context: android.content.Context) {
            sessionPrefs(context).edit().clear().apply()
            NativeLog.i(TAG, "wipePersistedSession: cleared stored VPN params")
        }
    }

    /** Sole Kotlin owner of the VpnService TUN PFD (null = transferred or closed). */
    private val tunInterface = AtomicReference<ParcelFileDescriptor?>(null)
    @Volatile
    private var isRunning = false
    @Volatile
    var lastShareTcp: String? = null

    @Volatile
    var provenEgressIp: String? = null
    /** True only while [startVpn] is establishing TUN/core (not onCreate hint). */
    @Volatile
    private var establishInProgress = false
    /** Prevents concurrent [teardownCores] from main + session dispatcher (fdsan). */
    private val teardownInFlight = AtomicBoolean(false)
    private var trafficMonitor: VpnTrafficMonitor? = null
    private var notificationSessionLine: String = "Прокси Дом"
    private val pathHealth = PathHealth()
    /** Params of the session [startVpn] is establishing. The watch reads this. */
    private var liveSessionParams: Map<String, Any?> = emptyMap()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var vpnWakeLock: PowerManager.WakeLock? = null
    private var vpnWifiLock: WifiManager.WifiLock? = null
    /** Hy2 died while TUN still up — recover without painting Nest rest. */
    @Volatile
    private var coreRecovering = false
    @Volatile
    private var deadRecoverAttempts = 0
    private var lastDeadRecoverAt = 0L
    private var deadRecoverRetry: Runnable? = null

    private val sessionEngine: VpnSessionEngine by lazy { VpnSessionEngine(sessionHost) }

    private val sessionHost = object : VpnSessionEngine.Host {
        override fun onSnapshot(snapshot: SessionSnapshot) {
            SessionSnapshotBroadcaster.emit(snapshot)
            if (snapshot.phase == SessionPhase.Error) {
                VpnStatusBroadcaster.setError(
                    snapshot.detail ?: snapshot.reason.name,
                )
            }
            currentStatus = snapshot.phase.toLegacyStatus()
            VpnStatusBroadcaster.emit(currentStatus)
            if (snapshot.phase == SessionPhase.ConnectedHealthy) {
                autoProving = false
                coreRecovering = false
                deadRecoverAttempts = 0
            } else if (snapshot.phase == SessionPhase.ConnectedDegraded ||
                snapshot.phase == SessionPhase.Error ||
                snapshot.phase == SessionPhase.Idle
            ) {
                autoProving = false
            }
        }

        override fun establishGeneration(
            generation: Long,
            username: String,
            protocol: String,
            params: Map<String, Any?>,
            alive: () -> Boolean,
            emit: (SessionSnapshot) -> Unit,
        ): Boolean {
            if (!alive()) return false
            startVpn(username, protocol, params, alive)
            return isRunning && alive()
        }

        override fun teardownGeneration(generation: Long) {
            val stopping = currentStatus == "disconnecting" ||
                sessionEngine.currentSnapshot().phase.toLegacyStatus() == "disconnecting"
            if (stopping) {
                stopVpn()
            } else {
                teardownCores()
            }
        }

        override fun onPathDegraded(generation: Long, detail: String) {
            NativeLog.w(TAG, "path degraded gen=$generation $detail")
        }

        override fun onPathDead(generation: Long, detail: String) {
            NativeLog.e(TAG, "path dead gen=$generation $detail")
            DiagnosticRing.event("error", "vpn.path", "phase=dead gen=$generation $detail")
            recoverDeadTunnel("path_dead $detail")
        }

        override fun suppressEstablishError(): Boolean = coreRecovering

        override fun onUnderlyingChangedWhileUp(generation: Long, iface: String?) {
            NativeLog.i(TAG, "underlying changed gen=$generation iface=$iface")
        }

        override fun proveCandidateSocks(
            username: String,
            protocol: String,
            params: Map<String, Any?>,
            alive: () -> Boolean,
        ): Boolean = proveAutoCandidate(username, protocol, params, alive)

        override fun persistAutoWinner(candidate: AutoCandidate) {
            val json = candidate.paramsJson.ifBlank {
                JSONObject(candidate.params.filterValues { it != null }).toString()
            }
            persistSession(candidate.username, candidate.protocol, json)
        }

        override fun markPersistedInactive() {
            markSessionInactive()
        }

        override fun lastStartFailure(): String? = VpnStatusBroadcaster.lastError()
    }

    /**
     * Текущий статус сервиса для [VpnStatusBroadcaster].
     * Возможные значения: idle / preparing / connecting / connected /
     * disconnecting / revoked / error.
     */
    @Volatile
    var currentStatus: String = "idle"
        private set

    /** TUN established — Home must not treat this as idle even if [currentStatus] lagged. */
    fun hasLiveTun(): Boolean = isRunning || tunInterface.get() != null

    /** Auto SOCKS prove must not [stopSelf] on a single candidate fail. */
    @Volatile
    private var autoProving = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        VpnStatusBroadcaster.attachAppContext(applicationContext)
        ShadeNotification.ensureChannels(this)
        DefaultNetworkMonitor.prewarm(this)
        // Do NOT broadcast "idle" here when Always-on is about to restore —
        // Flutter syncFromNative would paint Disconnected while the tunnel is up.
        if (prefs().getBoolean(KEY_ACTIVE, false)) {
            currentStatus = "preparing"
            VpnStatusBroadcaster.emit(currentStatus)
        } else {
            currentStatus = "idle"
            VpnStatusBroadcaster.emit(currentStatus)
        }
        NativeLog.i(TAG, "onCreate: VpnService создан status=$currentStatus")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val username = intent.getStringExtra(EXTRA_USERNAME) ?: "anonymous"
                val protocol = intent.getStringExtra(EXTRA_PROTOCOL) ?: "unknown"
                val paramsJson = intent.getStringExtra(EXTRA_PARAMS_JSON) ?: "{}"
                val appInitiated = intent.getBooleanExtra(EXTRA_APP_INITIATED, true)
                NativeLog.event("info", "vpn.service.start", "proto=$protocol user_set=${username != "anonymous"}")
                // Persist before establish so Always-on / sticky restart after reboot
                // can rebuild the tunnel without Flutter reinjecting params.
                persistSession(username, protocol, paramsJson, appInitiated)
                val params = runCatching { jsonToMap(JSONObject(paramsJson)) }
                    .onFailure { NativeLog.w(TAG, "failed to parse paramsJson, using defaults", it) }
                    .getOrDefault(emptyMap())
                sessionEngine.enqueueStart(username, protocol, params)
            }
            ACTION_START_AUTO -> {
                val raw = intent.getStringExtra(EXTRA_AUTO_CANDIDATES) ?: "[]"
                val candidates = parseAutoCandidates(raw)
                NativeLog.i(TAG, "onStartCommand: ACTION_START_AUTO n=${candidates.size}")
                // Whole Auto walk — hop teardownCores must not emit idle.
                autoProving = true
                sessionEngine.enqueueAutoStart(candidates)
            }
            ACTION_STOP -> {
                NativeLog.i(TAG, "onStartCommand: ACTION_STOP")
                NativeLog.sessionId = null
                autoProving = false
                coreRecovering = false
                cancelDeadRecoverRetry()
                // Keep params_json so Quick Settings can reconnect without Flutter.
                markSessionInactive()
                sessionEngine.enqueueStop(markInactive = true)
            }
            else -> {
                // Always-on VPN / START_STICKY restart: intent is often null.
                NativeLog.w(TAG, "onStartCommand: restore path action=${intent?.action}")
                restoreSessionIfNeeded()
            }
        }
        return START_STICKY
    }

    private fun prefs() = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

    private fun persistSession(
        username: String,
        protocol: String,
        paramsJson: String,
        appInitiated: Boolean = true,
    ) {
        prefs().edit()
            .putBoolean(KEY_ACTIVE, true)
            .putBoolean(KEY_APP_INITIATED, appInitiated)
            .putString(KEY_USERNAME, username)
            .putString(KEY_PROTOCOL, protocol)
            .putString(KEY_PARAMS_JSON, paramsJson)
            .apply()
        NativeLog.i(TAG, "persistSession: saved (${paramsJson.length} chars) appInitiated=$appInitiated")
    }

    /** Intentional disconnect — keep last config for QS tile reconnect. */
    private fun markSessionInactive() {
        prefs().edit().putBoolean(KEY_ACTIVE, false).apply()
        NativeLog.i(TAG, "markSessionInactive: active=false (params retained)")
    }

    /** Wipe params (corrupt session / no usable JSON). */
    private fun clearSession() {
        prefs().edit().clear().apply()
        NativeLog.i(TAG, "clearSession: wiped stored VPN params")
    }

    /**
     * After reboot / process death Always-on restarts VpnService without ACTION_START.
     * Rebuild tunnel from the last successful session if the user left VPN "active".
     *
     * Important: [onCreate] may set [currentStatus] to `preparing` as a UI hint when
     * KEY_ACTIVE is set. That must NOT block restore — otherwise we stick in
     * preparing forever and Flutter shows endless «Подключение…».
     */
    private fun restoreSessionIfNeeded() {
        if (isRunning) {
            NativeLog.i(TAG, "restoreSessionIfNeeded: already running")
            return
        }
        val store = prefs()
        if (!store.getBoolean(KEY_ACTIVE, false)) {
            NativeLog.i(TAG, "restoreSessionIfNeeded: no active session")
            if (currentStatus == "preparing") {
                currentStatus = "idle"
                VpnStatusBroadcaster.emit(currentStatus)
            }
            return
        }
        val paramsJson = store.getString(KEY_PARAMS_JSON, null)
        if (paramsJson.isNullOrBlank()) {
            NativeLog.w(TAG, "restoreSessionIfNeeded: active flag without params — clearing")
            clearSession()
            currentStatus = "idle"
            VpnStatusBroadcaster.emit(currentStatus)
            return
        }
        val username = store.getString(KEY_USERNAME, "anonymous") ?: "anonymous"
        val protocol = store.getString(KEY_PROTOCOL, "unknown") ?: "unknown"
        NativeLog.event("warn", "vpn.service.restore", "proto=$protocol was=$currentStatus")
        store.edit().putBoolean(KEY_APP_INITIATED, false).apply()
        val params = runCatching { jsonToMap(JSONObject(paramsJson)) }
            .onFailure { NativeLog.w(TAG, "restoreSessionIfNeeded: bad JSON", it) }
            .getOrDefault(emptyMap())
        if (params.isEmpty()) {
            clearSession()
            currentStatus = "idle"
            VpnStatusBroadcaster.emit(currentStatus)
            return
        }
        sessionEngine.enqueueStart(username, protocol, params)
    }

    /**
     * Hy2 QUIC died (screen off / Doze / Wi‑Fi sleep) while TUN is still up.
     * Restart the core from persisted params without going idle — Dart
     * auto-reconnect never sees this as a disconnect.
     */
    private fun recoverDeadTunnel(reason: String) {
        val now = SystemClock.elapsedRealtime()
        val elapsed = if (lastDeadRecoverAt == 0L) Long.MAX_VALUE else now - lastDeadRecoverAt
        val allowed = DeadTunnelReconnect.shouldAttempt(
            sessionActive = prefs().getBoolean(KEY_ACTIVE, false),
            userStopping = currentStatus == "disconnecting" || currentStatus == "idle",
            recoverInFlight = coreRecovering,
            attempts = deadRecoverAttempts,
            elapsedSinceLastMs = elapsed,
        )
        if (!allowed) {
            NativeLog.w(
                TAG,
                "recoverDeadTunnel skip reason=$reason attempts=$deadRecoverAttempts " +
                    "recovering=$coreRecovering status=$currentStatus",
            )
            return
        }
        beginDeadRecover(reason)
    }

    private fun beginDeadRecover(reason: String) {
        coreRecovering = true
        deadRecoverAttempts += 1
        lastDeadRecoverAt = SystemClock.elapsedRealtime()
        cancelDeadRecoverRetry()
        stopPathHealthWatch()
        NativeLog.i(
            TAG,
            "beginDeadRecover reason=$reason attempt=$deadRecoverAttempts/" +
                "${DeadTunnelReconnect.MAX_ATTEMPTS}",
        )
        DiagnosticRing.event(
            "warn",
            "vpn.recover",
            "attempt=$deadRecoverAttempts reason=$reason",
        )
        if (!enqueuePersistedStart(reason)) {
            coreRecovering = false
            NativeLog.w(TAG, "beginDeadRecover: no persisted session")
        }
    }

    private fun enqueuePersistedStart(reason: String): Boolean {
        val store = prefs()
        if (!store.getBoolean(KEY_ACTIVE, false)) return false
        val paramsJson = store.getString(KEY_PARAMS_JSON, null)
        if (paramsJson.isNullOrBlank()) return false
        val username = store.getString(KEY_USERNAME, "anonymous") ?: "anonymous"
        val protocol = store.getString(KEY_PROTOCOL, "unknown") ?: "unknown"
        val params = runCatching { jsonToMap(JSONObject(paramsJson)) }
            .onFailure { NativeLog.w(TAG, "enqueuePersistedStart: bad JSON", it) }
            .getOrDefault(emptyMap())
        if (params.isEmpty()) return false
        NativeLog.event("warn", "vpn.service.persisted_start", "reason=$reason proto=$protocol")
        sessionEngine.enqueueStart(username, protocol, params)
        return true
    }

    private fun scheduleDeadRecoverRetry(message: String) {
        if (!prefs().getBoolean(KEY_ACTIVE, false) || currentStatus == "disconnecting") {
            coreRecovering = false
            return
        }
        if (deadRecoverAttempts >= DeadTunnelReconnect.MAX_ATTEMPTS) {
            coreRecovering = false
            VpnStatusBroadcaster.setError(message)
            currentStatus = "error"
            VpnStatusBroadcaster.emit(currentStatus)
            NativeLog.e(TAG, "dead recover exhausted: $message")
            return
        }
        val delay = DeadTunnelReconnect.backoffMs(deadRecoverAttempts)
        NativeLog.i(TAG, "dead recover retry in ${delay}ms attempt=$deadRecoverAttempts")
        val retry = Runnable {
            coreRecovering = false
            beginDeadRecover("retry $message")
        }
        deadRecoverRetry = retry
        mainHandler.postDelayed(retry, delay)
    }

    private fun cancelDeadRecoverRetry() {
        deadRecoverRetry?.let { mainHandler.removeCallbacks(it) }
        deadRecoverRetry = null
    }

    /**
     * Prefer runtime-true / readable Secure; unknown Secure (S+ @hide) must not
     * abort Connect — treat as false so [applyBypassRoutes] can still try
     * excludeRoute (runtime-true already returned above when lockdown is on).
     */
    private fun isAlwaysOnVpnLockdownSetting(): Boolean =
        queryAlwaysOnVpnLockdown(this, this) == true

    /**
     * Keep VLESS egress + control-plane API off the TUN so Dio/API survives a
     * half-dead tunnel. Lockdown ("Block connections without VPN") forbids
     * bypass — then we can only rely on [VpnService.protect].
     */
    private fun applyBypassRoutes(
        builder: Builder,
        outboundServer: String,
        params: Map<String, Any?>,
    ) {
        if (isAlwaysOnVpnLockdownSetting()) {
            NativeLog.event("info", "vpn.bypass", "applied=false reason=always_on_lockdown")
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            NativeLog.event("info", "vpn.bypass", "applied=false reason=api_lt_33")
            return
        }
        val hosts = linkedSetOf<String>()
        if (outboundServer.isNotEmpty() && outboundServer != "unknown") {
            hosts.add(outboundServer)
        }
        @Suppress("UNCHECKED_CAST")
        val controlPlane = params["controlPlaneHosts"] as? List<*>
        controlPlane?.forEach { host ->
            if (host is String && host.isNotBlank()) {
                hosts.add(host.trim())
            }
        }
        @Suppress("UNCHECKED_CAST")
        val egress = params["egressHosts"] as? List<*>
        egress?.forEach { host ->
            if (host is String && host.isNotBlank()) {
                hosts.add(host.trim())
            }
        }
        // One line per host was the noisiest thing in a connect report: the same
        // three hosts on every reconnect, each one unable to explain anything.
        // The summary keeps the count and the failures; per-host detail is debug.
        var excluded = 0
        var skippedIpv6 = 0
        var failed = 0
        for (host in hosts) {
            try {
                val inet = InetAddress.getByName(host)
                // Only IPv4 /32 bypass — IPv6 literals need separate handling.
                if (inet.hostAddress?.contains(':') == true) {
                    skippedIpv6 += 1
                    NativeLog.d(TAG, "  skip excludeRoute IPv6 host=$host")
                    continue
                }
                builder.excludeRoute(IpPrefix(inet, 32))
                excluded += 1
                NativeLog.d(TAG, "  excludeRoute: $host/32")
            } catch (e: Exception) {
                failed += 1
                NativeLog.w(TAG, "excludeRoute failed host=$host", e)
            }
        }
        if (excluded == 0 && failed == 0 && skippedIpv6 == 0) {
            NativeLog.event("info", "vpn.bypass", "applied=false reason=no_hosts")
        } else {
            NativeLog.event(
                if (failed > 0) "warn" else "debug",
                "vpn.bypass",
                "excluded=$excluded skipped_ipv6=$skippedIpv6 failed=$failed",
            )
        }
    }

    /** Custom / Основные domain suffixes for hy2bind direct (Issue #143). */
    private fun directDomainSuffixesOf(params: Map<String, Any?>): List<String> {
        val raw = params["directDomainSuffixes"] as? List<*> ?: return emptyList()
        return raw.mapNotNull { (it as? String)?.trim()?.lowercase() }
            .filter { it.isNotEmpty() }
            .distinct()
    }

    /** Self + user «Что работает без VPN?» apps stay off the TUN. */
    private fun applyDisallowedApplications(
        builder: Builder,
        params: Map<String, Any?>,
    ) {
        runCatching { builder.addDisallowedApplication(packageName) }
            .onFailure { NativeLog.w(TAG, "addDisallowedApplication(self) failed", it) }
        @Suppress("UNCHECKED_CAST")
        val apps = params["disallowedApplications"] as? List<*> ?: return
        for (raw in apps) {
            val pkg = (raw as? String)?.trim().orEmpty()
            if (pkg.isEmpty() || pkg == packageName) continue
            runCatching { builder.addDisallowedApplication(pkg) }
                .onFailure {
                    NativeLog.w(TAG, "addDisallowedApplication($pkg) failed", it)
                }
        }
    }

    /**
     * User-facing notification subtitle: region/node label, optional protocol.
     * Never Marzban username (`u_3`) or `UNKNOWN`.
     */
    private fun buildNotificationSessionLine(
        params: Map<String, Any?>,
        protocolExtra: String,
    ): String {
        val label = listOf(
            params["displayLabel"] as? String,
            params["sessionName"] as? String,
        ).firstOrNull { !it.isNullOrBlank() } ?: "Прокси Дом"

        val fromParams = (params["outboundType"] as? String)?.trim().orEmpty()
        val proto = when {
            fromParams.isNotEmpty() -> fromParams
            else -> protocolExtra.trim()
        }.lowercase()

        return if (proto.isEmpty() || proto == "unknown") {
            label
        } else {
            "$label · ${proto.uppercase()}"
        }
    }

    private fun parseAutoCandidates(raw: String): List<AutoCandidate> {
        val arr = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
        val out = ArrayList<AutoCandidate>(arr.length())
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            val params = jsonToMap(obj)
            val nodeId = (params["autoNodeId"] as? String)?.trim().orEmpty()
                .ifBlank { (params["hysteriaNodeId"] as? String)?.trim().orEmpty() }
                
                .ifBlank { "auto-$i" }
            val host = (params["hysteriaServer"] as? String)?.substringBefore(':').orEmpty()
                .ifBlank { (params["outboundServer"] as? String)?.trim().orEmpty() }
            val label = (params["displayLabel"] as? String)?.trim().orEmpty().ifBlank { nodeId }
            val protocol = (params["outboundType"] as? String)?.trim().orEmpty().ifBlank { "hysteria2" }
            val username = (params["username"] as? String)?.trim().orEmpty().ifBlank { "anonymous" }
            out.add(
                AutoCandidate(
                    nodeId = nodeId,
                    host = host,
                    label = label,
                    username = username,
                    protocol = protocol,
                    params = params,
                    paramsJson = obj.toString(),
                ),
            )
        }
        return out
    }

    /**
     * Data-plane prove without claiming Connected. Xray/Hy2: SOCKS CONNECT.
     * TT: TUN + TCP CONNECT (handshake is not enough).
     */
    private fun proveAutoCandidate(
        username: String,
        protocol: String,
        params: Map<String, Any?>,
        alive: () -> Boolean,
    ): Boolean {
        if (!alive()) return false
        autoProving = true
        return try {
            if (isHysteriaCore(params)) {
                proveHysteriaSocks(params, alive)
            } else {
                false
            }
        } catch (e: Exception) {
            NativeLog.w(TAG, "proveAutoCandidate failed: ${e.message}")
            teardownCores()
            false
        }
    }

    private fun proveHysteriaSocks(
        params: Map<String, Any?>,
        alive: () -> Boolean,
    ): Boolean {
        val server = (params["hysteriaServer"] as? String)?.trim().orEmpty()
        val auth = (params["hysteriaAuth"] as? String)?.trim().orEmpty()
        if (server.isEmpty() || auth.isEmpty()) return false
        val sni = (params["hysteriaSni"] as? String)?.trim().orEmpty()
        val watch = socksWatchFor(params)
        if (watch == null) {
            NativeLog.w(TAG, "proveHysteriaSocks: socks port undefined")
            return false
        }
        val socksListen = hysteriaSocksListen(params)
        DefaultNetworkMonitor.prewarm(this)
        if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(this, 5000)) return false
        ProtectGuard.reset()
        val hy = HysteriaBridge.instance
        hy.bind(this)
        if (!hy.start(
                server = server,
                auth = auth,
                sni = sni,
                socksListen = socksListen,
                directDomainSuffixes = directDomainSuffixesOf(params),
                insecure = params["hysteriaInsecure"] == true,
                obfs = (params["hysteriaObfs"] as? String).orEmpty(),
                obfsPassword = (params["hysteriaObfsPassword"] as? String).orEmpty(),
            )) {
            NativeLog.w(TAG, "proveHysteriaSocks: start failed ${hy.lastErrorMessage}")
            return false
        }
        val health = PathHealth().proveEgress(
            adapter = watch.adapter,
            socksPort = watch.port,
            alive = alive,
            underlyingIface = DefaultNetworkMonitor.defaultNetwork?.toString(),
            candidateLabel = (params["hysteriaNodeId"] as? String) ?: server,
        )
        if (health !is PathHealth.HealthResult.Ok) {
            NativeLog.w(TAG, "proveHysteriaSocks: $health")
            hy.stop()
            return false
        }
        // Leave Hy2 up for establish — SOCKS prove already started the core.
        NativeLog.i(TAG, "proveHysteriaSocks: ok, Hy2 SOCKS kept for TUN")
        return true
    }

    /**
     * Creates TUN and starts Hysteria2 based on paramsJson.
     */
    private fun startVpn(
        username: String,
        protocol: String,
        params: Map<String, Any?>,
        alive: () -> Boolean = { true },
    ) {
        if (!alive()) return
        liveSessionParams = params.toMap()
        if (isRunning || HysteriaBridge.instance.running()) {
            NativeLog.w(TAG, "startVpn: previous hysteria still up — stop before establish")
            teardownCores()
        }
        if (!alive()) return
        if (establishInProgress) {
            NativeLog.w(TAG, "startVpn: establish already in progress")
            failStart("establish already in progress")
            return
        }
        establishInProgress = true

        notificationSessionLine = buildNotificationSessionLine(params, protocol)
        startForeground(
            ShadeNotification.notificationId(),
            ShadeNotification.connecting(this),
        )

        try {
            VpnStatusBroadcaster.clearError()
            currentStatus = "preparing"
            VpnStatusBroadcaster.emit(currentStatus)

            if (!validateRuntimeParams(params)) {
                failStart(
                    "invalid session: need schemaVersion=$SESSION_SCHEMA_VERSION " +
                        "with hysteriaServer/hysteriaAuth (legacy Xray/TT rejected)",
                )
                return
            }

            if (isHysteriaCore(params)) {
                startHysteriaOnWorker(username, protocol, params, alive)
                return
            }
            if (isVlessShareCore(params)) {
                startShareOnWorker(username, params)
                return
            }
            failStart("unsupported vpnCore")
        } catch (e: Exception) {
            NativeLog.e(TAG, "startVpn: failed", e)
            failStart(e.message ?: e.toString())
        }
    }

    private fun validateRuntimeParams(params: Map<String, Any?>): Boolean {
        if ((params["schemaVersion"] as? Number)?.toInt() != SESSION_SCHEMA_VERSION) {
            return false
        }
        if (isHysteriaCore(params)) {
            return !((params["hysteriaServer"] as? String).isNullOrBlank()) &&
                !((params["hysteriaAuth"] as? String).isNullOrBlank())
        }
        if (isVlessShareCore(params)) {
            return !((params["vlessConfig"] as? String).isNullOrBlank())
        }
        return false
    }

    private fun startShareOnWorker(
        username: String,
        params: Map<String, Any?>,
    ) {
        val configJson = CoreLog.enrich(
            this,
            (params["vlessConfig"] as? String)?.trim().orEmpty(),
        )
        if (configJson.isEmpty()) {
            failStart("vless config missing")
            return
        }
        val watch = socksWatchFor(params)
        if (watch == null) {
            failStart("VLESS SOCKS port undefined")
            return
        }
        val sessionName = (params["sessionName"] as? String)
            ?.takeIf { it.isNotBlank() }
            ?: "Прокси Дом"
        val mtu = 1280
        val address = (params["address"] as? String) ?: "10.255.255.1"
        val addressPrefix = (params["addressPrefix"] as? Number)?.toInt() ?: 30
        @Suppress("UNCHECKED_CAST")
        val routes = (params["routes"] as? List<String>) ?: listOf("0.0.0.0/0")
        DefaultNetworkMonitor.prewarm(this)
        if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(this, 5000)) {
            failStart("underlying network not ready")
            return
        }
        val builder = Builder()
            .setSession(sessionName)
            .setMtu(mtu)
            .addAddress(address, addressPrefix)
        for (route in routes) {
            val parts = route.split("/")
            if (parts.size == 2 && !parts[0].contains(":")) {
                runCatching { builder.addRoute(parts[0], parts[1].toInt()) }
            }
        }
        builder.addDnsServer("1.1.1.1")
        builder.addDnsServer("8.8.8.8")
        val server = Regex(""""address"\s*:\s*"([^"]+)"\s*,\s*"port"\s*:\s*(\d+)""")
            .find(configJson)
        val serverHost = server?.groupValues?.getOrNull(1).orEmpty()
        val serverPort = server?.groupValues?.getOrNull(2)?.toIntOrNull() ?: 0
        applyBypassRoutes(builder, serverHost, params)
        applyDisallowedApplications(builder, params)
        currentStatus = "connecting"
        VpnStatusBroadcaster.emit(currentStatus)
        tunInterface.set(builder.establish())
        val activeTun = tunInterface.get()
        if (activeTun == null) {
            failStart("VPN permission denied or establish() returned null")
            return
        }
        VpnUnderlyingNetworkPolicy.applyTo(this)
        val hy = HysteriaBridge.instance
        hy.bind(this)
        if (!hy.startShare(configJson)) {
            failStart(hy.lastErrorMessage ?: "VLESS start failed")
            return
        }
        val tunFd = try {
            ParcelFileDescriptor.dup(activeTun.fileDescriptor).detachFd()
        } catch (t: Throwable) {
            failStart("VLESS tun fd dup failed")
            return
        }
        if (!hy.startShareTun(tunFd = tunFd, mtu = mtu)) {
            failStart(hy.lastErrorMessage ?: "VLESS tun pump failed")
            return
        }
        val kcp = configJson.contains("\"network\":\"kcp\"") ||
            configJson.contains("\"network\": \"kcp\"")
        val reach = if (kcp) "udp" else tcpReach(serverHost, serverPort)
        val tcpLine = "server=$serverHost:$serverPort tcp=$reach"
        lastShareTcp = tcpLine
        DiagnosticRing.event("debug", "vpn.server_tcp", tcpLine)
        val protectErr = Hy2bind.lastProtectError()?.trim().orEmpty()
        if (protectErr.isNotEmpty()) {
            failStart(protectErr)
            return
        }
        if (!acceptCarryingTunnel(
                socksPort = watch.port,
                server = "$serverHost:$serverPort",
                tcpReachLine = reach,
            )
        ) {
            return
        }
        isRunning = true
        establishInProgress = false
        coreRecovering = false
        deadRecoverAttempts = 0
        cancelDeadRecoverRetry()
        currentStatus = "connected"
        VpnStatusBroadcaster.emit(currentStatus)
        showConnectedNotification()
        acquireVpnLocks()
        startPathHealthWatch()
        startTrafficMonitor()
        NativeLog.event("info", "vpn.core.established", "core=vless")
    }

    private fun startHysteriaOnWorker(
        username: String,
        protocol: String,
        params: Map<String, Any?>,
        alive: () -> Boolean = { true },
    ) {
        lastShareTcp = null
        val server = (params["hysteriaServer"] as? String)?.trim().orEmpty()
        val auth = (params["hysteriaAuth"] as? String)?.trim().orEmpty()
        if (server.isEmpty() || auth.isEmpty()) {
            failStart("hysteriaServer/hysteriaAuth missing")
            return
        }
        val sni = (params["hysteriaSni"] as? String)?.trim().orEmpty()
        val watch = socksWatchFor(params)
        if (watch == null) {
            failStart("hysteria socks port undefined")
            return
        }
        val socksListen = hysteriaSocksListen(params)

        val sessionName = (params["sessionName"] as? String)
            ?.takeIf { it.isNotBlank() }
            ?: "Прокси Дом"
        // Hy2 QUIC overhead on LTE: 1500 inner packets fragment and stall
        // the first request of each page. Video then recovers via TCP MSS.
        val mtu = 1280
        val address = (params["address"] as? String) ?: "10.255.255.1"
        val addressPrefix = (params["addressPrefix"] as? Number)?.toInt() ?: 30
        @Suppress("UNCHECKED_CAST")
        val routes = (params["routes"] as? List<String>) ?: listOf("0.0.0.0/0")
        // TUN peer 10.255.255.2 is not a resolver. Hy2 UDP must reach a public
        // DNS (same hijack as hyDialer for leftover RFC1918 :53).
        val dnsServers = listOf("1.1.1.1", "8.8.8.8")

        DefaultNetworkMonitor.prewarm(this)
        if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(this, 5000)) {
            failStart("underlying network not ready")
            return
        }
        ProtectGuard.reset()
        ProtectGuard.onFailure = {
            NativeLog.e(TAG, "Hysteria: protect() failed — stopping VPN")
            Handler(Looper.getMainLooper()).post {
                if (isRunning || establishInProgress) {
                    failStart("VpnService.protect() failed")
                }
            }
        }

        val builder = Builder()
            .setSession(sessionName)
            .setMtu(mtu)
            .addAddress(address, addressPrefix)
        for (route in routes) {
            val parts = route.split("/")
            if (parts.size == 2 && !parts[0].contains(":")) {
                runCatching { builder.addRoute(parts[0], parts[1].toInt()) }
            }
        }
        for (dns in dnsServers) {
            builder.addDnsServer(dns)
        }
        applyBypassRoutes(builder, server.substringBefore(':'), params)
        applyDisallowedApplications(builder, params)

        currentStatus = "connecting"
        VpnStatusBroadcaster.emit(currentStatus)

        tunInterface.set(builder.establish())
        val activeTun = tunInterface.get()
        if (activeTun == null) {
            ProtectGuard.onFailure = null
            failStart("VPN permission denied or establish() returned null")
            return
        }
        VpnUnderlyingNetworkPolicy.applyTo(this)

        if (!alive()) {
            teardownCores()
            return
        }
        val hy = HysteriaBridge.instance
        hy.bind(this)
        if (hy.running()) {
            hy.stop()
        }
        if (!alive()) {
            teardownCores()
            return
        }
        if (!hy.start(
                server = server,
                auth = auth,
                sni = sni,
                socksListen = socksListen,
                directDomainSuffixes = directDomainSuffixesOf(params),
                insecure = params["hysteriaInsecure"] == true,
                obfs = (params["hysteriaObfs"] as? String).orEmpty(),
                obfsPassword = (params["hysteriaObfsPassword"] as? String).orEmpty(),
            )) {
            failStart(hy.lastErrorMessage ?: "Hysteria start failed")
            return
        }
        if (ProtectGuard.hasFailed()) {
            failStart("VpnService.protect() failed during Hysteria start")
            return
        }
        // Pump gVisor inside hy2bind. gVisor unix.Close's this fd — detachFd
        // so ParcelFileDescriptor is not still the fdsan owner (Pixel abort
        // on StopTun / Auto restart).
        val tunFd = try {
            ParcelFileDescriptor.dup(activeTun.fileDescriptor).detachFd()
        } catch (t: Throwable) {
            failStart("Hysteria tun fd dup failed: ${t.message}")
            return
        }
        if (!hy.startTun(tunFd = tunFd, mtu = mtu)) {
            // Go closes the detached dup on failure; establish PFD stays for teardown.
            failStart(hy.lastErrorMessage ?: "Hysteria tun pump failed")
            return
        }
        // Go owns the detached dup; Kotlin keeps the establish PFD until
        // [closeTunOnce] in teardownCores (closing establish early tears down VPN).

        if (!alive()) {
            teardownCores()
            return
        }
        val hyHost = server.substringBefore(':')
        val hyPort = server.substringAfter(':', "").toIntOrNull() ?: 0
        if (!acceptCarryingTunnel(
                socksPort = watch.port,
                server = server,
                tcpReachLine = tcpReach(hyHost, hyPort),
            )
        ) {
            return
        }

        isRunning = true
        establishInProgress = false
        coreRecovering = false
        deadRecoverAttempts = 0
        cancelDeadRecoverRetry()
        currentStatus = "connected"
        VpnStatusBroadcaster.emit(currentStatus)
        showConnectedNotification()
        acquireVpnLocks()
        startPathHealthWatch()
        startTrafficMonitor()
        NativeLog.event("info", "vpn.core.established", "core=hysteria server=$server")
    }

    /**
     * SOCKS CONNECT to 1.1.1.1:443 through local Xray SOCKS — must pass before
     * `connected`. Runs off the main thread (no TLS, no generate_204).
     */
    private fun readCarrierIpv4(): String? = runCatching {
        val url = java.net.URL("http://ipv4.icanhazip.com")
        val conn = url.openConnection() as java.net.HttpURLConnection
        conn.connectTimeout = 4000
        conn.readTimeout = 4000
        conn.inputStream.bufferedReader().use { it.readLine()?.trim() }
    }.getOrNull()

    private fun tcpReach(host: String, port: Int): String {
        if (host.isEmpty() || port <= 0) return "no_target"
        val fd = try {
            Os.socket(OsConstants.AF_INET, OsConstants.SOCK_STREAM, 0)
        } catch (e: ErrnoException) {
            return "socket=${e.message ?: "err"}"
        }
        return try {
            val raw = FileDescriptor::class.java.getDeclaredField("descriptor").let { field ->
                field.isAccessible = true
                field.getInt(fd)
            }
            if (!protect(raw)) return "protect_failed"
            Os.setsockoptTimeval(
                fd,
                OsConstants.SOL_SOCKET,
                OsConstants.SO_SNDTIMEO,
                StructTimeval.fromMillis(3000),
            )
            try {
                Os.connect(fd, InetSocketAddress(InetAddress.getByName(host), port))
                "ok"
            } catch (e: ErrnoException) {
                if (e.errno != OsConstants.EINPROGRESS &&
                    e.message?.contains("EINPROGRESS") != true
                ) {
                    "ErrnoException=${e.message ?: "err"}"
                } else {
                    waitTcpConnected(fd, host, port)
                }
            }
        } catch (e: Exception) {
            "${e.javaClass.simpleName}=${e.message ?: "err"}"
        } finally {
            runCatching { Os.close(fd) }
        }
    }

    private fun waitTcpConnected(fd: FileDescriptor, host: String, port: Int): String {
        val pollFd = StructPollfd()
        pollFd.fd = fd
        pollFd.events = OsConstants.POLLOUT.toShort()
        val ready = try {
            Os.poll(arrayOf(pollFd), 3000)
        } catch (e: ErrnoException) {
            return "poll=${e.message ?: "err"}"
        }
        if (ready == 0) return "ETIMEDOUT"
        return try {
            Os.connect(fd, InetSocketAddress(InetAddress.getByName(host), port))
            "ok"
        } catch (e: ErrnoException) {
            when (e.errno) {
                OsConstants.EISCONN -> "ok"
                OsConstants.EALREADY, OsConstants.EINPROGRESS -> "ETIMEDOUT"
                else -> "errno=${e.errno}"
            }
        }
    }

    /**
     * SOCKS must accept a CONNECT before the session is connected. The exit
     * IP is recorded when a target returns one and is not a reason to stop.
     */
    private fun acceptCarryingTunnel(
        socksPort: Int,
        server: String,
        tcpReachLine: String,
    ): Boolean {
        if (!awaitSocksPort(socksPort)) {
            failStart(
                "socks not listening server=$server port=$socksPort tcp=$tcpReachLine",
            )
            return false
        }
        val acceptance = VpnPingMonitor.proveTunnel(socksPort = socksPort)
        if (!acceptance.carriesData) {
            failStart(
                "tunnel carried no tcp server=$server reason=${acceptance.detail} " +
                    "tcp=$tcpReachLine socks=$socksPort",
            )
            return false
        }
        val carrierIp = if (acceptance.exitIp.isNullOrBlank()) {
            null
        } else {
            readCarrierIpv4()
        }
        val warn = egressIpWarn(acceptance.exitIp, carrierIp)
        if (warn != null) {
            NativeLog.w(
                TAG,
                "$warn server=$server exit=${acceptance.exitIp} carrier=$carrierIp",
            )
        } else {
            NativeLog.i(
                TAG,
                "egress ip read exit=${acceptance.exitIp} target=${acceptance.target} " +
                    "server=$server",
            )
        }
        val legacy = VpnPingMonitor.socksExitIp(socksPort = socksPort, timeoutMs = 1_200)
        NativeLog.i(
            TAG,
            "icanhazip through tunnel exit=${legacy ?: "unread"} (not a gate) server=$server",
        )
        provenEgressIp = acceptance.exitIp
        return true
    }

    private fun awaitSocksPort(socksPort: Int): Boolean {
        val deadline = SystemClock.elapsedRealtime() + XRAY_SOCKS_WARMUP_BUDGET_MS
        while (SystemClock.elapsedRealtime() < deadline) {
            if (VpnPingMonitor.isSocksReachable(
                    port = socksPort,
                    timeoutMs = XRAY_SOCKS_WARMUP_POLL_MS,
                )
            ) {
                return true
            }
            Thread.sleep(50)
        }
        return VpnPingMonitor.isSocksReachable(port = socksPort, timeoutMs = 800)
    }

    private fun failStart(message: String) {
        NativeLog.e(TAG, "failStart: $message")
        establishInProgress = false
        VpnStatusBroadcaster.setError(message)
        DiagnosticRing.event(
            "error",
            "vpn.fail",
            "autoProving=$autoProving recovering=$coreRecovering",
        )
        if (autoProving) {
            NativeLog.w(TAG, "failStart during auto prove (no stopSelf): $message")
            teardownCores()
            return
        }
        if (coreRecovering) {
            NativeLog.w(TAG, "failStart during dead recover (no stopSelf): $message")
            teardownCores()
            scheduleDeadRecoverRetry(message)
            return
        }
        currentStatus = "error"
        VpnStatusBroadcaster.emit(currentStatus)
        markSessionInactive()
        stopVpn()
    }

    /**
     * Close the Kotlin-owned TUN PFD at most once. Safe under concurrent
     * [teardownCores] / failStart (main + session dispatcher).
     */
    private fun closeTunOnce(reason: String) {
        val pfd = tunInterface.getAndSet(null) ?: return
        val fd = try {
            pfd.fd
        } catch (_: Exception) {
            -1
        }
        NativeLog.i(TAG, "closeTunOnce reason=$reason fd=$fd")
        try {
            pfd.close()
        } catch (e: Exception) {
            NativeLog.w(TAG, "closeTunOnce: close failed fd=$fd", e)
        }
    }

    /** Stop cores + TUN without [stopSelf] (engine re-establish). */
    private fun teardownCores() {
        if (!teardownInFlight.compareAndSet(false, true)) {
            NativeLog.w(TAG, "teardownCores: already in flight — skip")
            return
        }
        try {
            stopPathHealthWatch()
            releaseVpnLocks()
            stopTrafficMonitor()
            HysteriaBridge.instance.stop()
            provenEgressIp = null
            closeTunOnce("teardownCores")
            NativeLog.i(TAG, "teardownCores: cores stopped, TUN closed if any")
        } catch (e: Exception) {
            NativeLog.e(TAG, "teardownCores: error", e)
        } finally {
            ProtectGuard.onFailure = null
            isRunning = false
            establishInProgress = false
            teardownInFlight.set(false)
            // TUN is gone — never leave Flutter/getStatus on "connected"
            // after a real stop. Auto hops (Binding/Proving) must keep
            // connecting/probing: idle here paints Nest rest while Hy2 is live.
            if (currentStatus != "revoked" && currentStatus != "disconnecting") {
                val hop = autoProving ||
                    coreRecovering ||
                    sessionEngine.currentSnapshot().phase.suppressTeardownIdleBroadcast()
                if (hop) {
                    VpnStatusBroadcaster.remember(currentStatus)
                } else if (currentStatus != "idle") {
                    currentStatus = "idle"
                    VpnStatusBroadcaster.emit(currentStatus)
                }
            }
        }
    }

    private fun stopVpn() {
        cancelDeadRecoverRetry()
        coreRecovering = false
        val shouldAnnounce = isRunning ||
            establishInProgress ||
            currentStatus == "connecting" ||
            currentStatus == "preparing" ||
            currentStatus == "error"
        try {
            if (shouldAnnounce && currentStatus != "revoked") {
                currentStatus = "disconnecting"
                VpnStatusBroadcaster.emit(currentStatus)
            }
            teardownCores()
        } catch (e: Exception) {
            NativeLog.e(TAG, "stopVpn: error", e)
        } finally {
            if (currentStatus != "revoked") {
                currentStatus = "idle"
                VpnStatusBroadcaster.emit(currentStatus)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        }
    }

    private fun showConnectedNotification(
        downText: String = "",
        upText: String = "",
    ) {
        val notification = ShadeNotification.connected(
            context = this,
            sessionLine = notificationSessionLine,
            downText = downText,
            upText = upText,
        )
        startForeground(ShadeNotification.notificationId(), notification)
    }

    /** Settings toggled shade visibility — refresh the single FGS card. */
    fun onNotificationStyleChanged() {
        if (currentStatus != "connected" && currentStatus != "connecting" &&
            currentStatus != "preparing"
        ) {
            return
        }
        if (currentStatus == "connected") {
            startTrafficMonitor()
            val showSpeeds = ShadeNotification.isVisible(this)
            showConnectedNotification(
                downText = if (showSpeeds) VpnTrafficBroadcaster.lastDownText else "",
                upText = if (showSpeeds) VpnTrafficBroadcaster.lastUpText else "",
            )
        } else {
            startForeground(
                ShadeNotification.notificationId(),
                ShadeNotification.connecting(this),
            )
        }
    }

    private fun startTrafficMonitor() {
        stopTrafficMonitor()
        trafficMonitor = VpnTrafficMonitor(
            context = this,
            onSpeeds = { downBps, upBps, downText, upText ->
                VpnTrafficBroadcaster.emit(downBps, upBps, downText, upText)
                if (currentStatus == "connected" && ShadeNotification.isVisible(this)) {
                    showConnectedNotification(downText = downText, upText = upText)
                }
            },
        ).also { it.start() }
        // Home ping stays off: SOCKS CONNECT every 5s shared the Hy2 path with
        // tabs. PathHealth continuous (below) is the liveness probe instead.
    }

    private fun startPathHealthWatch() {
        pathHealth.stopContinuous()
        if (!isRunning) return
        val watch = socksWatchFor(liveSessionParams)
        if (watch == null) {
            NativeLog.e(
                TAG,
                "path health watch refused: socks port undefined " +
                    "vpnCore=${liveSessionParams["vpnCore"]}",
            )
            return
        }
        pathHealth.startContinuous(
            adapter = watch.adapter,
            socksPort = watch.port,
            listener = { result -> sessionEngine.notifyHealth(result) },
            alive = {
                isRunning &&
                    prefs().getBoolean(KEY_ACTIVE, false) &&
                    currentStatus != "disconnecting" &&
                    currentStatus != "idle"
            },
        )
        NativeLog.i(
            TAG,
            "path health watch started adapter=${watch.adapter} socks=${watch.port}",
        )
    }

    private fun stopPathHealthWatch() {
        pathHealth.stopContinuous()
    }

    private fun acquireVpnLocks() {
        acquireVpnWakeLock()
        acquireVpnWifiLock()
    }

    private fun releaseVpnLocks() {
        releaseVpnWakeLock()
        releaseVpnWifiLock()
    }

    private fun acquireVpnWakeLock() {
        if (vpnWakeLock?.isHeld == true) return
        val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return
        runCatching {
            vpnWakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$packageName:vpn",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
            NativeLog.i(TAG, "vpn wake lock acquired")
        }.onFailure {
            NativeLog.w(TAG, "vpn wake lock failed", it)
            vpnWakeLock = null
        }
    }

    private fun releaseVpnWakeLock() {
        runCatching {
            if (vpnWakeLock?.isHeld == true) vpnWakeLock?.release()
        }
        vpnWakeLock = null
    }

    /**
     * Keep STA radio up after screen off. CPU wake lock does not stop Wi‑Fi sleep;
     * Hy2 QUIC dies and VpnService still reports connected.
     */
    private fun acquireVpnWifiLock() {
        if (vpnWifiLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(WIFI_SERVICE) as? WifiManager ?: return
        runCatching {
            @Suppress("DEPRECATION")
            vpnWifiLock = wifi.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "$packageName:vpn-wifi",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
            NativeLog.i(TAG, "vpn wifi lock acquired")
        }.onFailure {
            NativeLog.w(TAG, "vpn wifi lock skipped", it)
            vpnWifiLock = null
        }
    }

    private fun releaseVpnWifiLock() {
        runCatching {
            if (vpnWifiLock?.isHeld == true) vpnWifiLock?.release()
        }
        vpnWifiLock = null
    }

    private fun stopTrafficMonitor() {
        stopPingMonitor()
        trafficMonitor?.stop()
        trafficMonitor = null
        VpnTrafficBroadcaster.clear()
    }

    private fun stopPingMonitor() {
        VpnPingBroadcaster.clear()
    }

    override fun onRevoke() {
        NativeLog.w(TAG, "onRevoke: VPN отозван системой или пользователем")
        currentStatus = "revoked"
        VpnStatusBroadcaster.emit(currentStatus)
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        NativeLog.i(TAG, "onDestroy: VpnService уничтожен")
        if (instance === this) instance = null
        stopVpn()
        super.onDestroy()
    }
}

/**
 * Регистрация MethodChannel и EventChannel в MainActivity.
 * Вызывается из MainActivity.configureFlutterEngine().
 */
object VpnChannelRegistry {
    const val METHOD_CHANNEL = "proxydom/vpn"
    const val EVENT_CHANNEL = "proxydom/vpn/status"
    const val SESSION_EVENT_CHANNEL = "proxydom/vpn/session"
    const val TRAFFIC_EVENT_CHANNEL = "proxydom/vpn/traffic"
    const val PING_EVENT_CHANNEL = "proxydom/vpn/ping"

    /** Launcher apps for «Что работает без VPN?» → Приложения (no QUERY_ALL_PACKAGES). */
    private fun listLauncherApps(
        context: android.content.Context,
        includeIcons: Boolean,
    ): List<Map<String, Any?>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolves = pm.queryIntentActivities(intent, 0)
        val self = context.packageName
        val out = ArrayList<Map<String, Any?>>(resolves.size)
        val seen = HashSet<String>()
        for (ri in resolves) {
            val pkg = ri.activityInfo?.packageName?.trim().orEmpty()
            if (pkg.isEmpty() || pkg == self || !seen.add(pkg)) continue
            val label = try {
                ri.loadLabel(pm)?.toString()?.trim().orEmpty()
            } catch (_: Exception) {
                pkg
            }
            val row = HashMap<String, Any?>(3)
            row["packageName"] = pkg
            row["label"] = label.ifBlank { pkg }
            if (includeIcons) {
                val png = runCatching {
                    val drawable = ri.loadIcon(pm) ?: return@runCatching null
                    drawableToPngBytes(drawable, maxSide = 96)
                }.getOrNull()
                if (png != null) {
                    row["iconPng"] = png
                }
            }
            out.add(row)
        }
        out.sortBy { (it["label"] as? String)?.lowercase() ?: "" }
        return out
    }

    private fun drawableToPngBytes(
        drawable: android.graphics.drawable.Drawable,
        maxSide: Int,
    ): ByteArray? {
        val w = drawable.intrinsicWidth.coerceAtLeast(1)
        val h = drawable.intrinsicHeight.coerceAtLeast(1)
        val scale = maxSide.toFloat() / maxOf(w, h).toFloat()
        val tw = (w * scale).toInt().coerceAtLeast(1).coerceAtMost(maxSide)
        val th = (h * scale).toInt().coerceAtLeast(1).coerceAtMost(maxSide)
        val bitmap = android.graphics.Bitmap.createBitmap(
            tw,
            th,
            android.graphics.Bitmap.Config.ARGB_8888,
        )
        val canvas = android.graphics.Canvas(bitmap)
        drawable.setBounds(0, 0, tw, th)
        drawable.draw(canvas)
        val stream = java.io.ByteArrayOutputStream()
        if (!bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, stream)) {
            bitmap.recycle()
            return null
        }
        bitmap.recycle()
        return stream.toByteArray()
    }

    fun register(
        engine: FlutterEngine,
        appContext: android.content.Context,
        activityProvider: () -> android.app.Activity?,
        serviceProvider: () -> ProxyDomVpnService?,
        onPermissionRequest: (MethodChannel.Result) -> Unit,
        onNotificationPermissionRequest: (MethodChannel.Result) -> Unit = {},
        onInternetPermissionRequest: (MethodChannel.Result) -> Unit = {},
    ) {
        // MethodChannel — команды от Flutter
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAuto" -> {
                        NativeLog.sessionId = call.argument<String>("sessionId")
                        val rows = call.argument<List<*>>("candidatesJson")
                            ?: emptyList<Any?>()
                        val arr = JSONArray()
                        for (row in rows) {
                            val text = row as? String ?: continue
                            runCatching { arr.put(JSONObject(text)) }
                        }
                        val intent = Intent(
                            appContext,
                            ProxyDomVpnService::class.java,
                        ).apply {
                            action = ProxyDomVpnService.ACTION_START_AUTO
                            putExtra(
                                ProxyDomVpnService.EXTRA_AUTO_CANDIDATES,
                                arr.toString(),
                            )
                        }
                        appContext.startService(intent)
                        result.success(true)
                    }
                    "start" -> {
                        NativeLog.sessionId = call.argument<String>("sessionId")
                        // paramsJson — JSON-строка с flat keys (см. VpnServiceConfig)
                        val paramsJson = call.argument<String>("paramsJson") ?: "{}"
                        val json = try {
                            JSONObject(paramsJson)
                        } catch (e: Exception) {
                            JSONObject()
                        }
                        // username — только для логов; UI берёт displayLabel / sessionName
                        val username = call.argument<String>("username")
                            ?: json.optString("username", "").ifBlank { "anonymous" }
                        val protocol = call.argument<String>("protocol")
                            ?: json.optString("outboundType", "").ifBlank { "hysteria2" }

                        val intent = Intent(
                            appContext,
                            ProxyDomVpnService::class.java,
                        ).apply {
                            action = ProxyDomVpnService.ACTION_START
                            putExtra(ProxyDomVpnService.EXTRA_USERNAME, username)
                            putExtra(ProxyDomVpnService.EXTRA_PROTOCOL, protocol)
                            putExtra(ProxyDomVpnService.EXTRA_PARAMS_JSON, paramsJson)
                            putExtra(ProxyDomVpnService.EXTRA_APP_INITIATED, true)
                        }
                        appContext.startService(intent)
                        result.success(true)
                    }
                    "stop" -> {
                        NativeLog.sessionId = null
                        val intent = Intent(
                            appContext,
                            ProxyDomVpnService::class.java,
                        ).apply {
                            action = ProxyDomVpnService.ACTION_STOP
                        }
                        appContext.startService(intent)
                        result.success(true)
                    }
                    "wipeSession" -> {
                        ProxyDomVpnService.stopVpnService(appContext)
                        ProxyDomVpnService.wipePersistedSession(appContext)
                        result.success(true)
                    }
                    "getStatus" -> {
                        result.success(ProxyDomVpnService.resolveUiStatus(appContext))
                    }
                    "hasActiveSession" -> {
                        result.success(ProxyDomVpnService.hasActiveSession(appContext))
                    }
                    "getLastError" -> {
                        result.success(VpnStatusBroadcaster.lastError())
                    }
                    "getShareTcp" -> {
                        result.success(serviceProvider()?.lastShareTcp)
                    }
                    "getProvenEgress" -> {
                        result.success(serviceProvider()?.provenEgressIp)
                    }
                    "isLockdownEnabled" -> {
                        // Preference/system lockdown — not tunnel-up. See
                        // [ProxyDomVpnService.queryAlwaysOnVpnSnapshot].
                        // Map → Dart; null lockdown → unavailable.
                        runCatching {
                            ProxyDomVpnService.queryAlwaysOnVpnSnapshot(
                                appContext,
                                serviceProvider() ?: ProxyDomVpnService.currentInstance(),
                            )
                        }.fold(
                            onSuccess = { result.success(it) },
                            onFailure = { e ->
                                NativeLog.w(
                                    ProxyDomVpnService.TAG,
                                    "isLockdownEnabled query failed",
                                    e,
                                )
                                result.success(null)
                            },
                        )
                    }
                    "getVpnConflict" -> {
                        runCatching {
                            ProxyDomVpnService.queryVpnConflict(appContext)
                        }.fold(
                            onSuccess = { result.success(it) },
                            onFailure = { e ->
                                NativeLog.w(
                                    ProxyDomVpnService.TAG,
                                    "getVpnConflict failed",
                                    e,
                                )
                                result.success(
                                    mapOf(
                                        "foreignAlwaysOn" to false,
                                        "packageName" to null,
                                        "appLabel" to null,
                                        "lockdown" to null,
                                    ),
                                )
                            },
                        )
                    }
                    "openVpnSettings" -> {
                        // Prefer Activity context; fall back to app + NEW_TASK.
                        // Do not treat resolveActivity==null as hard fail before
                        // start — API 30+ package visibility can hide Settings
                        // unless <queries> declares VPN_SETTINGS (see manifest).
                        try {
                            val activity = activityProvider()
                            val intent = Intent(Settings.ACTION_VPN_SETTINGS)
                            if (activity == null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            val pm = (activity ?: appContext).packageManager
                            val resolved = intent.resolveActivity(pm)
                            NativeLog.i(
                                ProxyDomVpnService.TAG,
                                "openVpnSettings resolve=$resolved activity=${activity != null}",
                            )
                            if (activity != null) {
                                activity.startActivity(intent)
                            } else {
                                appContext.startActivity(intent)
                            }
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            NativeLog.w(ProxyDomVpnService.TAG, "openVpnSettings: no activity", e)
                            result.error("VPN_SETTINGS_UNAVAILABLE", e.message, null)
                        } catch (e: Exception) {
                            NativeLog.w(ProxyDomVpnService.TAG, "openVpnSettings failed", e)
                            result.error("VPN_SETTINGS_FAILED", e.message, null)
                        }
                    }
                    "requestBatteryExemption" -> {
                        try {
                            val activity = activityProvider()
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            ).apply {
                                data = android.net.Uri.parse(
                                    "package:${appContext.packageName}",
                                )
                            }
                            if (activity == null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            (activity ?: appContext).startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            NativeLog.w(ProxyDomVpnService.TAG, "battery exemption failed", e)
                            result.success(false)
                        }
                    }
                    "getSingBoxStderrTail" -> {
                        val maxLines = call.argument<Int>("maxLines") ?: 400
                        result.success(
                            ProxyDomVpnService.readSingBoxStderrTail(appContext, maxLines),
                        )
                    }
                    "setCoreLogLevel" -> {
                        CoreLog.override = call.argument<String>("level")
                        // Same gate for the native ring — the user picked one level,
                        // and «Журнал» must honour it for Go *and* for Kotlin lines.
                        NativeLog.level = CoreLog.resolve(appContext)
                        result.success(true)
                    }
                    "clearCoreLog" -> {
                        CoreLog.clear(appContext)
                        DiagnosticRing.clear()
                        result.success(true)
                    }
                    "getUnderlyingNetworkInterface" -> {
                        result.success(DefaultNetworkMonitor.currentInterfaceName ?: "(unknown)")
                    }
                    "requestPermission" -> {
                        onPermissionRequest(result)
                    }
                    "requestNotificationPermission" -> {
                        onNotificationPermissionRequest(result)
                    }
                    "ensureInternetPermission" -> {
                        onInternetPermissionRequest(result)
                    }
                    "bindToUnderlyingNetwork" -> {
                        Thread({
                            val ok = VpnUnderlyingNetworkPolicy.bindProcess(appContext)
                            Handler(Looper.getMainLooper()).post {
                                result.success(ok)
                            }
                        }, "bind-underlying").start()
                    }
                    "isShadeNotificationEnabled" -> {
                        result.success(ShadeNotification.isVisible(appContext))
                    }
                    "setShadeNotificationEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        ShadeNotification.setVisible(appContext, enabled)
                        val svc = serviceProvider() ?: ProxyDomVpnService.currentInstance()
                        svc?.onNotificationStyleChanged()
                        result.success(true)
                    }
                    "requestAddQsTile" -> {
                        val host = activityProvider() ?: appContext
                        QsTilePrompter.requestAdd(host, result)
                    }
                    "isQsTileAdded" -> {
                        result.success(QsTilePresence.isAdded(appContext))
                    }
                    "listLauncherApps" -> {
                        val includeIcons = call.argument<Boolean>("includeIcons") ?: true
                        result.success(listLauncherApps(appContext, includeIcons))
                    }
                    "getDeviceLabel" -> {
                        result.success(DeviceLabel.raw(appContext))
                    }
                    else -> result.notImplemented()
                }
            }

        // EventChannel — статус-апдейты к Flutter
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    VpnStatusBroadcaster.register(events)
                }

                override fun onCancel(arguments: Any?) {
                    VpnStatusBroadcaster.unregister()
                }
            })

        EventChannel(engine.dartExecutor.binaryMessenger, SESSION_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    SessionSnapshotBroadcaster.register(events)
                }

                override fun onCancel(arguments: Any?) {
                    SessionSnapshotBroadcaster.unregister()
                }
            })

        // EventChannel — live ↓/↑ bytes/s for Home stats (independent of shade prefs)
        EventChannel(engine.dartExecutor.binaryMessenger, TRAFFIC_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    VpnTrafficBroadcaster.register(events)
                }

                override fun onCancel(arguments: Any?) {
                    VpnTrafficBroadcaster.unregister()
                }
            })

        // EventChannel — path latency (ms) for Home ping (stub without libbox)
        EventChannel(engine.dartExecutor.binaryMessenger, PING_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    VpnPingBroadcaster.register(events)
                }

                override fun onCancel(arguments: Any?) {
                    VpnPingBroadcaster.unregister()
                }
            })
    }
}

/**
 * Peer DNS address inside the TUN /30 (or similar) for Android Builder.addDnsServer.
 */
internal fun tunDnsPeerAddress(address: String, prefixLength: Int): String {
    val octets = address.split(".").mapNotNull { it.toIntOrNull() }
    if (octets.size != 4) return "172.19.0.2"

    val ip = (octets[0] shl 24) or (octets[1] shl 16) or (octets[2] shl 8) or octets[3]
    val mask = if (prefixLength == 0) 0 else (-1 shl (32 - prefixLength))
    val network = ip and mask
    val broadcast = network or mask.inv()
    val host1 = network + 1
    val host2 = broadcast - 1
    val peer = when (ip) {
        host1 -> host2
        host2 -> host1
        else -> host2
    }
    return "${(peer shr 24) and 0xff}.${(peer shr 16) and 0xff}.${(peer shr 8) and 0xff}.${peer and 0xff}"
}

/**
 * Конвертация org.json.JSONObject → Map<String, Any?> (рекурсивно для вложенных
 * объектов и массивов). Используется для парсинга paramsJson в [ProxyDomVpnService].
 */
internal fun jsonToMap(json: JSONObject): Map<String, Any?> {
    val map = mutableMapOf<String, Any?>()
    for (key in json.keys()) {
        val value = json.get(key)
        map[key] = when (value) {
            is JSONObject -> jsonToMap(value)
            is JSONArray -> jsonArrayToList(value)
            JSONObject.NULL -> null
            else -> value
        }
    }
    return map
}

internal fun jsonArrayToList(arr: JSONArray): List<Any?> {
    return (0 until arr.length()).map { i ->
        val value = arr.get(i)
        when (value) {
            is JSONObject -> jsonToMap(value)
            is JSONArray -> jsonArrayToList(value)
            JSONObject.NULL -> null
            else -> value
        }
    }
}

/**
 * Broadcaster — шлёт статус-апдейты из сервиса в EventChannel.
 *
 * EventChannel.EventSink.success() нужно дёргать с main thread —
 * поэтому [emit] всегда постит на main looper через Handler.
 */
object VpnStatusBroadcaster {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    /** Последний статус — для getStatus() когда VpnService не bound к Activity. */
    @Volatile
    private var lastStatus: String = "idle"

    private var lastErrorMessage: String? = null

    @Volatile
    private var appContext: android.content.Context? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun attachAppContext(context: android.content.Context) {
        appContext = context.applicationContext
    }

    fun currentStatus(): String = lastStatus

    fun lastError(): String? = lastErrorMessage

    fun setError(message: String) {
        lastErrorMessage = message
    }

    fun clearError() {
        lastErrorMessage = null
    }

    fun register(sink: EventChannel.EventSink) {
        this.sink = sink
        val replay = lastStatus
        mainHandler.post {
            try {
                sink.success(replay)
            } catch (e: Exception) {
                NativeLog.w(ProxyDomVpnService.TAG, "VpnStatusBroadcaster.replay failed: ${e.message}")
            }
        }
    }

    fun unregister() {
        sink = null
    }

    /** Update lastStatus without EventChannel (hop teardown during Auto). */
    fun remember(status: String) {
        lastStatus = status
        appContext?.let { ProxyDomTileService.requestListening(it) }
    }

    fun emit(status: String) {
        lastStatus = status
        appContext?.let { ProxyDomTileService.requestListening(it) }
        mainHandler.post {
            val current = sink
            if (current != null) {
                try {
                    current.success(status)
                } catch (e: Exception) {
                    NativeLog.w(ProxyDomVpnService.TAG, "VpnStatusBroadcaster.emit failed: ${e.message}")
                }
            }
        }
    }
}

/**
 * Broadcasts downlink/uplink rates to Flutter EventChannel `proxydom/vpn/traffic`.
 */
object VpnTrafficBroadcaster {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    @Volatile
    var lastDownlinkBps: Long = 0
        private set

    @Volatile
    var lastUplinkBps: Long = 0
        private set

    @Volatile
    var lastDownText: String = ""
        private set

    @Volatile
    var lastUpText: String = ""
        private set

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(sink: EventChannel.EventSink) {
        this.sink = sink
        val payload = mapOf(
            "downlinkBps" to lastDownlinkBps,
            "uplinkBps" to lastUplinkBps,
        )
        mainHandler.post {
            try {
                sink.success(payload)
            } catch (e: Exception) {
                NativeLog.w(ProxyDomVpnService.TAG, "VpnTrafficBroadcaster.replay failed: ${e.message}")
            }
        }
    }

    fun unregister() {
        sink = null
    }

    fun clear() {
        lastDownlinkBps = 0
        lastUplinkBps = 0
        lastDownText = ""
        lastUpText = ""
        emit(0, 0, "", "")
    }

    fun emit(downlinkBps: Long, uplinkBps: Long, downText: String, upText: String) {
        lastDownlinkBps = downlinkBps
        lastUplinkBps = uplinkBps
        lastDownText = downText
        lastUpText = upText
        val payload = mapOf(
            "downlinkBps" to downlinkBps,
            "uplinkBps" to uplinkBps,
        )
        mainHandler.post {
            val current = sink
            if (current != null) {
                try {
                    current.success(payload)
                } catch (e: Exception) {
                    NativeLog.w(ProxyDomVpnService.TAG, "VpnTrafficBroadcaster.emit failed: ${e.message}")
                }
            }
        }
    }
}

/**
 * Broadcasts path latency (ms) to Flutter EventChannel `proxydom/vpn/ping`.
 *
 * [emit] with null clears the last sample so Home shows `— ms` instead of a
 * stale RTT after the data-plane dies.
 */
object VpnPingBroadcaster {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    @Volatile
    var lastDelayMs: Int? = null
        private set

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(sink: EventChannel.EventSink) {
        this.sink = sink
        val replay = lastDelayMs
        mainHandler.post {
            try {
                // Always push current state (including null) so listeners do not
                // keep a previous AsyncData from an older session.
                sink.success(mapOf("delayMs" to replay))
            } catch (e: Exception) {
                NativeLog.w(ProxyDomVpnService.TAG, "VpnPingBroadcaster.replay failed: ${e.message}")
            }
        }
    }

    fun unregister() {
        sink = null
    }

    fun clear() {
        lastDelayMs = null
        mainHandler.post {
            val current = sink
            if (current != null) {
                try {
                    current.success(mapOf("delayMs" to null))
                } catch (e: Exception) {
                    NativeLog.w(ProxyDomVpnService.TAG, "VpnPingBroadcaster.clear emit failed: ${e.message}")
                }
            }
        }
    }

    fun emit(delayMs: Int?) {
        lastDelayMs = delayMs
        val payload = mapOf("delayMs" to delayMs)
        mainHandler.post {
            val current = sink
            if (current != null) {
                try {
                    current.success(payload)
                } catch (e: Exception) {
                    NativeLog.w(ProxyDomVpnService.TAG, "VpnPingBroadcaster.emit failed: ${e.message}")
                }
            }
        }
    }
}