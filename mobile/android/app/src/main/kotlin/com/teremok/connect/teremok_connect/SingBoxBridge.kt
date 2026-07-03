package com.teremok.connect.teremok_connect

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.TimeUnit

/**
 * Bridge к sing-box native binary через Process.
 *
 * На этом шаге (Шаг 14) sing-box CLI запускается как child process.
 * Конфиг передаётся через stdin, логи читаются через stdout.
 *
 * ⚠️ Это НЕ оптимальный вариант для продакшена:
 * - Настоящий tun2socks требует передачи TUN fd от VpnService → sing-box.
 *   Это делается через fd inheritance на Linux/Android, что сложно.
 * - В Шаге 15 добавим tun2socks через прямое чтение fd.
 * - В Шаге 19 (release) — заменим на JNI binding.
 *
 * Для Шага 14 достаточно проверить инфраструктуру:
 * - binary копируется из assets в filesDir (chmod +x)
 * - стартует и принимает JSON config через stdin
 * - логи пишутся в logcat
 */
class SingBoxBridge private constructor() {

    companion object {
        private const val TAG = "SingBoxBridge"
        private const val BINARY_DIR_NAME = "sing-box"
        private const val BINARY_NAME = "sing-box"

        @JvmStatic
        val instance: SingBoxBridge by lazy { SingBoxBridge() }
    }

    private var process: Process? = null
    private var _appContext: Context? = null

    /**
     * Установить context (нужно вызвать до installBinary).
     */
    fun bind(context: Context) {
        _appContext = context.applicationContext
    }

    private val binariesDir: File
        get() {
            val ctx = _appContext
                ?: error("SingBoxBridge.bind(context) must be called first")
            return File(ctx.filesDir, BINARY_DIR_NAME).apply { mkdirs() }
        }

    /**
     * Копирует sing-box binary из assets в filesDir.
     * APK assets read-only — нужен реальный файл на диске для chmod +x.
     */
    fun installBinary(): Boolean {
        val ctx = _appContext
        if (ctx == null) {
            Log.e(TAG, "installBinary: bind() не вызван")
            return false
        }

        val assetName = pickAssetForAbi()
        val target = File(binariesDir, BINARY_NAME)

        if (target.exists() && target.canExecute()) {
            Log.i(TAG, "installBinary: уже установлен (${target.absolutePath})")
            return true
        }

        return try {
            ctx.assets.open(assetName).use { input: InputStream ->
                target.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            target.setExecutable(true, false)
            target.setReadable(true, false)
            Log.i(
                TAG,
                "installBinary: copied $assetName → ${target.absolutePath} " +
                    "(${target.length()} bytes, exec=${target.canExecute()})",
            )
            true
        } catch (e: Exception) {
            Log.e(TAG, "installBinary: failed", e)
            false
        }
    }

    /**
     * Выбираем asset по Build.SUPPORTED_ABIS[0].
     * Ожидаемые имена: sing-box-arm64 / sing-box-armv7 / sing-box-x86_64.
     */
    private fun pickAssetForAbi(): String {
        val primaryAbi = if (Build.SUPPORTED_ABIS.isNotEmpty()) {
            Build.SUPPORTED_ABIS[0]
        } else {
            "arm64-v8a"
        }
        val asset = when (primaryAbi) {
            "arm64-v8a" -> "sing-box-arm64"
            "armeabi-v7a" -> "sing-box-armv7"
            "x86_64" -> "sing-box-x86_64"
            "x86" -> "sing-box-x86_64" // legacy x86 fallback
            else -> "sing-box-arm64" // safe default
        }
        Log.i(TAG, "pickAssetForAbi: $primaryAbi → $asset")
        return asset
    }

    /**
     * Запустить sing-box с переданным sing-box JSON config.
     *
     * ⚠️ На этом шаге (Шаг 14) binary стартует и принимает конфиг,
     * но tun2socks НЕ работает (TUN fd не передаётся в process).
     * Реальный tun2socks — Шаг 15.
     */
    fun start(singBoxConfigJson: String): Boolean {
        if (process?.isAlive == true) {
            Log.w(TAG, "start: уже запущен (PID=${safePid(process!!)})")
            return false
        }

        val binary = File(binariesDir, BINARY_NAME)
        if (!binary.exists() || !binary.canExecute()) {
            Log.e(TAG, "start: binary не найден или не executable: ${binary.absolutePath}")
            return false
        }

        return try {
            val pb = ProcessBuilder(binary.absolutePath, "run")
            pb.redirectErrorStream(true)
            val p = pb.start()
            process = p

            // Отправляем конфиг в stdin
            val stdin: OutputStream = p.outputStream
            stdin.write(singBoxConfigJson.toByteArray())
            stdin.write("\n".toByteArray())
            stdin.flush()
            stdin.close()

            Log.i(TAG, "start: sing-box запущен, PID=${safePid(p)}")

            // Запускаем reader для stdout (логи) — fire and forget
            startLogReader(p.inputStream)

            true
        } catch (e: Exception) {
            Log.e(TAG, "start: failed", e)
            false
        }
    }

    /**
     * Остановить sing-box процесс.
     */
    fun stop() {
        val p = process ?: return
        try {
            Log.i(TAG, "stop: destroy() PID=${safePid(p)}")
            p.destroy()
            if (!p.waitFor(5, TimeUnit.SECONDS)) {
                Log.w(TAG, "stop: не завершился за 5 сек, force kill")
                p.destroyForcibly()
            }
        } catch (e: Exception) {
            Log.e(TAG, "stop: error", e)
        }
        process = null
    }

    private fun safePid(p: Process): Long {
        // Process.pid() появился в API 26 (Android 8.0). MinSdk=23,
        // поэтому используем reflection чтобы не падать на старых API.
        return try {
            val method = Process::class.java.getMethod("pid")
            (method.invoke(p) as? Long) ?: -1L
        } catch (e: NoSuchMethodException) {
            -1L
        } catch (e: Exception) {
            -1L
        }
    }

    private fun startLogReader(stream: InputStream) {
        Thread {
            try {
                stream.bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        Log.i(TAG, "[sing-box] $line")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "logReader: stream closed", e)
            }
        }.start()
    }
}