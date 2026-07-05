package com.teremok.connect.teremok_connect

import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * Передаёт TUN [ParcelFileDescriptor] в libbox через [SingBoxBridge.setTunFd].
 *
 * VpnService создаёт TUN через [android.net.VpnService.Builder.establish],
 * затем этот класс регистрирует fd до [SingBoxBridge.start].
 */
class TunForwarder(
    private val tunInterface: ParcelFileDescriptor,
    private val bridge: SingBoxBridge,
    private val onReady: () -> Unit = {},
) {

    companion object {
        const val TAG = "TunForwarder"
    }

    @Volatile
    private var isRunning = false

    /**
     * Регистрирует TUN fd в libbox. Вызывать после [establish] и до [SingBoxBridge.start].
     */
    fun start() {
        if (isRunning) {
            Log.w(TAG, "start: уже запущен")
            return
        }

        val fd = tunInterface.fd
        Log.i(TAG, "start: wiring TUN fd=$fd to libbox")
        bridge.setTunFd(fd)
        isRunning = true
        onReady()
    }

    fun stop() {
        if (!isRunning) return
        isRunning = false
        Log.i(TAG, "stop: TUN fd wiring cleared")
    }
}
