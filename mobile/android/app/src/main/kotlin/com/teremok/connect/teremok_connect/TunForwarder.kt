package com.teremok.connect.teremok_connect

import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.IOException

/**
 * Forwarder между TUN interface и UNIX socket (Android LocalServerSocket),
 * через который sing-box (или будущий libbox JNI wrapper) может получить
 * доступ к TUN fd.
 *
 * ⚠️ На этом шаге (Шаг 15) работает в "stub" режиме:
 * - TUN interface создаётся (через VpnService.Builder.establish())
 * - UNIX socket поднимается для будущего подключения
 * - Когда кто-то подключится к сокету — форвардим пакеты между TUN и сокетом
 * - Реальный tun2socks (sing-box ↔ TUN через socketpair+SCM_RIGHTS) — Шаг 19
 *
 * Используем [LocalServerSocket] (Android API), потому что стандартный
 * [java.net.UnixDomainSocketAddress] требует API 26+, а у нас minSdk=23.
 *
 * На Шаге 19 (release) подключим настоящий JNI binding к libbox.so,
 * который напрямую примет TUN fd и сделает tun2socks через socketpair+SCM_RIGHTS.
 */
class TunForwarder(
    private val tunInterface: ParcelFileDescriptor,
    private val onReady: () -> Unit = {},
) {

    companion object {
        const val TAG = "TunForwarder"
        const val UNIX_SOCKET_NAME = "tun"
        private const val BUFFER_SIZE = 32 * 1024
    }

    private var forwardThread: Thread? = null
    private var serverSocket: LocalServerSocket? = null
    @Volatile private var isRunning = false

    /**
     * Создаёт UNIX socket и запускает accept-loop.
     * Когда клиент (sing-box / наш wrapper) подключится, начинает форвардить
     * пакеты между TUN и сокетом в отдельном handler-thread'е.
     */
    fun start() {
        if (isRunning) {
            Log.w(TAG, "start: уже запущен, пропускаем")
            return
        }
        isRunning = true

        try {
            serverSocket = LocalServerSocket(UNIX_SOCKET_NAME)
            Log.i(TAG, "Listening on UNIX socket: $UNIX_SOCKET_NAME")
        } catch (e: IOException) {
            Log.e(TAG, "start: failed to bind LocalServerSocket", e)
            isRunning = false
            return
        }

        forwardThread = Thread(
            {
                try {
                    runForwardLoop()
                } catch (e: Exception) {
                    Log.e(TAG, "Forwarder thread crashed", e)
                }
            },
            "TunForwarder",
        ).apply {
            isDaemon = true
            start()
        }

        // Уведомляем что forwarder стартовал (даже если никто не подключился)
        onReady()
    }

    private fun runForwardLoop() {
        val server = serverSocket ?: return
        while (isRunning) {
            try {
                val client = server.accept()
                Log.i(TAG, "Client connected: $client")
                handleClient(client)
            } catch (e: Exception) {
                if (isRunning) {
                    Log.w(TAG, "Accept error", e)
                }
            }
        }
        Log.i(TAG, "Forwarder loop exited")
    }

    /**
     * Stub: читаем-пишем между TUN и сокетом в обе стороны.
     * Реальный tun2socks (sing-box ↔ TUN) — Шаг 19.
     */
    private fun handleClient(client: LocalSocket) {
        val tunInput = ParcelFileDescriptor.AutoCloseInputStream(tunInterface)
        val tunOutput = ParcelFileDescriptor.AutoCloseOutputStream(tunInterface)
        val sockInput = client.inputStream
        val sockOutput = client.outputStream

        Thread(
            {
                try {
                    val tunBuffer = ByteArray(BUFFER_SIZE)
                    val sockBuffer = ByteArray(BUFFER_SIZE)

                    while (isRunning) {
                        // TUN → client
                        val bytesRead = try {
                            tunInput.read(tunBuffer)
                        } catch (e: IOException) {
                            if (isRunning) Log.w(TAG, "TUN read error", e)
                            -1
                        }
                        if (bytesRead > 0) {
                            try {
                                sockOutput.write(tunBuffer, 0, bytesRead)
                                sockOutput.flush()
                                Log.d(TAG, "TUN → client: $bytesRead bytes")
                            } catch (e: IOException) {
                                if (isRunning) Log.w(TAG, "client write error", e)
                                break
                            }
                        }

                        // client → TUN
                        val sockBytesRead = try {
                            sockInput.read(sockBuffer)
                        } catch (e: IOException) {
                            if (isRunning) Log.w(TAG, "client read error", e)
                            -1
                        }
                        if (sockBytesRead > 0) {
                            try {
                                tunOutput.write(sockBuffer, 0, sockBytesRead)
                                Log.d(TAG, "client → TUN: $sockBytesRead bytes")
                            } catch (e: IOException) {
                                if (isRunning) Log.w(TAG, "TUN write error", e)
                                break
                            }
                        }

                        // Маленькая пауза чтобы не крутить CPU
                        Thread.sleep(1)
                    }
                } catch (e: InterruptedException) {
                    Log.i(TAG, "Client handler interrupted")
                } catch (e: Exception) {
                    if (isRunning) {
                        Log.w(TAG, "handleClient: error", e)
                    }
                } finally {
                    try {
                        client.close()
                    } catch (_: Exception) {
                    }
                    Log.i(TAG, "Client disconnected")
                }
            },
            "TunClientHandler",
        ).apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        isRunning = false
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        forwardThread?.interrupt()
        Log.i(TAG, "Forwarder stopped")
    }
}