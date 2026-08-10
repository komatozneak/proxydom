package com.teremok.connect.teremok_connect

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Traffic monitor stub (libbox CommandClient removed with ADR 005).
 *
 * Emits zeros so Flutter EventChannel / shade notification stay alive without
 * crashing. Real Xray/TT counters are a follow-up.
 */
class VpnTrafficMonitor(
    @Suppress("UNUSED_PARAMETER") private val context: Context,
    private val onSpeeds: (
        downlinkBps: Long,
        uplinkBps: Long,
        downText: String,
        upText: String,
    ) -> Unit,
) {
    companion object {
        private const val TAG = "VpnTrafficMonitor"

        fun formatSpeed(bytesPerSecond: Long): String {
            if (bytesPerSecond <= 0) return "0 B/s"
            val kib = 1024.0
            val mib = kib * 1024.0
            return when {
                bytesPerSecond >= mib -> String.format("%.2f MiB/s", bytesPerSecond / mib)
                bytesPerSecond >= kib -> String.format("%.2f KiB/s", bytesPerSecond / kib)
                else -> "$bytesPerSecond B/s"
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var running = false

    fun start() {
        stop()
        running = true
        Log.i(TAG, "traffic monitor stub started (zeros until Xray/TT counters)")
        mainHandler.post {
            if (running) onSpeeds(0L, 0L, formatSpeed(0), formatSpeed(0))
        }
    }

    fun stop() {
        running = false
    }
}
