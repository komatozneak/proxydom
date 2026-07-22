package com.teremok.connect.teremok_connect

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.StatusMessage

/**
 * Subscribes to libbox [CommandClient] status stream for live uplink/downlink speeds.
 */
class VpnTrafficMonitor(
    private val context: Context,
    private val onSpeeds: (downText: String, upText: String) -> Unit,
) {
    companion object {
        private const val TAG = "VpnTrafficMonitor"
        /** Status interval in nanoseconds (1 s). */
        private const val STATUS_INTERVAL_NS = 1_000_000_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var client: CommandClient? = null

    private val handler = object : CommandClientHandler {
        override fun clearLogs() {}

        override fun connected() {
            Log.i(TAG, "CommandClient connected")
        }

        override fun disconnected(message: String?) {
            Log.w(TAG, "CommandClient disconnected: $message")
        }

        override fun initializeClashMode(p0: io.nekohasekai.libbox.StringIterator?, p1: String?) {}

        override fun setDefaultLogLevel(level: Int) {}

        override fun updateClashMode(mode: String?) {}

        override fun writeConnectionEvents(p0: io.nekohasekai.libbox.ConnectionEvents?) {}

        override fun writeGroups(p0: io.nekohasekai.libbox.OutboundGroupIterator?) {}

        override fun writeLogs(p0: io.nekohasekai.libbox.LogIterator?) {}

        override fun writeStatus(status: StatusMessage?) {
            if (status == null || !status.trafficAvailable) return
            val down = formatSpeed(status.downlink)
            val up = formatSpeed(status.uplink)
            mainHandler.post { onSpeeds(down, up) }
        }
    }

    fun start() {
        stop()
        try {
            val options = CommandClientOptions().apply {
                setStatusInterval(STATUS_INTERVAL_NS)
                addCommand(Libbox.CommandStatus)
            }
            val commandClient = Libbox.newCommandClient(handler, options)
            commandClient.connect()
            client = commandClient
            Log.i(TAG, "traffic monitor started")
        } catch (e: Exception) {
            Log.e(TAG, "traffic monitor start failed", e)
        }
    }

    fun stop() {
        val active = client ?: return
        client = null
        runCatching { active.disconnect() }
            .onFailure { Log.w(TAG, "disconnect: ${it.message}") }
    }

    private fun formatSpeed(bytesPerSecond: Long): String {
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
