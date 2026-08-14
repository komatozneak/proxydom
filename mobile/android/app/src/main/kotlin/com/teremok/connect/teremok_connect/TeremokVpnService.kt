package com.teremok.connect.teremok_connect

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.Settings
import android.system.OsConstants
import android.util.Log
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import com.adguard.trusttunnel.VpnClient
import com.adguard.trusttunnel.VpnState
import com.adguard.trusttunnel.VpnServiceConfig as TtVpnServiceConfig
import com.teremok.connect.teremok_connect.session.AutoCandidate
import com.teremok.connect.teremok_connect.session.PathHealth
import com.teremok.connect.teremok_connect.session.SessionPhase
import com.teremok.connect.teremok_connect.session.SessionSnapshot
import com.teremok.connect.teremok_connect.session.SessionSnapshotBroadcaster
import com.teremok.connect.teremok_connect.session.VpnSessionEngine
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Android VpnService with triple-core runtime (ADR 005 / 006 / 015):
 * - Xray: VpnService TUN → libXray setTunFd (gVisor) → VLESS
 * - TrustTunnel: VpnService TUN → TrustTunnelBridge / VpnClient
 * - Hysteria2: VpnService TUN → libXray tun2socks → Hy2 SOCKS (prove on :10808)
 */
class TeremokVpnService : VpnService() {

    companion object {
        const val TAG = "TeremokVpn"
        const val ACTION_START = "com.teremok.connect.START_VPN"
        const val ACTION_START_AUTO = "com.teremok.connect.START_VPN_AUTO"
        const val ACTION_STOP = "com.teremok.connect.STOP_VPN"
        const val EXTRA_AUTO_CANDIDATES = "autoCandidatesJson"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_PROTOCOL = "protocol"
        const val EXTRA_PARAMS_JSON = "paramsJson"
        const val EXTRA_APP_INITIATED = "appInitiated"

        /** Session payload schema from Flutter VpnServiceConfig / VpnController. */
        const val SESSION_SCHEMA_VERSION = 2

        /** paramsJson["vpnCore"] values — triple-core switch (ADR 015). */
        const val VPN_CORE_XRAY = "xray"
        const val VPN_CORE_TRUSTTUNNEL = "trusttunnel"
        const val VPN_CORE_HYSTERIA = "hysteria"

        /** TT native CONNECTED wait budget. */
        private const val TT_CONNECT_TIMEOUT_MS = 20_000L

        const val PREFS_NAME = "teremok_vpn_session"
        private const val KEY_PARAMS_JSON = "params_json"
        private const val KEY_USERNAME = "username"
        private const val KEY_PROTOCOL = "protocol"
        private const val KEY_ACTIVE = "active"
        private const val KEY_APP_INITIATED = "app_initiated"

        @Volatile
        private var instance: TeremokVpnService? = null

        fun currentInstance(): TeremokVpnService? = instance

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
            service: TeremokVpnService? = currentInstance(),
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
            service: TeremokVpnService? = currentInstance(),
        ): Map<String, Any?> {
            var fromRuntime: Boolean? = null
            var alwaysOnRuntime: Boolean? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val svc = service ?: currentInstance()
                if (svc != null) {
                    fromRuntime = runCatching { svc.isLockdownEnabled }
                        .onFailure { Log.w(TAG, "VpnService.isLockdownEnabled failed", it) }
                        .getOrNull()
                    alwaysOnRuntime = runCatching { svc.isAlwaysOn }
                        .onFailure { Log.w(TAG, "VpnService.isAlwaysOn failed", it) }
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

            Log.i(
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
         * Detect Always-on held by **another** VPN app (blocks Teremok Connect).
         *
         * Keys: foreignAlwaysOn (Boolean), packageName (String?),
         * appLabel (String?), lockdown (Boolean?).
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
            // Android 12+ often blocks Settings.Secure.always_on_vpn_app for
            // non-system apps (Pixel: "is not readable") while still exposing
            // always_on_vpn_lockdown=1. Treat lockdown-without-our-Always-on as
            // a foreign block so gate UX is not «check your connection».
            val foreign = when {
                alwaysOnPkg != null -> alwaysOnPkg != context.packageName
                lockdown == true && !oursAlwaysOn -> true
                else -> false
            }
            val label = if (foreign && alwaysOnPkg != null) {
                resolveAppLabel(context, alwaysOnPkg)
            } else {
                null
            }
            Log.i(
                TAG,
                "vpnConflict foreign=$foreign pkg=$alwaysOnPkg label=$label " +
                    "lockdown=$lockdown oursAlwaysOn=$oursAlwaysOn",
            )
            return mapOf(
                "foreignAlwaysOn" to foreign,
                "packageName" to if (foreign) alwaysOnPkg else null,
                "appLabel" to label,
                "lockdown" to lockdown,
            )
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
                Log.w(TAG, "Settings.Secure.$key not readable: ${e.message}")
                null
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "Settings.Secure.$key invalid: ${e.message}")
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
                Log.w(TAG, "Settings.Secure.$key not readable: ${e.message}")
                null
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "Settings.Secure.$key invalid: ${e.message}")
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
            val file = java.io.File(context.filesDir, "xray/stderr.log")
            val fileTail = if (!file.exists()) {
                ""
            } else {
                runCatching {
                    val lines = file.readLines()
                    if (lines.isEmpty()) "" else lines.takeLast(maxLines).joinToString("\n")
                }.getOrDefault("")
            }
            return listOf(ring, fileTail).filter { it.isNotBlank() }.joinToString("\n")
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

        fun allowUserDisconnect(context: android.content.Context): Boolean {
            val snap = queryAlwaysOnVpnSnapshot(context)
            return VpnShadePolicy.allowUserDisconnect(
                alwaysOn = snap["alwaysOn"] as? Boolean,
                lockdown = snap["lockdown"] as? Boolean,
                sdkInt = Build.VERSION.SDK_INT,
                appInitiated = isAppInitiatedSession(context),
            )
        }

        fun tileStateFor(status: String, lockdown: Boolean?): Int =
            VpnShadePolicy.tileState(status, lockdown)

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
                Log.w(TAG, "startFromPersistedSession: no usable params")
                return false
            }
            val username = store.getString(KEY_USERNAME, "anonymous") ?: "anonymous"
            val protocol = store.getString(KEY_PROTOCOL, "unknown") ?: "unknown"
            val intent = Intent(context, TeremokVpnService::class.java).apply {
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
                Log.w(TAG, "startFromPersistedSession: start failed", e)
                false
            }
        }

        fun stopVpnService(context: android.content.Context) {
            val intent = Intent(context, TeremokVpnService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    private var tunInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    /** True only while [startVpn] is establishing TUN/core (not onCreate hint). */
    @Volatile
    private var establishInProgress = false
    private var trafficMonitor: VpnTrafficMonitor? = null
    private var notificationSessionLine: String = "Теремок VPN"

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
            if (snapshot.phase == SessionPhase.ConnectedHealthy ||
                snapshot.phase == SessionPhase.ConnectedDegraded ||
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
            startVpn(username, protocol, params)
            return isRunning
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
            Log.w(TAG, "path degraded gen=$generation $detail")
        }

        override fun onPathDead(generation: Long, detail: String) {
            Log.e(TAG, "path dead gen=$generation $detail")
            DiagnosticRing.append(TAG, "path dead gen=$generation $detail")
        }

        override fun onUnderlyingChangedWhileUp(generation: Long, iface: String?) {
            Log.i(TAG, "underlying changed gen=$generation iface=$iface")
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
    fun hasLiveTun(): Boolean = isRunning || tunInterface != null

    /** Auto SOCKS prove must not [stopSelf] on a single candidate fail. */
    @Volatile
    private var autoProving = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        VpnStatusBroadcaster.attachAppContext(applicationContext)
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
        Log.i(TAG, "onCreate: VpnService создан status=$currentStatus")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val username = intent.getStringExtra(EXTRA_USERNAME) ?: "anonymous"
                val protocol = intent.getStringExtra(EXTRA_PROTOCOL) ?: "unknown"
                val paramsJson = intent.getStringExtra(EXTRA_PARAMS_JSON) ?: "{}"
                val appInitiated = intent.getBooleanExtra(EXTRA_APP_INITIATED, true)
                Log.i(TAG, "onStartCommand: ACTION_START (user=$username, proto=$protocol)")
                // Persist before establish so Always-on / sticky restart after reboot
                // can rebuild the tunnel without Flutter reinjecting params.
                persistSession(username, protocol, paramsJson, appInitiated)
                val params = runCatching { jsonToMap(JSONObject(paramsJson)) }
                    .onFailure { Log.w(TAG, "failed to parse paramsJson, using defaults", it) }
                    .getOrDefault(emptyMap())
                sessionEngine.enqueueStart(username, protocol, params)
            }
            ACTION_START_AUTO -> {
                val raw = intent.getStringExtra(EXTRA_AUTO_CANDIDATES) ?: "[]"
                val candidates = parseAutoCandidates(raw)
                Log.i(TAG, "onStartCommand: ACTION_START_AUTO n=${candidates.size}")
                // Whole Auto walk — hop teardownCores must not emit idle.
                autoProving = true
                sessionEngine.enqueueAutoStart(candidates)
            }
            ACTION_STOP -> {
                Log.i(TAG, "onStartCommand: ACTION_STOP")
                autoProving = false
                // Keep params_json so Quick Settings can reconnect without Flutter.
                markSessionInactive()
                sessionEngine.enqueueStop(markInactive = true)
            }
            else -> {
                // Always-on VPN / START_STICKY restart: intent is often null.
                Log.w(TAG, "onStartCommand: restore path action=${intent?.action}")
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
        Log.i(TAG, "persistSession: saved (${paramsJson.length} chars) appInitiated=$appInitiated")
    }

    /** Intentional disconnect — keep last config for QS tile reconnect. */
    private fun markSessionInactive() {
        prefs().edit().putBoolean(KEY_ACTIVE, false).apply()
        Log.i(TAG, "markSessionInactive: active=false (params retained)")
    }

    /** Wipe params (corrupt session / no usable JSON). */
    private fun clearSession() {
        prefs().edit().clear().apply()
        Log.i(TAG, "clearSession: wiped stored VPN params")
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
            Log.i(TAG, "restoreSessionIfNeeded: already running")
            return
        }
        val store = prefs()
        if (!store.getBoolean(KEY_ACTIVE, false)) {
            Log.i(TAG, "restoreSessionIfNeeded: no active session")
            if (currentStatus == "preparing") {
                currentStatus = "idle"
                VpnStatusBroadcaster.emit(currentStatus)
            }
            return
        }
        val paramsJson = store.getString(KEY_PARAMS_JSON, null)
        if (paramsJson.isNullOrBlank()) {
            Log.w(TAG, "restoreSessionIfNeeded: active flag without params — clearing")
            clearSession()
            currentStatus = "idle"
            VpnStatusBroadcaster.emit(currentStatus)
            return
        }
        val username = store.getString(KEY_USERNAME, "anonymous") ?: "anonymous"
        val protocol = store.getString(KEY_PROTOCOL, "unknown") ?: "unknown"
        Log.i(TAG, "restoreSessionIfNeeded: restarting (user=$username, proto=$protocol, was=$currentStatus)")
        store.edit().putBoolean(KEY_APP_INITIATED, false).apply()
        val params = runCatching { jsonToMap(JSONObject(paramsJson)) }
            .onFailure { Log.w(TAG, "restoreSessionIfNeeded: bad JSON", it) }
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
            Log.i(TAG, "  skip excludeRoute: always_on_vpn_lockdown=1")
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            Log.i(TAG, "  skip excludeRoute: API < 33")
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
        for (host in hosts) {
            try {
                val inet = InetAddress.getByName(host)
                // Only IPv4 /32 bypass — IPv6 literals need separate handling.
                if (inet.hostAddress?.contains(':') == true) {
                    Log.w(TAG, "  skip excludeRoute IPv6 host=$host")
                    continue
                }
                builder.excludeRoute(IpPrefix(inet, 32))
                Log.i(TAG, "  excludeRoute: $host/32")
            } catch (e: Exception) {
                Log.w(TAG, "  excludeRoute failed for $host", e)
            }
        }
    }

    /** Self + user «Что работает без VPN?» apps stay off the TUN. */
    private fun applyDisallowedApplications(
        builder: Builder,
        params: Map<String, Any?>,
    ) {
        runCatching { builder.addDisallowedApplication(packageName) }
            .onFailure { Log.w(TAG, "addDisallowedApplication(self) failed", it) }
        @Suppress("UNCHECKED_CAST")
        val apps = params["disallowedApplications"] as? List<*> ?: return
        for (raw in apps) {
            val pkg = (raw as? String)?.trim().orEmpty()
            if (pkg.isEmpty() || pkg == packageName) continue
            runCatching { builder.addDisallowedApplication(pkg) }
                .onFailure {
                    Log.w(TAG, "addDisallowedApplication($pkg) failed", it)
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
        ).firstOrNull { !it.isNullOrBlank() } ?: "Теремок VPN"

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
                .ifBlank { (params["trusttunnelNodeId"] as? String)?.trim().orEmpty() }
                .ifBlank { "auto-$i" }
            val host = (params["trusttunnelHost"] as? String)?.trim().orEmpty()
                .ifBlank { (params["hysteriaServer"] as? String)?.substringBefore(':').orEmpty() }
                .ifBlank { (params["outboundServer"] as? String)?.trim().orEmpty() }
            val label = (params["displayLabel"] as? String)?.trim().orEmpty().ifBlank { nodeId }
            val protocol = (params["outboundType"] as? String)?.trim().orEmpty().ifBlank { "vless" }
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
            if (isTrustTunnelCore(params)) {
                startTrustTunnelOnWorker(username, protocol, params)
                if (!isRunning) return false
                val health = PathHealth().proveEgress(
                    adapter = PathHealth.CoreAdapter.TrustTunnel,
                    alive = alive,
                    underlyingIface = DefaultNetworkMonitor.defaultNetwork?.toString(),
                    candidateLabel = (params["trusttunnelNodeId"] as? String) ?: "tt",
                )
                val ok = health is PathHealth.HealthResult.Ok
                if (!ok) teardownCores()
                ok
            } else if (isHysteriaCore(params)) {
                proveHysteriaSocks(params, alive)
            } else {
                proveXraySocks(params, alive)
            }
        } catch (e: Exception) {
            Log.w(TAG, "proveAutoCandidate failed: ${e.message}")
            teardownCores()
            false
        }
    }

    private fun proveXraySocks(
        params: Map<String, Any?>,
        alive: () -> Boolean,
    ): Boolean {
        val candidates = runtimeCandidates(params)
        val selected = candidates.firstOrNull() ?: return false
        DefaultNetworkMonitor.prewarm(this)
        if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(this, 5000)) return false
        val bridge = XrayBridge.instance
        bridge.bind(this)
        if (!bridge.loadLibrary()) return false
        if (!bridge.start(selected.configJson, tunFd = 0)) {
            bridge.stop()
            return false
        }
        val health = PathHealth().proveEgress(
            adapter = PathHealth.CoreAdapter.XraySocks,
            alive = alive,
            underlyingIface = DefaultNetworkMonitor.defaultNetwork?.toString(),
            candidateLabel = selected.id,
        )
        bridge.stop()
        return health is PathHealth.HealthResult.Ok
    }

    private fun proveHysteriaSocks(
        params: Map<String, Any?>,
        alive: () -> Boolean,
    ): Boolean {
        val server = (params["hysteriaServer"] as? String)?.trim().orEmpty()
        val auth = (params["hysteriaAuth"] as? String)?.trim().orEmpty()
        if (server.isEmpty() || auth.isEmpty()) return false
        val sni = (params["hysteriaSni"] as? String)?.trim().orEmpty()
        val socksListen = (params["hysteriaSocksListen"] as? String)?.trim()
            .orEmpty()
            .ifBlank { "${GvisorTun2Socks.SOCKS_HOST}:${GvisorTun2Socks.SOCKS_PORT}" }
        DefaultNetworkMonitor.prewarm(this)
        if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(this, 5000)) return false
        ProtectGuard.reset()
        val hy = HysteriaBridge.instance
        hy.bind(this)
        if (!hy.start(server = server, auth = auth, sni = sni, socksListen = socksListen)) {
            Log.w(TAG, "proveHysteriaSocks: start failed ${hy.lastErrorMessage}")
            return false
        }
        val health = PathHealth().proveEgress(
            adapter = PathHealth.CoreAdapter.HysteriaSocks,
            alive = alive,
            underlyingIface = DefaultNetworkMonitor.defaultNetwork?.toString(),
            candidateLabel = (params["hysteriaNodeId"] as? String) ?: server,
        )
        if (health !is PathHealth.HealthResult.Ok) {
            Log.w(TAG, "proveHysteriaSocks: $health")
            hy.stop()
            return false
        }
        // Leave Hy2 up for establish. Stop+Start after libXray.touch deadlocks
        // the second gomobile runtime (Pixel: Hy2bind.start never returns).
        Log.i(TAG, "proveHysteriaSocks: ok, Hy2 SOCKS kept for TUN")
        return true
    }

    /**
     * Creates TUN and starts Xray (gVisor) or TrustTunnel based on paramsJson.
     */
    private fun startVpn(
        username: String,
        protocol: String,
        params: Map<String, Any?>,
    ) {
        if (isRunning) {
            Log.w(TAG, "startVpn: already running — teardown+reapply new params")
            teardownCores()
        }
        if (establishInProgress) {
            Log.w(TAG, "startVpn: establish already in progress, skip")
            return
        }
        establishInProgress = true

        notificationSessionLine = buildNotificationSessionLine(params, protocol)
        startForeground(
            VpnNotificationHelper.notificationId(),
            VpnNotificationHelper.startConnecting(this),
        )

        try {
            VpnStatusBroadcaster.clearError()
            currentStatus = "preparing"
            VpnStatusBroadcaster.emit(currentStatus)

            if (!validateRuntimeParams(params)) {
                failStart(
                    "invalid session: need schemaVersion=$SESSION_SCHEMA_VERSION " +
                        "with xrayCandidateConfigs, trusttunnelToml, or hysteriaServer " +
                        "(legacy singBoxConfigJson rejected)",
                )
                return
            }

            if (isTrustTunnelCore(params)) {
                startTrustTunnelOnWorker(username, protocol, params)
                return
            }
            if (isHysteriaCore(params)) {
                startHysteriaOnWorker(username, protocol, params)
                return
            }

            startXrayOnWorker(username, protocol, params)
        } catch (e: Exception) {
            Log.e(TAG, "startVpn: failed", e)
            failStart(e.message ?: e.toString())
        }
    }

    private fun validateRuntimeParams(params: Map<String, Any?>): Boolean {
        if ((params["schemaVersion"] as? Number)?.toInt() != SESSION_SCHEMA_VERSION) {
            return false
        }
        if (isTrustTunnelCore(params)) {
            return !((params["trusttunnelToml"] as? String).isNullOrBlank())
        }
        if (isHysteriaCore(params)) {
            return !((params["hysteriaServer"] as? String).isNullOrBlank()) &&
                !((params["hysteriaAuth"] as? String).isNullOrBlank())
        }
        return runtimeCandidates(params).isNotEmpty()
    }

    private fun startXrayOnWorker(
        username: String,
        protocol: String,
        params: Map<String, Any?>,
    ) {
        val candidates = runtimeCandidates(params)
        val autoSelect = (params["autoSelect"] as? Boolean) == true
        val ordered = candidateProbeOrder(candidates, autoSelect = autoSelect)
        val selected = ordered.firstOrNull()
        if (selected == null) {
            failStart("xrayCandidateConfigs empty after probe order")
            return
        }

        val sessionName = (params["sessionName"] as? String)
            ?.takeIf { it.isNotBlank() }
            ?: "Теремок VPN"
        val mtu = (params["mtu"] as? Number)?.toInt() ?: 1500
        val address = (params["address"] as? String) ?: "10.255.255.1"
        val addressPrefix = (params["addressPrefix"] as? Number)?.toInt() ?: 30
        @Suppress("UNCHECKED_CAST")
        val routes = (params["routes"] as? List<String>) ?: listOf("0.0.0.0/0")
        @Suppress("UNCHECKED_CAST")
        val dnsServers = (params["dnsServers"] as? List<String>)
            ?: listOf(tunDnsPeerAddress(address, addressPrefix))
        val outboundServer = (params["outboundServer"] as? String)
            ?.takeIf { it.isNotBlank() }
            ?: selected.host

        Log.i(TAG, "startVpn: Xray $sessionName candidate=${selected.id}@${selected.host}")
        Log.i(TAG, "  tunnel: $address/$addressPrefix routes=$routes dns=$dnsServers")

        val builder = Builder()
            .setSession(sessionName)
            .setMtu(mtu)
            .addAddress(address, addressPrefix)

        for (route in routes) {
            val parts = route.split("/")
            if (parts.size == 2) {
                if (parts[0].contains(":")) {
                    Log.w(TAG, "  skip IPv6 route '$route' (no inet6 on TUN)")
                    continue
                }
                try {
                    builder.addRoute(parts[0], parts[1].toInt())
                    Log.i(TAG, "  added route: $route")
                } catch (_: Exception) {
                    Log.w(TAG, "  invalid route '$route', skipping")
                }
            } else {
                Log.w(TAG, "  invalid route '$route', skipping")
            }
        }

        for (dns in dnsServers) {
            builder.addDnsServer(dns)
        }

        applyBypassRoutes(builder, outboundServer, params)
        applyDisallowedApplications(builder, params)

        currentStatus = "connecting"
        VpnStatusBroadcaster.emit(currentStatus)

        DefaultNetworkMonitor.prewarm(this)
        if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(this, 5000)) {
            failStart("underlying network not ready")
            return
        }
        ProtectGuard.reset()
        ProtectGuard.onFailure = {
            Log.e(TAG, "startVpn: protect() failed — stopping VPN")
            Handler(Looper.getMainLooper()).post {
                if (isRunning || establishInProgress) {
                    failStart("VpnService.protect() failed")
                }
            }
        }

        tunInterface = builder.establish()
        val activeTun = tunInterface
        if (activeTun == null) {
            ProtectGuard.onFailure = null
            failStart("VPN permission denied or establish() returned null")
            return
        }

        VpnUnderlyingNetworkPolicy.applyTo(this)

        val bridge = XrayBridge.instance
        bridge.bind(this)
        if (!bridge.loadLibrary()) {
            failStart("Xray init failed")
            return
        }

        Log.i(
            TAG,
            "candidate ${selected.id}@${selected.host}: starting Xray+gVisor tunFd=${activeTun.fd}",
        )
        if (!bridge.start(selected.configJson, tunFd = activeTun.fd)) {
            val detail = bridge.lastErrorMessage ?: "Xray start failed"
            failStart("${selected.id}@${selected.host}: $detail")
            return
        }
        if (ProtectGuard.hasFailed()) {
            failStart("VpnService.protect() failed during Xray start")
            return
        }

        // SOCKS CONNECT :443 through proxy. HTTP generate_204 hangs on VPS.
        if (!probeSocksHttps(selected)) {
            failStart(
                "${selected.id}@${selected.host}: SOCKS HTTPS probe failed",
            )
            return
        }

        isRunning = true
        establishInProgress = false
        currentStatus = "connected"
        VpnStatusBroadcaster.emit(currentStatus)
        showConnectedNotification()
        startTrafficMonitor()
        Log.i(
            TAG,
            "startVpn: TUN+gVisor+Xray established candidate=" +
                "${selected.id}@${selected.host} user=$username protocol=$protocol",
        )
    }

    /**
     * TrustTunnel core (ADR 006): native VpnClient owns the tunnel fd after start.
     */
    private fun startTrustTunnelOnWorker(
        username: String,
        protocol: String,
        params: Map<String, Any?>,
    ) {
        val toml = (params["trusttunnelToml"] as? String)?.trim().orEmpty()
        if (toml.isEmpty()) {
            failStart("trusttunnelToml missing")
            return
        }
        val ttHost = (params["trusttunnelHost"] as? String)?.trim().orEmpty()
        val ttConfig = runCatching { TtVpnServiceConfig.parseToml(toml) }.getOrNull()

        DefaultNetworkMonitor.prewarm(this)
        if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(this, 5000)) {
            failStart("underlying network not ready")
            return
        }
        ProtectGuard.reset()
        ProtectGuard.onFailure = {
            Log.e(TAG, "TrustTunnel: protect() failed — stopping VPN")
            Handler(Looper.getMainLooper()).post {
                if (isRunning || establishInProgress) {
                    failStart("VpnService.protect() failed")
                }
            }
        }

        val sessionName = (params["sessionName"] as? String)
            ?.takeIf { it.isNotBlank() }
            ?: "Теремок VPN"
        val mtu = ttConfig?.listener?.tun?.mtuSize?.toInt()?.takeIf { it > 0 } ?: 1500
        val builder = Builder()
            .setSession(sessionName)
            .setMtu(mtu)
            .addAddress(TrustTunnelBridge.TUN_ADDRESS, TrustTunnelBridge.TUN_ADDRESS_PREFIX)
        builder.allowFamily(OsConstants.AF_INET)
        applyDisallowedApplications(builder, params)

        val hasDnsUpstreams = ttConfig?.endpoint?.dnsUpstreams?.isNotEmpty() == true ||
            toml.contains("dns_upstreams")
        if (hasDnsUpstreams) {
            builder.addDnsServer(TrustTunnelBridge.FAKE_DNS_SERVER)
        } else {
            builder.addDnsServer("1.1.1.1")
            builder.addDnsServer("8.8.8.8")
        }

        val included = ttConfig?.listener?.tun?.includedRoutes
            ?.takeIf { it.isNotEmpty() }
            ?: listOf("0.0.0.0/0")
        val excluded = (ttConfig?.listener?.tun?.excludedRoutes ?: emptyList()) +
            listOf("0.0.0.0/8", "224.0.0.0/3")
        val routes = try {
            VpnClient.excludeCidr(included, excluded)
        } catch (e: Exception) {
            Log.w(TAG, "excludeCidr failed, using full default route", e)
            listOf("0.0.0.0/0")
        } ?: listOf("0.0.0.0/0")

        for (route in routes) {
            val parts = route.split("/")
            if (parts.size == 2 && !parts[0].contains(":")) {
                try {
                    builder.addRoute(parts[0], parts[1].toInt())
                } catch (_: Exception) {
                    Log.w(TAG, "  invalid TT route '$route', skipping")
                }
            }
        }

        currentStatus = "connecting"
        VpnStatusBroadcaster.emit(currentStatus)

        val tun = builder.establish()
        if (tun == null) {
            ProtectGuard.onFailure = null
            failStart("VPN permission denied or establish() returned null")
            return
        }
        tunInterface = tun
        VpnUnderlyingNetworkPolicy.applyTo(this)

        val bridge = TrustTunnelBridge.instance
        bridge.bind(this)
        val connectedLatch = CountDownLatch(1)
        val droppedBeforeConnect = AtomicBoolean(false)
        val host = object : TrustTunnelBridge.Host {
            override fun onTrustTunnelState(state: VpnState) {
                when (state) {
                    VpnState.CONNECTED -> connectedLatch.countDown()
                    VpnState.DISCONNECTED -> {
                        if (connectedLatch.count > 0L) {
                            droppedBeforeConnect.set(true)
                            connectedLatch.countDown()
                        } else if (isRunning) {
                            Log.e(TAG, "TrustTunnel dropped post-connect — stopping")
                            Handler(Looper.getMainLooper()).post {
                                markSessionInactive()
                                stopVpn()
                            }
                        }
                    }
                    else -> Unit
                }
            }
        }

        if (!bridge.start(toml, tun, host)) {
            val detail = bridge.lastErrorMessage ?: "TrustTunnel start failed"
            failStart(detail)
            return
        }
        // VpnClient.start takes ownership of the TUN fd.
        tunInterface = null

        if (ProtectGuard.hasFailed()) {
            failStart("VpnService.protect() failed during TrustTunnel start")
            return
        }

        val connected = try {
            connectedLatch.await(TT_CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            false
        }
        if (!connected || droppedBeforeConnect.get()) {
            failStart(
                if (droppedBeforeConnect.get()) {
                    "TrustTunnel handshake dropped (auth/endpoint unreachable)"
                } else {
                    "TrustTunnel CONNECTED timeout (${TT_CONNECT_TIMEOUT_MS}ms)"
                },
            )
            return
        }

        isRunning = true
        establishInProgress = false
        currentStatus = "connected"
        VpnStatusBroadcaster.emit(currentStatus)
        showConnectedNotification()
        startTrafficMonitor()
        Log.i(
            TAG,
            "startVpn: TrustTunnel established host=$ttHost user=$username protocol=$protocol",
        )
    }

    /**
     * Hysteria2 (ADR 015): official client SOCKS + libXray tun pump + SOCKS prove.
     * Soft-pass on QUIC-up is forbidden — same SOCKS CONNECT gate as Xray.
     */
    private fun startHysteriaOnWorker(
        username: String,
        protocol: String,
        params: Map<String, Any?>,
    ) {
        val server = (params["hysteriaServer"] as? String)?.trim().orEmpty()
        val auth = (params["hysteriaAuth"] as? String)?.trim().orEmpty()
        if (server.isEmpty() || auth.isEmpty()) {
            failStart("hysteriaServer/hysteriaAuth missing")
            return
        }
        val sni = (params["hysteriaSni"] as? String)?.trim().orEmpty()
        val socksListen = (params["hysteriaSocksListen"] as? String)?.trim()
            .orEmpty()
            .ifBlank { "${GvisorTun2Socks.SOCKS_HOST}:${GvisorTun2Socks.SOCKS_PORT}" }
        val nodeId = (params["hysteriaNodeId"] as? String)?.trim().orEmpty()
            .ifBlank { "eu-hy2-1" }

        val sessionName = (params["sessionName"] as? String)
            ?.takeIf { it.isNotBlank() }
            ?: "Теремок VPN"
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
            Log.e(TAG, "Hysteria: protect() failed — stopping VPN")
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

        tunInterface = builder.establish()
        val activeTun = tunInterface
        if (activeTun == null) {
            ProtectGuard.onFailure = null
            failStart("VPN permission denied or establish() returned null")
            return
        }
        VpnUnderlyingNetworkPolicy.applyTo(this)

        val hy = HysteriaBridge.instance
        hy.bind(this)
        if (!hy.start(server = server, auth = auth, sni = sni, socksListen = socksListen)) {
            failStart(hy.lastErrorMessage ?: "Hysteria start failed")
            return
        }
        if (ProtectGuard.hasFailed()) {
            failStart("VpnService.protect() failed during Hysteria start")
            return
        }
        // libXray as TUN pump deadlocks while hyjni is loaded (two gomobile
        // Go runtimes). Pump gVisor inside hy2bind instead.
        // gVisor unix.Close's this fd. detachFd so ParcelFileDescriptor is
        // not still the fdsan owner (Pixel abort on StopTun / Auto restart).
        val tunFd = try {
            ParcelFileDescriptor.dup(activeTun.fileDescriptor).detachFd()
        } catch (t: Throwable) {
            failStart("Hysteria tun fd dup failed: ${t.message}")
            return
        }
        if (!hy.startTun(tunFd = tunFd, mtu = mtu)) {
            failStart(hy.lastErrorMessage ?: "Hysteria tun pump failed")
            return
        }

        val probeCandidate = XrayRuntimeCandidate(
            id = nodeId,
            host = server.substringBefore(':'),
            label = "hysteria",
            configJson = hysteriaTun2SocksConfig(mtu),
        )
        if (!probeSocksHttps(probeCandidate)) {
            failStart("$nodeId@$server: SOCKS HTTPS probe failed")
            return
        }

        isRunning = true
        establishInProgress = false
        currentStatus = "connected"
        VpnStatusBroadcaster.emit(currentStatus)
        showConnectedNotification()
        startTrafficMonitor()
        Log.i(TAG, "startVpn: Hysteria established server=$server user=$username")
    }

    /**
     * SOCKS CONNECT to 1.1.1.1:443 through local Xray SOCKS — must pass before
     * `connected`. Runs off the main thread (no TLS, no generate_204).
     */
    private fun probeSocksHttps(selected: XrayRuntimeCandidate): Boolean {
        val okFlag = AtomicBoolean(false)
        val done = CountDownLatch(1)
        Thread(
            {
                try {
                    // Poll SOCKS accept readiness instead of a blind sleep(500).
                    val warmupDeadline =
                        SystemClock.elapsedRealtime() + XRAY_SOCKS_WARMUP_BUDGET_MS
                    while (SystemClock.elapsedRealtime() < warmupDeadline) {
                        if (VpnPingMonitor.isSocksReachable(
                                timeoutMs = XRAY_SOCKS_WARMUP_POLL_MS,
                            )
                        ) {
                            break
                        }
                        Thread.sleep(50)
                    }
                    for (attempt in 1..XRAY_SOCKS_PROBE_ATTEMPTS) {
                        if (!VpnPingMonitor.isSocksReachable(timeoutMs = 800)) {
                            Log.w(
                                TAG,
                                "SOCKS not reachable yet candidate=" +
                                    "${selected.id}@${selected.host} " +
                                    "attempt=$attempt/$XRAY_SOCKS_PROBE_ATTEMPTS",
                            )
                            Thread.sleep(XRAY_SOCKS_PROBE_RETRY_SLEEP_MS)
                            continue
                        }
                        val outcome = VpnPingMonitor.socksConnectProbe(
                            timeoutMs = XRAY_SOCKS_PROBE_TIMEOUT_MS,
                        )
                        if (outcome is VpnPingMonitor.SocksHttpsResult.Ok) {
                            Log.i(
                                TAG,
                                "SOCKS CONNECT ${outcome.code}ms ok candidate=" +
                                    "${selected.id}@${selected.host} attempt=$attempt",
                            )
                            okFlag.set(true)
                            return@Thread
                        }
                        Log.w(
                            TAG,
                            "SOCKS CONNECT probe fail candidate=" +
                                "${selected.id}@${selected.host} " +
                                "attempt=$attempt/$XRAY_SOCKS_PROBE_ATTEMPTS " +
                                "err=${outcome.detail}",
                        )
                        Thread.sleep(XRAY_SOCKS_PROBE_RETRY_SLEEP_MS)
                    }
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                } finally {
                    done.countDown()
                }
            },
            "teremok-socks-probe",
        ).apply { isDaemon = true }.start()

        val budgetMs =
            XRAY_SOCKS_WARMUP_BUDGET_MS +
                XRAY_SOCKS_PROBE_ATTEMPTS *
                (XRAY_SOCKS_PROBE_TIMEOUT_MS + XRAY_SOCKS_PROBE_RETRY_SLEEP_MS + 800L)
        val finished = try {
            done.await(budgetMs, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            false
        }
        if (!finished) {
            Log.w(
                TAG,
                "SOCKS CONNECT probe timeout candidate=${selected.id}@${selected.host}",
            )
        }
        return okFlag.get()
    }

    private fun failStart(message: String) {
        establishInProgress = false
        VpnStatusBroadcaster.setError(message)
        DiagnosticRing.append(TAG, "failStart autoProving=$autoProving msg=$message")
        if (autoProving) {
            Log.w(TAG, "failStart during auto prove (no stopSelf): $message")
            teardownCores()
            return
        }
        currentStatus = "error"
        VpnStatusBroadcaster.emit(currentStatus)
        markSessionInactive()
        stopVpn()
    }

    /** Stop cores + TUN without [stopSelf] (engine re-establish). */
    private fun teardownCores() {
        try {
            stopTrafficMonitor()
            HysteriaBridge.instance.stop()
            TrustTunnelBridge.instance.stop()
            XrayBridge.instance.stop()
            tunInterface?.close()
            Log.i(TAG, "teardownCores: cores stopped, TUN closed if any")
        } catch (e: Exception) {
            Log.e(TAG, "teardownCores: error", e)
        } finally {
            ProtectGuard.onFailure = null
            tunInterface = null
            isRunning = false
            establishInProgress = false
            // TUN is gone — never leave Flutter/getStatus on "connected"
            // after a real stop. Auto hops (Binding/Proving) must keep
            // connecting/probing: idle here paints Nest rest while Hy2 is live.
            if (currentStatus != "revoked" && currentStatus != "disconnecting") {
                val hop = autoProving ||
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
            Log.e(TAG, "stopVpn: error", e)
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
        val notification = VpnNotificationHelper.buildConnected(
            context = this,
            sessionLine = notificationSessionLine,
            downText = downText,
            upText = upText,
        )
        startForeground(VpnNotificationHelper.notificationId(), notification)
    }

    /** Settings toggled detailed shade card — refresh FGS notification style. */
    fun onNotificationStyleChanged() {
        if (currentStatus != "connected" && currentStatus != "connecting" &&
            currentStatus != "preparing"
        ) {
            return
        }
        // Traffic monitor always runs while connected (feeds Home + optional shade).
        if (currentStatus == "connected") {
            startTrafficMonitor()
            val down = if (VpnNotificationHelper.isDetailedEnabled(this)) {
                VpnTrafficBroadcaster.lastDownText
            } else {
                ""
            }
            val up = if (VpnNotificationHelper.isDetailedEnabled(this)) {
                VpnTrafficBroadcaster.lastUpText
            } else {
                ""
            }
            showConnectedNotification(downText = down, upText = up)
        } else {
            startForeground(
                VpnNotificationHelper.notificationId(),
                VpnNotificationHelper.startConnecting(this),
            )
        }
    }

    private fun startTrafficMonitor() {
        stopTrafficMonitor()
        trafficMonitor = VpnTrafficMonitor(this) { downBps, upBps, downText, upText ->
            VpnTrafficBroadcaster.emit(downBps, upBps, downText, upText)
            if (currentStatus == "connected" &&
                VpnNotificationHelper.isDetailedEnabled(this)
            ) {
                showConnectedNotification(downText = downText, upText = upText)
            }
        }.also { it.start() }
        // Home ping off: SOCKS CONNECT every 5s shared the same proxy as tabs.
        // Flutter already renders `— ms` when delayMs is null.
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
        Log.w(TAG, "onRevoke: VPN отозван системой или пользователем")
        currentStatus = "revoked"
        VpnStatusBroadcaster.emit(currentStatus)
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy: VpnService уничтожен")
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
    const val METHOD_CHANNEL = "teremok/vpn"
    const val EVENT_CHANNEL = "teremok/vpn/status"
    const val SESSION_EVENT_CHANNEL = "teremok/vpn/session"
    const val TRAFFIC_EVENT_CHANNEL = "teremok/vpn/traffic"
    const val PING_EVENT_CHANNEL = "teremok/vpn/ping"

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
        serviceProvider: () -> TeremokVpnService?,
        onPermissionRequest: (MethodChannel.Result) -> Unit,
        onNotificationPermissionRequest: (MethodChannel.Result) -> Unit = {},
    ) {
        // MethodChannel — команды от Flutter
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAuto" -> {
                        val rows = call.argument<List<*>>("candidatesJson")
                            ?: emptyList<Any?>()
                        val arr = JSONArray()
                        for (row in rows) {
                            val text = row as? String ?: continue
                            runCatching { arr.put(JSONObject(text)) }
                        }
                        val intent = Intent(
                            appContext,
                            TeremokVpnService::class.java,
                        ).apply {
                            action = TeremokVpnService.ACTION_START_AUTO
                            putExtra(
                                TeremokVpnService.EXTRA_AUTO_CANDIDATES,
                                arr.toString(),
                            )
                        }
                        appContext.startService(intent)
                        result.success(true)
                    }
                    "start" -> {
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
                            ?: json.optString("outboundType", "").ifBlank { "vless" }

                        val intent = Intent(
                            appContext,
                            TeremokVpnService::class.java,
                        ).apply {
                            action = TeremokVpnService.ACTION_START
                            putExtra(TeremokVpnService.EXTRA_USERNAME, username)
                            putExtra(TeremokVpnService.EXTRA_PROTOCOL, protocol)
                            putExtra(TeremokVpnService.EXTRA_PARAMS_JSON, paramsJson)
                            putExtra(TeremokVpnService.EXTRA_APP_INITIATED, true)
                        }
                        appContext.startService(intent)
                        result.success(true)
                    }
                    "stop" -> {
                        val intent = Intent(
                            appContext,
                            TeremokVpnService::class.java,
                        ).apply {
                            action = TeremokVpnService.ACTION_STOP
                        }
                        appContext.startService(intent)
                        result.success(true)
                    }
                    "getStatus" -> {
                        result.success(TeremokVpnService.resolveUiStatus(appContext))
                    }
                    "hasActiveSession" -> {
                        result.success(TeremokVpnService.hasActiveSession(appContext))
                    }
                    "getLastError" -> {
                        result.success(VpnStatusBroadcaster.lastError())
                    }
                    "isLockdownEnabled" -> {
                        // Preference/system lockdown — not tunnel-up. See
                        // [TeremokVpnService.queryAlwaysOnVpnSnapshot].
                        // Map → Dart; null lockdown → unavailable.
                        runCatching {
                            TeremokVpnService.queryAlwaysOnVpnSnapshot(
                                appContext,
                                serviceProvider() ?: TeremokVpnService.currentInstance(),
                            )
                        }.fold(
                            onSuccess = { result.success(it) },
                            onFailure = { e ->
                                Log.w(
                                    TeremokVpnService.TAG,
                                    "isLockdownEnabled query failed",
                                    e,
                                )
                                result.success(null)
                            },
                        )
                    }
                    "getVpnConflict" -> {
                        runCatching {
                            TeremokVpnService.queryVpnConflict(appContext)
                        }.fold(
                            onSuccess = { result.success(it) },
                            onFailure = { e ->
                                Log.w(
                                    TeremokVpnService.TAG,
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
                            Log.i(
                                TeremokVpnService.TAG,
                                "openVpnSettings resolve=$resolved activity=${activity != null}",
                            )
                            if (activity != null) {
                                activity.startActivity(intent)
                            } else {
                                appContext.startActivity(intent)
                            }
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            Log.w(TeremokVpnService.TAG, "openVpnSettings: no activity", e)
                            result.error("VPN_SETTINGS_UNAVAILABLE", e.message, null)
                        } catch (e: Exception) {
                            Log.w(TeremokVpnService.TAG, "openVpnSettings failed", e)
                            result.error("VPN_SETTINGS_FAILED", e.message, null)
                        }
                    }
                    "getSingBoxStderrTail" -> {
                        val maxLines = call.argument<Int>("maxLines") ?: 400
                        result.success(
                            TeremokVpnService.readSingBoxStderrTail(appContext, maxLines),
                        )
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
                    "isVpnNotificationDetailedEnabled" -> {
                        result.success(VpnNotificationHelper.isDetailedEnabled(appContext))
                    }
                    "setVpnNotificationDetailedEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        VpnNotificationHelper.setDetailedEnabled(appContext, enabled)
                        val svc = serviceProvider() ?: TeremokVpnService.currentInstance()
                        svc?.onNotificationStyleChanged()
                        result.success(true)
                    }
                    "requestAddQsTile" -> {
                        val host = activityProvider() ?: appContext
                        QsTilePrompter.requestAdd(host, result)
                    }
                    "listLauncherApps" -> {
                        val includeIcons = call.argument<Boolean>("includeIcons") ?: true
                        result.success(listLauncherApps(appContext, includeIcons))
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
 * объектов и массивов). Используется для парсинга paramsJson в [TeremokVpnService].
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

    @Volatile
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
                Log.w(TeremokVpnService.TAG, "VpnStatusBroadcaster.replay failed: ${e.message}")
            }
        }
    }

    fun unregister() {
        sink = null
    }

    /** Update lastStatus without EventChannel (hop teardown during Auto). */
    fun remember(status: String) {
        lastStatus = status
    }

    fun emit(status: String) {
        lastStatus = status
        appContext?.let { TeremokTileService.requestListening(it) }
        mainHandler.post {
            val current = sink
            if (current != null) {
                try {
                    current.success(status)
                } catch (e: Exception) {
                    Log.w(TeremokVpnService.TAG, "VpnStatusBroadcaster.emit failed: ${e.message}")
                }
            }
        }
    }
}

/**
 * Broadcasts downlink/uplink rates to Flutter EventChannel `teremok/vpn/traffic`.
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
                Log.w(TeremokVpnService.TAG, "VpnTrafficBroadcaster.replay failed: ${e.message}")
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
                    Log.w(TeremokVpnService.TAG, "VpnTrafficBroadcaster.emit failed: ${e.message}")
                }
            }
        }
    }
}

/**
 * Broadcasts path latency (ms) to Flutter EventChannel `teremok/vpn/ping`.
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
                Log.w(TeremokVpnService.TAG, "VpnPingBroadcaster.replay failed: ${e.message}")
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
                    Log.w(TeremokVpnService.TAG, "VpnPingBroadcaster.clear emit failed: ${e.message}")
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
                    Log.w(TeremokVpnService.TAG, "VpnPingBroadcaster.emit failed: ${e.message}")
                }
            }
        }
    }
}