package com.proxydom.app

import java.io.BufferedReader
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.charset.StandardCharsets

/**
 * Home `ms` as one HTTP round trip on a kept-alive tunnel connection.
 *
 * A fresh SOCKS connection pays the tunnel's stream setup on every sample: the
 * first request through a new connection measured ~240 ms, while the next one
 * on the same connection measured ~152 ms for the same node — and the Windows
 * build, which measures in-process through the TUN, reads ~155 ms. Keeping the
 * connection makes each sample a single round trip instead of setup + round
 * trip, and keeps the number comparable across platforms.
 *
 * Any failure drops the connection; the next sample reopens it.
 */
internal class TunnelHttpProbe(
    private val socksHost: String = GvisorTun2Socks.SOCKS_HOST,
    private val socksPort: Int,
) : Closeable {
    private var socket: Socket? = null
    private var out: DataOutputStream? = null
    private var reader: BufferedReader? = null

    /**
     * Set by [close]. A probe that the session already dropped must not reopen
     * a stream behind its owner's back when a late loop iteration calls it.
     */
    @Volatile
    private var closed = false

    /** Round trip in ms, or null when the path did not answer. */
    fun sample(timeoutMs: Int): Long? {
        if (closed) return null
        val ms = runCatching { measure(timeoutMs) }.getOrNull()
        // A failed sample drops the stream; the next one reopens it.
        if (ms == null) dropConnection()
        return ms
    }

    private fun measure(timeoutMs: Int): Long? {
        if (socket == null) open(timeoutMs)
        val out = out ?: return null
        val reader = reader ?: return null
        socket?.soTimeout = timeoutMs

        val started = System.nanoTime()
        out.write(request())
        out.flush()

        val statusLine = reader.readLine() ?: return null
        val code = VpnPingMonitor.parseHttpStatusCode(statusLine) ?: return null
        // Drain the headers so the next request starts on a clean stream.
        var lines = 0
        while (true) {
            val line = reader.readLine() ?: return null
            if (line.isEmpty()) break
            if (++lines > MAX_HEADER_LINES) return null
        }
        val elapsed = (System.nanoTime() - started) / 1_000_000L
        // A body would desynchronise a reused stream: only a bodyless answer
        // may keep the connection.
        if (code != HTTP_NO_CONTENT) dropConnection()
        return elapsed
    }

    private fun open(timeoutMs: Int) {
        if (closed) error("probe closed")
        if (openWith(timeoutMs, viaIPv4 = true)) return
        if (openWith(timeoutMs, viaIPv4 = false)) return
        error("socks connect failed")
    }

    private fun openWith(timeoutMs: Int, viaIPv4: Boolean): Boolean {
        val s = Socket()
        return runCatching {
            s.soTimeout = timeoutMs
            s.connect(InetSocketAddress(socksHost, socksPort), timeoutMs)
            val o = DataOutputStream(s.getOutputStream())
            val i = DataInputStream(s.getInputStream())
            VpnPingMonitor.socks5Greeting(o, i)
            if (viaIPv4) {
                VpnPingMonitor.socks5ConnectIpv4(
                    o,
                    i,
                    VpnPingMonitor.PROBE_HOST,
                    VpnPingMonitor.PROBE_HTTP_PORT,
                )
            } else {
                VpnPingMonitor.socks5ConnectDomain(
                    o,
                    i,
                    VpnPingMonitor.PROBE_HTTPS_HOST,
                    VpnPingMonitor.PROBE_HTTP_PORT,
                )
            }
            socket = s
            out = o
            reader = BufferedReader(InputStreamReader(i, StandardCharsets.US_ASCII))
            true
        }.getOrElse {
            runCatching { s.close() }
            false
        }
    }

    /** HTTP/1.1 keep-alive: no `Connection: close`, so the stream survives. */
    private fun request(): ByteArray = (
        "GET ${VpnPingMonitor.PROBE_HTTPS_PATH} HTTP/1.1\r\n" +
            "Host: ${VpnPingMonitor.PROBE_HTTPS_HOST}\r\n" +
            "\r\n"
        ).toByteArray(StandardCharsets.US_ASCII)

    private fun dropConnection() {
        runCatching { socket?.close() }
        socket = null
        out = null
        reader = null
    }

    override fun close() {
        closed = true
        dropConnection()
    }

    private companion object {
        const val MAX_HEADER_LINES = 64
        const val HTTP_NO_CONTENT = 204
    }
}
