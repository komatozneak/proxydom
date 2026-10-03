package com.proxydom.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * Временная активити для ручной проверки VpnService на устройстве.
 *
 * Доступна ТОЛЬКО в debug-сборке через отдельный AndroidManifest.
 * В release-сборке Шага 19 этот файл будет удалён (или помечен @VisibleForTesting).
 *
 * Использование:
 * 1. adb shell am start -n com.proxydom.app.debug/.DebugVpnActivity
 * 2. Нажать "Start VPN" → системный диалог "Разрешить VPN"
 * 3. Разрешить → в logcat: "ProxyDomVpn: TUN interface established"
 * 4. Нажать "Stop VPN" → "TUN interface closed"
 */
class DebugVpnActivity : Activity() {

    companion object {
        const val TAG = "DebugVpn"
        const val VPN_REQUEST_CODE = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(TAG, "onCreate: DebugVpnActivity")

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 48, 48, 48)
        }

        val title = TextView(this).apply {
            text = "Proxy Dom — Debug VPN"
            textSize = 22f
            setPadding(0, 0, 0, 32)
        }

        val info = TextView(this).apply {
            text = """
                Этот экран только для разработки (Шаг 11).

                Используется для проверки Android VpnService без Flutter UI.

                В Шаге 12 здесь появится MethodChannel и Flutter будет
                управлять стартом/стопом через HomeScreen.
            """.trimIndent()
            setPadding(0, 0, 0, 32)
        }

        val startButton = Button(this).apply {
            text = "▶ Start VPN (mock)"
            setOnClickListener { startVpnFlow() }
        }

        val stopButton = Button(this).apply {
            text = "■ Stop VPN"
            setOnClickListener { stopVpn() }
        }

        val logButton = Button(this).apply {
            text = "📋 View logcat for ProxyDomVpn"
            setOnClickListener {
                Log.i(TAG, "Check logcat: adb logcat -s ProxyDomVpn:V DebugVpn:V")
                Toast.makeText(
                    this@DebugVpnActivity,
                    "Run: adb logcat -s ProxyDomVpn:V",
                    Toast.LENGTH_LONG,
                ).show()
            }
        }

        layout.addView(title)
        layout.addView(info)
        layout.addView(startButton)
        layout.addView(stopButton)
        layout.addView(logButton)

        setContentView(layout)
    }

    private fun startVpnFlow() {
        // 1. Проверяем что у нас есть права VPN.
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent != null) {
            // 2. Нужен запрос permission → запускаем системный диалог.
            Log.i(TAG, "startVpnFlow: запрашиваем permission")
            startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
        } else {
            // 3. Уже есть permission — стартуем сразу.
            Log.i(TAG, "startVpnFlow: permission уже есть, стартуем напрямую")
            launchVpnService()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                Log.i(TAG, "onActivityResult: permission GRANTED")
                launchVpnService()
            } else {
                Log.w(TAG, "onActivityResult: permission DENIED (result=$resultCode)")
                Toast.makeText(this, "VPN permission denied", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun launchVpnService() {
        val intent = Intent(this, ProxyDomVpnService::class.java).apply {
            action = ProxyDomVpnService.ACTION_START
            putExtra(ProxyDomVpnService.EXTRA_USERNAME, "debug_user")
            putExtra(ProxyDomVpnService.EXTRA_PROTOCOL, "VLESS+Reality")
        }
        startService(intent)
        Log.i(TAG, "launchVpnService: startService() отправлен")
    }

    private fun stopVpn() {
        val intent = Intent(this, ProxyDomVpnService::class.java).apply {
            action = ProxyDomVpnService.ACTION_STOP
        }
        startService(intent)
        Log.i(TAG, "stopVpn: stop signal отправлен")
    }
}