package com.teremok.connect.teremok_connect

import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
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

        /** Получить системный Intent для запроса VPN-разрешения, или null если уже есть. */
        fun prepareVpn(context: android.content.Context): Intent? {
            return VpnService.prepare(context)
        }
    }

    private var tunInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    private var tunForwarder: TunForwarder? = null

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
        currentStatus = "idle"
        VpnStatusBroadcaster.emit(currentStatus)
        Log.i(TAG, "onCreate: VpnService создан")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val username = intent.getStringExtra(EXTRA_USERNAME) ?: "anonymous"
                val protocol = intent.getStringExtra(EXTRA_PROTOCOL) ?: "unknown"
                val paramsJson = intent.getStringExtra(EXTRA_PARAMS_JSON) ?: "{}"
                Log.i(TAG, "onStartCommand: ACTION_START (user=$username, proto=$protocol)")
                val params = runCatching { jsonToMap(JSONObject(paramsJson)) }
                    .onFailure { Log.w(TAG, "failed to parse paramsJson, using defaults", it) }
                    .getOrDefault(emptyMap())
                startVpn(username, protocol, params)
            }
            ACTION_STOP -> {
                Log.i(TAG, "onStartCommand: ACTION_STOP")
                stopVpn()
            }
            else -> {
                Log.w(TAG, "onStartCommand: unknown action=${intent?.action}")
            }
        }
        return START_STICKY
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
            return
        }

        try {
            currentStatus = "preparing"
            VpnStatusBroadcaster.emit(currentStatus)

            val sessionName = (params["sessionName"] as? String)
                ?: "Teremok VPN ($username)"
            val mtu = (params["mtu"] as? Number)?.toInt() ?: 1500
            val address = (params["address"] as? String) ?: "10.255.255.1"
            val addressPrefix = (params["addressPrefix"] as? Number)?.toInt() ?: 30
            @Suppress("UNCHECKED_CAST")
            val routes = (params["routes"] as? List<String>) ?: listOf("0.0.0.0/0")
            @Suppress("UNCHECKED_CAST")
            val dnsServers = (params["dnsServers"] as? List<String>)
                ?: listOf("1.1.1.1", "8.8.8.8")
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

            currentStatus = "connecting"
            VpnStatusBroadcaster.emit(currentStatus)

            tunInterface = builder.establish()

            if (tunInterface == null) {
                currentStatus = "error"
                VpnStatusBroadcaster.emit(currentStatus)
                Log.e(TAG, "startVpn: Builder.establish() вернул null (permission denied?)")
                stopSelf()
                return
            }

            isRunning = true

            val singBoxConfigJson = buildSingBoxJson(
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
            if (!bridge.installBinary()) {
                Log.e(TAG, "startVpn: libbox init failed")
                currentStatus = "error"
                VpnStatusBroadcaster.emit(currentStatus)
                stopVpn()
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
                currentStatus = "error"
                VpnStatusBroadcaster.emit(currentStatus)
                stopVpn()
                return
            }

            val started = bridge.start(singBoxConfigJson)
            if (!started) {
                Log.e(TAG, "startVpn: libbox не запустился")
                currentStatus = "error"
                VpnStatusBroadcaster.emit(currentStatus)
                stopVpn()
                return
            }

            currentStatus = "connected"
            VpnStatusBroadcaster.emit(currentStatus)
            Log.i(TAG, "startVpn: TUN interface established (protocol=$protocol)")
        } catch (e: Exception) {
            currentStatus = "error"
            VpnStatusBroadcaster.emit(currentStatus)
            Log.e(TAG, "startVpn: failed", e)
            stopSelf()
        }
    }

    private fun stopVpn() {
        if (!isRunning) {
            currentStatus = "idle"
            VpnStatusBroadcaster.emit(currentStatus)
            Log.w(TAG, "stopVpn: не запущен, пропускаем")
            return
        }
        try {
            currentStatus = "disconnecting"
            VpnStatusBroadcaster.emit(currentStatus)
            // Сначала останавливаем sing-box, потом forwarder, потом закрываем TUN
            SingBoxBridge.instance.stop()
            tunForwarder?.stop()
            tunForwarder = null
            tunInterface?.close()
            Log.i(TAG, "stopVpn: TUN interface closed")
        } catch (e: Exception) {
            Log.e(TAG, "stopVpn: error closing tunInterface", e)
        } finally {
            tunInterface = null
            isRunning = false
            currentStatus = "idle"
            VpnStatusBroadcaster.emit(currentStatus)
            stopSelf()
        }
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

    fun register(
        engine: FlutterEngine,
        appContext: android.content.Context,
        serviceProvider: () -> TeremokVpnService?,
        onPermissionRequest: () -> Boolean,
    ) {
        // MethodChannel — команды от Flutter
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        // paramsJson — JSON-строка с flat keys (см. VpnServiceConfig)
                        val paramsJson = call.argument<String>("paramsJson") ?: "{}"
                        // username и protocol — для удобства логирования (можно вытащить
                        // и из JSON, но проще держать отдельно для теста)
                        val username = call.argument<String>("username")
                            ?: try {
                                JSONObject(paramsJson).optString("sessionName", "anonymous")
                                    .removePrefix("Teremok VPN (")
                                    .removeSuffix(")")
                            } catch (e: Exception) { "anonymous" }
                        val protocol = call.argument<String>("protocol")
                            ?: try {
                                JSONObject(paramsJson).optString("outboundType", "unknown")
                            } catch (e: Exception) { "unknown" }

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
                        result.success(serviceProvider()?.currentStatus ?: "idle")
                    }
                    "requestPermission" -> {
                        result.success(onPermissionRequest())
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
        put("log", JSONObject().apply { put("level", "info") })
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
                        put("strict_route", true)
                        put("stack", "gvisor")
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
                put("final", "proxy")
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
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(sink: EventChannel.EventSink) {
        this.sink = sink
    }

    fun unregister() {
        sink = null
    }

    fun emit(status: String) {
        val current = sink ?: return
        mainHandler.post {
            try {
                current.success(status)
            } catch (e: Exception) {
                Log.w(TeremokVpnService.TAG, "VpnStatusBroadcaster.emit failed: ${e.message}")
            }
        }
    }
}