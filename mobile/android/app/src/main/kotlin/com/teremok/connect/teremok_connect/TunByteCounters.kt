package com.teremok.connect.teremok_connect

import android.net.TrafficStats
import android.util.Log
import java.io.File
import java.net.NetworkInterface

/**
 * TUN rx/tx bytes for shade speeds.
 *
 * Hy2 has no libbox CommandClient. UID [TrafficStats] counts the VPN app, not
 * apps inside the tunnel. Prefer tun sysfs / `/proc/net/dev`; last resort is
 * device-wide totals (default-route VPN ≈ tunnel).
 */
object TunByteCounters {
    private const val TAG = "TunByteCounters"

    data class Sample(val rxBytes: Long, val txBytes: Long)

    @Volatile
    private var loggedSource: String? = null

    fun read(): Sample? {
        readSysfsTun()?.also {
            logSourceOnce("sysfs")
            return it
        }
        readProcNetDev()?.also {
            logSourceOnce("proc")
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

    /**
     * Parse kernel `/proc/net/dev`. Receive bytes are field 0 after the colon;
     * transmit bytes are field 8.
     */
    fun parseProcNetDev(text: String): Sample? {
        for (raw in text.lineSequence()) {
            val line = raw.trim()
            val colon = line.indexOf(':')
            if (colon <= 0) continue
            val name = line.substring(0, colon).trim()
            if (!name.startsWith("tun")) continue
            val parts = line.substring(colon + 1).trim().split(Regex("\\s+"))
            if (parts.size < 9) continue
            val rx = parts[0].toLongOrNull() ?: continue
            val tx = parts[8].toLongOrNull() ?: continue
            return Sample(rxBytes = rx, txBytes = tx)
        }
        return null
    }

    internal fun tunInterfaceNames(): List<String> {
        val found = ArrayList<String>(2)
        val en = runCatching { NetworkInterface.getNetworkInterfaces() }.getOrNull()
            ?: return listOf("tun0")
        while (en.hasMoreElements()) {
            val ni = en.nextElement()
            val name = ni.name ?: continue
            if (!name.startsWith("tun")) continue
            val up = runCatching { ni.isUp }.getOrDefault(true)
            if (!up) continue
            found.add(name)
        }
        if (found.isEmpty()) found.add("tun0")
        return found
    }

    private fun readSysfsTun(): Sample? {
        for (name in tunInterfaceNames()) {
            val rx = readSysfs(name, "rx_bytes") ?: continue
            val tx = readSysfs(name, "tx_bytes") ?: continue
            return Sample(rxBytes = rx, txBytes = tx)
        }
        return null
    }

    private fun readProcNetDev(): Sample? {
        val path = File("/proc/net/dev")
        if (!path.canRead()) return null
        val text = runCatching { path.readText() }.getOrNull() ?: return null
        return parseProcNetDev(text)
    }

    private fun readTrafficStatsTotal(): Sample? {
        val rx = runCatching { TrafficStats.getTotalRxBytes() }.getOrNull() ?: return null
        val tx = runCatching { TrafficStats.getTotalTxBytes() }.getOrNull() ?: return null
        if (rx < 0L || tx < 0L) return null
        return Sample(rxBytes = rx, txBytes = tx)
    }

    private fun readSysfs(iface: String, file: String): Long? {
        val path = File("/sys/class/net/$iface/statistics/$file")
        if (!path.canRead()) return null
        return runCatching { path.readText().trim().toLong() }.getOrNull()
    }

    private fun logSourceOnce(source: String) {
        if (loggedSource == source) return
        loggedSource = source
        Log.i(TAG, "byte source=$source")
    }
}
