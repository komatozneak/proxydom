package com.teremok.connect.teremok_connect

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * Android VpnService — скелет для будущей sing-box интеграции (Шаги 14-15).
 *
 * Lifecycle:
 * - onCreate: сервис создан
 * - onStartCommand: вызывается через startService с intent.action = ACTION_START/STOP.
 *   Создаём TUN через Builder.establish() (пока без tun2socks).
 * - onRevoke: вызывается системой или при ручном отзыве из Settings.
 * - onDestroy: чистим ресурсы.
 *
 * На этом шаге VPN работает (системный диалог "Разрешить VPN" появляется),
 * но НЕ маршрутизирует трафик. Трафик пойдёт через sing-box в Шаге 15.
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

    override fun onCreate() {
        super.onCreate()
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
            val builder = Builder()
                .setSession("Teremok VPN ($username)")
                .setMtu(1500)
                // Минимальный адрес TUN (RFC 5737 documentation prefix).
                // В Шаге 15 мы будем парсить это из sing_box_config.inbounds.
                .addAddress("10.255.255.1", 30)
                .addRoute("0.0.0.0", 0) // весь IPv4 трафик
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")

            // В Шаге 15 заменим на tun2socks через sing-box.
            tunInterface = builder.establish()

            if (tunInterface == null) {
                Log.e(TAG, "startVpn: Builder.establish() вернул null (permission denied?)")
                stopSelf()
                return
            }

            isRunning = true
            Log.i(TAG, "startVpn: TUN interface established (protocol=$protocol)")
        } catch (e: Exception) {
            Log.e(TAG, "startVpn: failed", e)
            stopSelf()
        }
    }

    private fun stopVpn() {
        if (!isRunning) {
            Log.w(TAG, "stopVpn: не запущен, пропускаем")
            return
        }
        try {
            tunInterface?.close()
            Log.i(TAG, "stopVpn: TUN interface closed")
        } catch (e: Exception) {
            Log.e(TAG, "stopVpn: error closing tunInterface", e)
        } finally {
            tunInterface = null
            isRunning = false
            stopSelf()
        }
    }

    override fun onRevoke() {
        Log.w(TAG, "onRevoke: VPN отозван системой или пользователем")
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy: VpnService уничтожен")
        stopVpn()
        super.onDestroy()
    }
}