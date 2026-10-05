package com.proxydom.app

import android.net.TrafficStats
import hy2bind.Hy2bind

/**
 * Tunnel payload counters for shade speeds.
 *
 * Android 10+ SELinux denies untrusted_app reads of `/proc/net` and
 * `/sys/class/net`. `File.canRead()` still issues `access()` and the kernel
 * writes an AVC for every probe, so this process does not open those paths.
 *
 * Bytes come from the tun2socks trackers inside hy2bind (apps inside the
 * tunnel). [TrafficStats] device totals are only the fallback when the
 * native export cannot be read. rx is downlink, tx is uplink.
 */
object TunByteCounters {
    private const val TAG = "TunByteCounters"

    data class Sample(val rxBytes: Long, val txBytes: Long)

    @Volatile
    private var loggedSource: String? = null

    fun read(): Sample? {
        readCore()?.also {
            logSourceOnce("core")
            return it
        }
        readTrafficStatsTotal()?.also {
            logSourceOnce("trafficstats")
            return it
        }
        logSourceOnce("none")
        return null
    }

    fun bytesPerSecond(deltaBytes: Long, elapsedMs: Long): Long {
        if (elapsedMs <= 0L || deltaBytes <= 0L) return 0L
        return (deltaBytes * 1000L) / elapsedMs
    }

    private fun readCore(): Sample? {
        return try {
            val rx = Hy2bind.tunDownlinkBytes()
            val tx = Hy2bind.tunUplinkBytes()
            if (rx < 0L || tx < 0L) null else Sample(rxBytes = rx, txBytes = tx)
        } catch (_: Throwable) {
            null
        }
    }

    private fun readTrafficStatsTotal(): Sample? {
        val rx = runCatching { TrafficStats.getTotalRxBytes() }.getOrNull() ?: return null
        val tx = runCatching { TrafficStats.getTotalTxBytes() }.getOrNull() ?: return null
        if (rx < 0L || tx < 0L) return null
        return Sample(rxBytes = rx, txBytes = tx)
    }

    private fun logSourceOnce(source: String) {
        if (loggedSource == source) return
        loggedSource = source
        NativeLog.i(TAG, "byte source=$source")
    }
}
