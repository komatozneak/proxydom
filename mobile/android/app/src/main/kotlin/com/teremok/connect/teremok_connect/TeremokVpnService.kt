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
import android.provider.Settings
import android.util.Log
import java.net.InetAddress
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Android VpnService с libbox JNI (sing-box tun2socks).
 *
 * Lifecycle:
 * - establish TUN через Builder
 * - TunForwarder → SingBoxBridge.setTunFd
 * - SingBoxBridge.start(config) → libbox CommandServer
 */
class TeremokVpnService : VpnService() {

    companion object {
        const val TAG = "TeremokVpn"
        const val ACTION_START = "com.teremok.connect.START_VPN"
        const val ACTION_STOP = "com.teremok.connect.STOP_VPN"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_PROTOCOL = "protocol"
        const val EXTRA_PARAMS_JSON = "paramsJson"

        /** Минимальный интервал между попытками start (debounce reconnect storm). */
        private const val START_DEBOUNCE_MS = 2000L

        const val PREFS_NAME = "teremok_vpn_session"
        private const val KEY_PARAMS_JSON = "params_json"
        private const val KEY_USERNAME = "username"
        private const val KEY_PROTOCOL = "protocol"
        private const val KEY_ACTIVE = "active"

        @Volatile
        private var lastStartAttemptMs: Long = 0L

        @Volatile
        private var instance: TeremokVpnService? = null

        fun currentInstance(): TeremokVpnService? = instance

        /**
         * Always-on "Block connections without VPN".
         *
         * Prefer [VpnService.isLockdownEnabled] (system runtime SoT on API 29+).
         * [Settings.Secure] `always_on_vpn_lockdown` alone can lag after Off→On.
         */
        fun queryAlwaysOnVpnLockdown(
            context: android.content.Context,
            service: TeremokVpnService? = currentInstance(),
        ): Boolean {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val svc = service ?: currentInstance()
                if (svc != null) {
                    val enabled = svc.isLockdownEnabled
                    Log.i(TAG, "lockdown VpnService.isLockdownEnabled=$enabled")
                    return enabled
                }
            }
            val fromSecure = Settings.Secure.getInt(
                context.contentResolver,
                "always_on_vpn_lockdown",
                0,
            ) == 1
            val alwaysOnPkg = Settings.Secure.getString(
                context.contentResolver,
                "always_on_vpn_app",
            )
            Log.i(
                TAG,
                "lockdown Secure=$fromSecure alwaysOnPkg=$alwaysOnPkg pkg=${context.packageName}",
            )
            // If package is recorded and it isn't us, treat as off for our tile.
            if (alwaysOnPkg != null && alwaysOnPkg != context.packageName) {
                return false
            }
            return fromSecure
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
         * Status for Flutter [getStatus] — prefer live service, then
         * active-session + system VPN (Always-on / process race).
         */
        fun resolveUiStatus(context: android.content.Context): String {
            val live = instance?.currentStatus
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

        fun readSingBoxStderrTail(context: android.content.Context, maxLines: Int): String {
            val file = java.io.File(context.filesDir, "sing-box/stderr.log")
            if (!file.exists()) return "(none)"
            return runCatching {
                val lines = file.readLines()
                if (lines.isEmpty()) "(empty)" else lines.takeLast(maxLines).joinToString("\n")
            }.getOrElse { "(read error: ${it.message})" }
        }

        fun sessionPrefs(context: android.content.Context) =
            context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)

        /** Last successful connect params still on disk (survives intentional disconnect). */
        fun hasPersistedParams(context: android.content.Context): Boolean {
            val json = sessionPrefs(context).getString(KEY_PARAMS_JSON, null)
            return !json.isNullOrBlank()
        }

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
            if (paramsJson.isNullOrBlank()) {
                Log.w(TAG, "startFromPersistedSession: no params")
                return false
            }
            val username = store.getString(KEY_USERNAME, "anonymous") ?: "anonymous"
            val protocol = store.getString(KEY_PROTOCOL, "unknown") ?: "unknown"
            val intent = Intent(context, TeremokVpnService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_USERNAME, username)
                putExtra(EXTRA_PROTOCOL, protocol)
                putExtra(EXTRA_PARAMS_JSON, paramsJson)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            return true
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
    /** True only while [startVpn] is establishing TUN/libbox (not onCreate hint). */
    @Volatile
    private var establishInProgress = false
    private var tunForwarder: TunForwarder? = null
    private var trafficMonitor: VpnTrafficMonitor? = null
    private var pingMonitor: VpnPingMonitor? = null
    private var notificationSessionLine: String = "Теремок VPN"

    /**
     * Текущий статус сервиса для [VpnStatusBroadcaster].
     * Возможные значения: idle / preparing / connecting / connected /
     * disconnecting / revoked / error.
     */
    @Volatile
    var currentStatus: String = "idle"
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        VpnStatusBroadcaster.attachAppContext(applicationContext)
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
                Log.i(TAG, "onStartCommand: ACTION_START (user=$username, proto=$protocol)")
                // Persist before establish so Always-on / sticky restart after reboot
                // can rebuild the tunnel without Flutter reinjecting params.
                persistSession(username, protocol, paramsJson)
                val params = runCatching { jsonToMap(JSONObject(paramsJson)) }
                    .onFailure { Log.w(TAG, "failed to parse paramsJson, using defaults", it) }
                    .getOrDefault(emptyMap())
                startVpn(username, protocol, params)
            }
            ACTION_STOP -> {
                Log.i(TAG, "onStartCommand: ACTION_STOP")
                // Keep params_json so Quick Settings can reconnect without Flutter.
                markSessionInactive()
                stopVpn()
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

    private fun persistSession(username: String, protocol: String, paramsJson: String) {
        prefs().edit()
            .putBoolean(KEY_ACTIVE, true)
            .putString(KEY_USERNAME, username)
            .putString(KEY_PROTOCOL, protocol)
            .putString(KEY_PARAMS_JSON, paramsJson)
            .apply()
        Log.i(TAG, "persistSession: saved (${paramsJson.length} chars)")
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
        val params = runCatching { jsonToMap(JSONObject(paramsJson)) }
            .onFailure { Log.w(TAG, "restoreSessionIfNeeded: bad JSON", it) }
            .getOrDefault(emptyMap())
        if (params.isEmpty()) {
            clearSession()
            currentStatus = "idle"
            VpnStatusBroadcaster.emit(currentStatus)
            return
        }
        startVpn(username, protocol, params)
    }

    /** Prefer runtime SoT; Secure can lag right after the user toggles lockdown. */
    private fun isAlwaysOnVpnLockdownSetting(): Boolean =
        queryAlwaysOnVpnLockdown(this, this)

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

    /**
     * Создаёт TUN-интерфейс через Builder.establish() на основе распарсенных
     * параметров из sing-box config (см. [VpnServiceConfig.toJsonString] в Dart).
     *
     * Пока не подключаем к sing-box — это будет в Шаге 14+.
     */
    private fun startVpn(
        username: String,
        protocol: String,
        params: Map<String, Any?>,
    ) {
        if (isRunning) {
            Log.w(TAG, "startVpn: уже запущен, пропускаем")
            // Re-emit so Flutter UI that restarted can sync to Connected.
            currentStatus = "connected"
            VpnStatusBroadcaster.emit(currentStatus)
            return
        }
        // Note: onCreate may set currentStatus=preparing when KEY_ACTIVE (UI hint
        // for Always-on). That must NOT block a real ACTION_START — only an
        // in-flight establish / debounce should.
        if (establishInProgress) {
            Log.w(TAG, "startVpn: establish already in progress, пропускаем")
            return
        }
        val now = System.currentTimeMillis()
        if (now - lastStartAttemptMs < START_DEBOUNCE_MS) {
            Log.w(TAG, "startVpn: debounce (${now - lastStartAttemptMs}ms), пропускаем")
            return
        }
        lastStartAttemptMs = now
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
            val outboundServer = (params["outboundServer"] as? String) ?: "unknown"
            val outboundServerPort = (params["outboundServerPort"] as? Number)?.toInt() ?: 443
            val outboundUuid = (params["outboundUuid"] as? String) ?: ""
            val outboundFlow = params["outboundFlow"] as? String
            val tlsFingerprint = params["outboundTlsFingerprint"] as? String
            val tlsSni = params["outboundTlsSni"] as? String
            val tlsPublicKey = params["outboundTlsPublicKey"] as? String
            val tlsShortId = params["outboundTlsShortId"] as? String

            Log.i(TAG, "startVpn: $sessionName (mtu=$mtu)")
            Log.i(TAG, "  tunnel: $address/$addressPrefix, routes=$routes, dns=$dnsServers")
            Log.i(
                TAG,
                "  outbound: $outboundServer:$outboundServerPort flow=$outboundFlow",
            )
            Log.i(
                TAG,
                "  tls: sni=$tlsSni fp=$tlsFingerprint pk=$tlsPublicKey sid=$tlsShortId",
            )

            val builder = Builder()
                .setSession(sessionName)
                .setMtu(mtu)
                .addAddress(address, addressPrefix)

            for (route in routes) {
                val parts = route.split("/")
                if (parts.size == 2) {
                    // IPv6 default route без v6-адреса на TUN ломает connectivity на Android.
                    if (parts[0].contains(":")) {
                        Log.w(TAG, "  skip IPv6 route '$route' (no inet6 on TUN)")
                        continue
                    }
                    try {
                        builder.addRoute(parts[0], parts[1].toInt())
                        Log.i(TAG, "  added route: $route")
                    } catch (e: Exception) {
                        Log.w(TAG, "  invalid route '$route', skipping")
                    }
                } else {
                    Log.w(TAG, "  invalid route '$route' (expected addr/prefix), skipping")
                }
            }

            for (dns in dnsServers) {
                builder.addDnsServer(dns)
            }

            applyBypassRoutes(builder, outboundServer, params)

            currentStatus = "connecting"
            VpnStatusBroadcaster.emit(currentStatus)

            // До TUN: underlying network должен быть известен для direct→VPS.
            DefaultNetworkMonitor.prewarm(this)
            ProtectGuard.reset()
            ProtectGuard.onFailure = {
                Log.e(TAG, "startVpn: protect() failed — stopping VPN")
                Handler(Looper.getMainLooper()).post {
                    if (isRunning) {
                        failStart("VpnService.protect() failed")
                    }
                }
            }

            tunInterface = builder.establish()

            if (tunInterface == null) {
                ProtectGuard.onFailure = null
                failStart("VPN permission denied or establish() returned null")
                return
            }

            isRunning = true

            val singBoxConfigJson = (params["singBoxConfigJson"] as? String)
                ?.takeIf { it.isNotBlank() }
                ?: buildSingBoxJson(
                    params = params,
                    address = address,
                    addressPrefix = addressPrefix,
                    mtu = mtu,
                    outboundServer = outboundServer,
                    outboundServerPort = outboundServerPort,
                    outboundUuid = outboundUuid,
                    outboundFlow = outboundFlow,
                    tlsFingerprint = tlsFingerprint,
                    tlsSni = tlsSni,
                    tlsPublicKey = tlsPublicKey,
                    tlsShortId = tlsShortId,
                )
            Log.i(TAG, "startVpn: sing-box config (${singBoxConfigJson.length} chars)")

            val bridge = SingBoxBridge.instance
            bridge.bind(this)
            if (!bridge.loadLibrary()) {
                Log.e(TAG, "startVpn: libbox init failed")
                failStart("libbox init failed")
                return
            }

            val activeTun = tunInterface
            if (activeTun != null) {
                tunForwarder = TunForwarder(activeTun, bridge) {
                    Log.i(TAG, "TunForwarder: TUN fd wired to libbox")
                }
                tunForwarder?.start()
            } else {
                Log.e(TAG, "startVpn: tunInterface is null")
                failStart("TUN interface is null")
                return
            }

            if (!DefaultNetworkMonitor.awaitUnderlyingNetwork(this, 5000)) {
                Log.e(TAG, "startVpn: underlying network timeout — aborting")
                failStart("underlying network not ready")
                return
            }

            val started = bridge.start(singBoxConfigJson)
            if (!started) {
                val detail = bridge.lastErrorMessage ?: "unknown libbox error"
                Log.e(TAG, "startVpn: libbox не запустился: $detail")
                failStart(detail)
                return
            }

            if (ProtectGuard.hasFailed()) {
                Log.e(TAG, "startVpn: protect() failed during libbox start — aborting")
                failStart("VpnService.protect() failed")
                return
            }

            establishInProgress = false
            currentStatus = "connected"
            VpnStatusBroadcaster.emit(currentStatus)
            showConnectedNotification()
            startTrafficMonitor()
            Log.i(TAG, "startVpn: TUN interface established (protocol=$protocol)")
        } catch (e: Exception) {
            Log.e(TAG, "startVpn: failed", e)
            failStart(e.message ?: e.toString())
        }
    }

    private fun failStart(message: String) {
        establishInProgress = false
        VpnStatusBroadcaster.setError(message)
        currentStatus = "error"
        VpnStatusBroadcaster.emit(currentStatus)
        stopVpn()
    }

    private fun stopVpn() {
        if (!isRunning) {
            establishInProgress = false
            currentStatus = "idle"
            VpnStatusBroadcaster.emit(currentStatus)
            Log.w(TAG, "stopVpn: не запущен, пропускаем")
            return
        }
        try {
            currentStatus = "disconnecting"
            VpnStatusBroadcaster.emit(currentStatus)
            stopTrafficMonitor()
            // Сначала останавливаем sing-box, потом forwarder, потом закрываем TUN
            SingBoxBridge.instance.stop()
            tunForwarder?.stop()
            tunForwarder = null
            tunInterface?.close()
            Log.i(TAG, "stopVpn: TUN interface closed")
        } catch (e: Exception) {
            Log.e(TAG, "stopVpn: error closing tunInterface", e)
        } finally {
            ProtectGuard.onFailure = null
            tunInterface = null
            isRunning = false
            establishInProgress = false
            currentStatus = "idle"
            VpnStatusBroadcaster.emit(currentStatus)
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
        startPingMonitor()
    }

    private fun stopTrafficMonitor() {
        stopPingMonitor()
        trafficMonitor?.stop()
        trafficMonitor = null
        VpnTrafficBroadcaster.clear()
    }

    private fun startPingMonitor() {
        stopPingMonitor()
        pingMonitor = VpnPingMonitor { delayMs ->
            VpnPingBroadcaster.emit(delayMs)
        }.also { it.start() }
    }

    private fun stopPingMonitor() {
        pingMonitor?.stop()
        pingMonitor = null
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
    const val TRAFFIC_EVENT_CHANNEL = "teremok/vpn/traffic"
    const val PING_EVENT_CHANNEL = "teremok/vpn/ping"

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
                        // Distinguish query failure from "off" — do not default to false.
                        // Prefer VpnService.isLockdownEnabled (system SoT); Secure alone can
                        // stay stale after Off→On until a later process restart.
                        runCatching {
                            TeremokVpnService.queryAlwaysOnVpnLockdown(
                                appContext,
                                serviceProvider() ?: TeremokVpnService.currentInstance(),
                            )
                        }.fold(
                            onSuccess = { result.success(it) },
                            onFailure = { e ->
                                result.error(
                                    "LOCKDOWN_QUERY_FAILED",
                                    e.message,
                                    null,
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
                        val maxLines = call.argument<Int>("maxLines") ?: 30
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

        // EventChannel — libbox urlTest delay (ms) for Home ping
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
 * Собирает sing-box config JSON для libbox [CommandServer].
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
 * Собирает sing-box config JSON для libbox [CommandServer].
 */
internal fun buildSingBoxJson(
    params: Map<String, Any?>,
    address: String,
    addressPrefix: Int,
    mtu: Int,
    outboundServer: String,
    outboundServerPort: Int,
    outboundUuid: String,
    outboundFlow: String?,
    tlsFingerprint: String?,
    tlsSni: String?,
    tlsPublicKey: String?,
    tlsShortId: String?,
): String {
    val outbound = JSONObject().apply {
        put("type", "vless")
        put("tag", "proxy")
        put("network", "tcp")
        put("server", outboundServer)
        put("server_port", outboundServerPort)
        put("uuid", outboundUuid)
        if (!outboundFlow.isNullOrEmpty()) put("flow", outboundFlow)
        put(
            "tls",
            JSONObject().apply {
                put("enabled", true)
                if (!tlsSni.isNullOrEmpty()) put("server_name", tlsSni)
                put(
                    "utls",
                    JSONObject().apply {
                        put("enabled", true)
                        if (!tlsFingerprint.isNullOrEmpty()) {
                            put("fingerprint", tlsFingerprint)
                        }
                    },
                )
                put(
                    "reality",
                    JSONObject().apply {
                        put("enabled", true)
                        if (!tlsPublicKey.isNullOrEmpty()) put("public_key", tlsPublicKey)
                        if (!tlsShortId.isNullOrEmpty()) put("short_id", tlsShortId)
                    },
                )
            },
        )
    }

    val root = JSONObject().apply {
        put("log", JSONObject().apply { put("level", "debug") })
        put(
            "dns",
            JSONObject().apply {
                put(
                    "servers",
                    JSONArray().apply {
                        put(
                            JSONObject().apply {
                                put("type", "https")
                                put("tag", "dns-remote")
                                put("server", "1.1.1.1")
                                put("server_port", 443)
                                put("path", "/dns-query")
                                put("detour", "proxy")
                            },
                        )
                        put(
                            JSONObject().apply {
                                put("type", "fakeip")
                                put("tag", "dns-fakeip")
                                put("inet4_range", "198.18.0.0/15")
                            },
                        )
                    },
                )
                put(
                    "rules",
                    JSONArray().apply {
                        put(
                            JSONObject().apply {
                                put(
                                    "query_type",
                                    JSONArray().apply {
                                        put("A")
                                        put("AAAA")
                                    },
                                )
                                put("server", "dns-fakeip")
                            },
                        )
                    },
                )
                put("final", "dns-remote")
                put("reverse_mapping", true)
                put("strategy", "ipv4_only")
                put("independent_cache", true)
            },
        )
        put(
            "inbounds",
            JSONArray().apply {
                put(
                    JSONObject().apply {
                        put("type", "tun")
                        put("tag", "tun-in")
                        put("interface_name", "tun0")
                        put("mtu", mtu)
                        put(
                            "address",
                            JSONArray().apply { put("$address/$addressPrefix") },
                        )
                        put("auto_route", false)
                        put("stack", "system")
                    },
                )
            },
        )
        put(
            "outbounds",
            JSONArray().apply {
                put(JSONObject().apply { put("type", "direct"); put("tag", "direct") })
                put(outbound)
            },
        )
        put(
            "route",
            JSONObject().apply {
                put(
                    "rules",
                    JSONArray().apply {
                        put(
                            JSONObject().apply {
                                put("inbound", "tun-in")
                                put("action", "sniff")
                            },
                        )
                        put(
                            JSONObject().apply {
                                put("port", JSONArray().apply { put(53) })
                                put("action", "hijack-dns")
                            },
                        )
                        put(
                            JSONObject().apply {
                                put("protocol", "dns")
                                put("action", "hijack-dns")
                            },
                        )
                        put(
                            JSONObject().apply {
                                put(
                                    "ip_cidr",
                                    JSONArray().apply { put("198.18.0.0/15") },
                                )
                                put("outbound", "proxy")
                            },
                        )
                        if (outboundServer.isNotEmpty() && outboundServer != "unknown") {
                            put(
                                JSONObject().apply {
                                    put(
                                        "ip_cidr",
                                        JSONArray().apply { put("$outboundServer/32") },
                                    )
                                    put("outbound", "direct")
                                },
                            )
                        }
                        @Suppress("UNCHECKED_CAST")
                        val controlPlane = params["controlPlaneHosts"] as? List<*>
                        controlPlane?.forEach { host ->
                            if (host is String && host.isNotBlank()) {
                                put(
                                    JSONObject().apply {
                                        put(
                                            "ip_cidr",
                                            JSONArray().apply { put("${host.trim()}/32") },
                                        )
                                        put("outbound", "direct")
                                    },
                                )
                            }
                        }
                    },
                )
                put("final", "proxy")
                put("auto_detect_interface", true)
            },
        )
    }
    return root.toString()
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

    fun emit(status: String) {
        lastStatus = status
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
 * Broadcasts libbox downlink/uplink rates to Flutter EventChannel `teremok/vpn/traffic`.
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
 * Broadcasts libbox urlTest delay (ms) to Flutter EventChannel `teremok/vpn/ping`.
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
        if (replay != null) {
            mainHandler.post {
                try {
                    sink.success(mapOf("delayMs" to replay))
                } catch (e: Exception) {
                    Log.w(TeremokVpnService.TAG, "VpnPingBroadcaster.replay failed: ${e.message}")
                }
            }
        }
    }

    fun unregister() {
        sink = null
    }

    fun clear() {
        lastDelayMs = null
    }

    fun emit(delayMs: Int) {
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