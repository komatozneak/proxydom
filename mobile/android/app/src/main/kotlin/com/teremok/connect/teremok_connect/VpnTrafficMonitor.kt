package com.teremok.connect.teremok_connect

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.util.Locale

/**
 * Home / shade ↓↑ from the TUN interface, not UID TrafficStats.
 *
 * libbox CommandClient is gone (ADR 005 / 018). A stub that always emitted
 * zeros made a live VpnService look dead after screen lock.
 */
class VpnTrafficMonitor(
    @Suppress("UNUSED_PARAMETER") private val context: Context,
    private val onSpeeds: (
        downlinkBps: Long,
        uplinkBps: Long,
        downText: String,
        upText: String,
    ) -> Unit,
    private val readSample: () -> TunByteCounters.Sample? = { TunByteCounters.read() },
) {
    companion object {
        private const val TAG = "VpnTrafficMonitor"
        private const val SAMPLE_MS = 1_000L

        fun formatSpeed(bytesPerSecond: Long): String {
            if (bytesPerSecond <= 0) return "0 B/s"
            val kib = 1024.0
            val mib = kib * 1024.0
            return when {
                bytesPerSecond >= mib -> String.format(Locale.US, "%.2f MiB/s", bytesPerSecond / mib)
                bytesPerSecond >= kib -> String.format(Locale.US, "%.2f KiB/s", bytesPerSecond / kib)
                else -> "$bytesPerSecond B/s"
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var running = false
    private var worker: Thread? = null
    private var lastRx = -1L
    private var lastTx = -1L
    private var lastAt = 0L

    fun start() {
        stop()
        running = true
        lastRx = -1L
        lastTx = -1L
        lastAt = 0L
        Log.i(TAG, "traffic monitor started (tun sysfs)")
        worker = Thread(
            {
                while (running) {
                    sampleOnce()
                    var waited = 0L
                    while (running && waited < SAMPLE_MS) {
                        try {
                            Thread.sleep(200)
                        } catch (_: InterruptedException) {
                            break
                        }
                        waited += 200
                    }
                }
            },
            "teremok-traffic-monitor",
        ).apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        running = false
        worker?.interrupt()
        worker = null
    }

    private fun sampleOnce() {
        val sample = readSample() ?: return
        val now = SystemClock.elapsedRealtime()
        val prevRx = lastRx
        val prevTx = lastTx
        val prevAt = lastAt
        lastRx = sample.rxBytes
        lastTx = sample.txBytes
        lastAt = now
        if (prevRx < 0L || prevAt <= 0L) return
        val elapsed = now - prevAt
        val down = TunByteCounters.bytesPerSecond(sample.rxBytes - prevRx, elapsed)
        val up = TunByteCounters.bytesPerSecond(sample.txBytes - prevTx, elapsed)
        val downText = formatSpeed(down)
        val upText = formatSpeed(up)
        mainHandler.post {
            if (running) onSpeeds(down, up, downText, upText)
        }
    }
}
