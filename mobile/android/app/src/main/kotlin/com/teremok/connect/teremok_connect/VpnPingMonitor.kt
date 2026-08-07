package com.teremok.connect.teremok_connect

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OutboundGroup
import io.nekohasekai.libbox.OutboundGroupIterator

/**
 * Path latency via libbox [CommandClient.urlTest] on the `proxy` urltest group.
 *
 * Dart Socket/HTTP probes while TUN is up measure local accept (~5ms) or cold
 * multi-RTT (~800ms) — not Speedtest-class idle RTT. Engine urlTest is the
 * verified source of truth (home-path-latency MoA 2026-07-25).
 */
class VpnPingMonitor(
    private val groupTag: String = GROUP_TAG,
    private val onDelayMs: (Int) -> Unit,
) {
    companion object {
        private const val TAG = "VpnPingMonitor"
        const val GROUP_TAG = "proxy"

        /** Reject TUN-local fakes and dead probes. */
        const val MIN_PLAUSIBLE_MS = 30
        const val MAX_PLAUSIBLE_MS = 5000

        /** How often to trigger urlTest (battery-friendly). */
        private const val PROBE_INTERVAL_MS = 15_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var client: CommandClient? = null
    private val probeRunnable = object : Runnable {
        override fun run() {
            triggerUrlTest()
            mainHandler.postDelayed(this, PROBE_INTERVAL_MS)
        }
    }

    private val handler = object : CommandClientHandler {
        override fun clearLogs() {}

        override fun connected() {
            Log.i(TAG, "CommandClient connected")
            triggerUrlTest()
        }

        override fun disconnected(message: String?) {
            Log.w(TAG, "CommandClient disconnected: $message")
        }

        override fun initializeClashMode(p0: io.nekohasekai.libbox.StringIterator?, p1: String?) {}

        override fun setDefaultLogLevel(level: Int) {}

        override fun updateClashMode(mode: String?) {}

        override fun writeConnectionEvents(p0: io.nekohasekai.libbox.ConnectionEvents?) {}

        override fun writeGroups(groups: OutboundGroupIterator?) {
            if (groups == null) return
            var best: Int? = null
            while (groups.hasNext()) {
                val group: OutboundGroup = groups.next()
                if (group.tag != groupTag) continue
                val items = group.items ?: continue
                while (items.hasNext()) {
                    val item = items.next()
                    val delay = item.urlTestDelay
                    if (delay in MIN_PLAUSIBLE_MS..MAX_PLAUSIBLE_MS) {
                        best = if (best == null) delay else minOf(best, delay)
                    } else if (delay > 0) {
                        Log.d(TAG, "reject delay=${delay}ms tag=${item.tag}")
                    }
                }
            }
            if (best != null) {
                val ms = best
                mainHandler.post { onDelayMs(ms) }
            }
        }

        override fun writeLogs(p0: io.nekohasekai.libbox.LogIterator?) {}

        override fun writeStatus(status: io.nekohasekai.libbox.StatusMessage?) {}
    }

    fun start() {
        stop()
        try {
            val options = CommandClientOptions().apply {
                addCommand(Libbox.CommandGroup)
            }
            val commandClient = Libbox.newCommandClient(handler, options)
            commandClient.connect()
            client = commandClient
            mainHandler.postDelayed(probeRunnable, 1_500L)
            Log.i(TAG, "ping monitor started group=$groupTag")
        } catch (e: Exception) {
            Log.e(TAG, "ping monitor start failed", e)
        }
    }

    fun stop() {
        mainHandler.removeCallbacks(probeRunnable)
        val active = client ?: return
        client = null
        runCatching { active.disconnect() }
            .onFailure { Log.w(TAG, "disconnect: ${it.message}") }
    }

    private var missingGroupLogged = false

    private fun triggerUrlTest() {
        val active = client ?: return
        try {
            active.urlTest(groupTag)
            Log.d(TAG, "urlTest($groupTag) scheduled")
        } catch (e: Exception) {
            val msg = e.message.orEmpty()
            // Avoid spamming logcat every 15s when runtime JSON omitted the group.
            if (msg.contains("outbound group not found") ||
                msg.contains(groupTag)
            ) {
                if (!missingGroupLogged) {
                    missingGroupLogged = true
                    Log.w(
                        TAG,
                        "urlTest: group '$groupTag' missing in sing-box config " +
                            "(will not retry-log). ${e.message}",
                    )
                }
                return
            }
            Log.w(TAG, "urlTest failed: ${e.message}")
        }
    }
}
