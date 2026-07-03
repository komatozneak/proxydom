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

/**
 * Android VpnService — скелет для будущей sing-box интеграции (Шаги 14-15).
 *
 * Lifecycle:
 * - onCreate: сервис создан, currentStatus = "idle"
 * - onStartCommand: вызывается через startService с intent.action = ACTION_START/STOP.
 *   Создаём TUN через Builder.establish() (пока без tun2socks).
 * - onRevoke: вызывается системой или при ручном отзыве из Settings.
 * - onDestroy: чистим ресурсы.
 *
 * На этом шаге VPN работает (системный диалог "Разрешить VPN" появляется),
 * но НЕ маршрутизирует трафик. Трафик пойдёт через sing-box в Шаге 15.
 *
 * Шаг 12: добавлен currentStatus + broadcaster для EventChannel.
 */
class TeremokVpnService : VpnService() {

    companion object {
        const val TAG = "TeremokVpn"
        const val ACTION_START = "com.teremok.connect.START_VPN"
        const val ACTION_STOP = "com.teremok.connect.STOP_VPN"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_PROTOCOL = "protocol"

        /** Получить системный Intent для запроса VPN-разрешения, или null если уже есть. */
        fun prepareVpn(context: android.content.Context): Intent? {
            return VpnService.prepare(context)
        }
    }

    private var tunInterface: ParcelFileDescriptor? = null
    private var isRunning = false

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
                Log.i(TAG, "onStartCommand: ACTION_START (user=$username, proto=$protocol)")
                startVpn(username, protocol)
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
     * Создаёт TUN-интерфейс через Builder.establish().
     * Пока не подключаем ни к чему — только проверяем что permission OK
     * и система выдаёт нам fd.
     *
     * В Шаге 14+ сюда добавится tun2socks через sing-box.
     */
    private fun startVpn(username: String, protocol: String) {
        if (isRunning) {
            Log.w(TAG, "startVpn: уже запущен, пропускаем")
            return
        }

        try {
            currentStatus = "preparing"
            VpnStatusBroadcaster.emit(currentStatus)

            val builder = Builder()
                .setSession("Teremok VPN ($username)")
                .setMtu(1500)
                // Минимальный адрес TUN (RFC 5737 documentation prefix).
                // В Шаге 15 мы будем парсить это из sing_box_config.inbounds.
                .addAddress("10.255.255.1", 30)
                .addRoute("0.0.0.0", 0) // весь IPv4 трафик
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")

            currentStatus = "connecting"
            VpnStatusBroadcaster.emit(currentStatus)

            // В Шаге 15 заменим на tun2socks через sing-box.
            tunInterface = builder.establish()

            if (tunInterface == null) {
                currentStatus = "error"
                VpnStatusBroadcaster.emit(currentStatus)
                Log.e(TAG, "startVpn: Builder.establish() вернул null (permission denied?)")
                stopSelf()
                return
            }

            isRunning = true
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
                        val username = call.argument<String>("username") ?: ""
                        val protocol = call.argument<String>("protocol") ?: ""
                        val intent = Intent(
                            appContext,
                            TeremokVpnService::class.java,
                        ).apply {
                            action = TeremokVpnService.ACTION_START
                            putExtra(TeremokVpnService.EXTRA_USERNAME, username)
                            putExtra(TeremokVpnService.EXTRA_PROTOCOL, protocol)
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