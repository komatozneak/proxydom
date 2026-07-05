package com.teremok.connect.teremok_connect

import android.content.Context
import android.net.VpnService
import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.SystemProxyStatus
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridge к sing-box через libbox JNI ([libbox.aar]).
 *
 * Заменяет CLI child process (Шаг 14) на [CommandServer] + [PlatformInterface].
 * TUN fd передаётся через [setTunFd] — Commit 4 (TunForwarder).
 */
class SingBoxBridge private constructor() {

    companion object {
        private const val TAG = "SingBoxBridge"
        private const val WORK_DIR = "sing-box"
        private const val TEMP_DIR = "sing-box-temp"

        init {
            System.loadLibrary("box")
            Libbox.touch()
        }

        @JvmStatic
        val instance: SingBoxBridge by lazy { SingBoxBridge() }
    }

    private var appContext: Context? = null
    private var vpnService: VpnService? = null
    private var commandServer: CommandServer? = null
    private var tunFd: Int? = null
    private val isSetup = AtomicBoolean(false)
    private val isRunning = AtomicBoolean(false)

    private val platform = LibboxPlatform(
        tunFdProvider = { tunFd },
        protectSocket = { fd -> vpnService?.protect(fd) == true },
    )

    private val commandHandler = object : CommandServerHandler {
        override fun getSystemProxyStatus(): SystemProxyStatus? = null

        override fun serviceReload() {
            Log.i(TAG, "serviceReload requested")
        }

        override fun serviceStop() {
            Log.i(TAG, "serviceStop requested")
            stop()
        }

        override fun setSystemProxyEnabled(isEnabled: Boolean) {
            Log.i(TAG, "setSystemProxyEnabled: $isEnabled")
        }

        override fun writeDebugMessage(message: String?) {
            if (!message.isNullOrBlank()) {
                Log.i(TAG, "[libbox] $message")
            }
        }
    }

    /**
     * Установить context. Если [context] — [VpnService], сохраняем для [VpnService.protect].
     */
    fun bind(context: Context) {
        appContext = context.applicationContext
        if (context is VpnService) {
            vpnService = context
        }
        ensureSetup()
    }

    /**
     * Передать TUN file descriptor в libbox (Commit 4).
     * Вызывать после [android.net.VpnService.Builder.establish].
     */
    fun setTunFd(fd: Int) {
        tunFd = fd
        Log.i(TAG, "setTunFd: $fd")
    }

    /**
     * Инициализирует libbox runtime.
     */
    fun loadLibrary(): Boolean {
        val ctx = appContext
        if (ctx == null) {
            Log.e(TAG, "loadLibrary: bind() не вызван")
            return false
        }
        return try {
            ensureSetup()
            Log.i(TAG, "loadLibrary: libbox ${Libbox.version()} ready")
            true
        } catch (e: Exception) {
            Log.e(TAG, "loadLibrary: libbox setup failed", e)
            false
        }
    }

    /**
     * Запустить sing-box через [CommandServer.startOrReloadService].
     */
    fun start(singBoxConfigJson: String): Boolean {
        if (isRunning.get()) {
            Log.w(TAG, "start: уже запущен")
            return false
        }

        val ctx = appContext
        if (ctx == null) {
            Log.e(TAG, "start: bind() не вызван")
            return false
        }

        if (tunFd == null) {
            Log.e(TAG, "start: TUN fd not set — call setTunFd() first")
            return false
        }

        return try {
            ensureSetup()
            Libbox.checkConfig(singBoxConfigJson)

            val server = Libbox.newCommandServer(commandHandler, platform)
            server.start()
            server.startOrReloadService(singBoxConfigJson, OverrideOptions())
            commandServer = server
            isRunning.set(true)

            Log.i(TAG, "start: libbox CommandServer started (${Libbox.version()})")
            true
        } catch (e: Exception) {
            Log.e(TAG, "start: failed", e)
            commandServer?.close()
            commandServer = null
            isRunning.set(false)
            false
        }
    }

    /**
     * Остановить sing-box CommandServer.
     */
    fun stop() {
        val server = commandServer ?: return
        try {
            Log.i(TAG, "stop: closing CommandServer")
            runCatching { server.closeService() }
                .onFailure { Log.w(TAG, "closeService: ${it.message}") }
            server.close()
        } catch (e: Exception) {
            Log.e(TAG, "stop: error", e)
        } finally {
            commandServer = null
            isRunning.set(false)
            tunFd = null
        }
    }

    private fun ensureSetup() {
        if (isSetup.get()) return
        val ctx = appContext ?: error("SingBoxBridge.bind(context) must be called first")

        val basePath = ctx.filesDir.absolutePath
        val workingPath = File(ctx.filesDir, WORK_DIR).apply { mkdirs() }.absolutePath
        val tempPath = File(ctx.cacheDir, TEMP_DIR).apply { mkdirs() }.absolutePath

        val options = SetupOptions().apply {
            setBasePath(basePath)
            setWorkingPath(workingPath)
            setTempPath(tempPath)
            setFixAndroidStack(true)
            setLogMaxLines(3000)
        }
        Libbox.setup(options)

        val stderrLog = File(workingPath, "stderr.log").absolutePath
        runCatching { Libbox.redirectStderr(stderrLog) }
            .onFailure { Log.w(TAG, "redirectStderr failed: ${it.message}") }

        isSetup.set(true)
        Log.i(TAG, "ensureSetup: libbox ${Libbox.version()} base=$basePath")
    }
}
