package com.teremok.connect.teremok_connect

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    /**
     * Текущий инстанс сервиса. На этом шаге сервис создаётся через
     * startService() (см. VpnChannelRegistry.start/stop), поэтому
     * ссылка может быть null — getStatus() вернёт "idle".
     * В Шаге 14 заменим на реальный binding через IBinder.
     */
    @Volatile
    private var activeService: TeremokVpnService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        VpnChannelRegistry.register(
            engine = flutterEngine,
            appContext = applicationContext,
            serviceProvider = { activeService },
            onPermissionRequest = {
                // На этом шаге просто сообщаем что permission у нас есть —
                // системный диалог был показан ДО старта сервиса
                // (см. логику VpnController.requestPermission + MainActivity
                // в Шаге 14, когда добавим UI flow с явным диалогом).
                true
            },
        )
    }
}