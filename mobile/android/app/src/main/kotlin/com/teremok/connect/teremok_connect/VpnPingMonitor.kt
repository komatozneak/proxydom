package com.teremok.connect.teremok_connect

import android.util.Log
import java.io.BufferedReader
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.URI
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * Periodic path-latency probe for Home `ms`.
 *
 * When SOCKS is up: SOCKS5 CONNECT to [PROBE_HOST]:443 **and** SOCKS HTTPS
 * [PROBE_URL] must both succeed — CONNECT-only can look healthy while the
 * HTTPS/DNS data-plane is dead (Europe XHTTP hang pattern).
 *
 * Fallback: direct TCP through TUN (no protect) when SOCKS is down.
 *
 * After [FAIL_CLEAR_THRESHOLD] consecutive failures, emits `null` so Flutter
 * shows `— ms` instead of freezing on the last good sample.
 */
class VpnPingMonitor(
    @Suppress("UNUSED_PARAMETER") private val groupTag: String = GROUP_TAG,
    /** Sample in ms, or null to clear Home ping. */
    private val onSample: (Int?) -> Unit,
) {
    companion object {
        private const val TAG = "VpnPingMonitor"
        const val GROUP_TAG = "proxy"
        const val MIN_PLAUSIBLE_MS = 30
        const val MAX_PLAUSIBLE_MS = 5000
        const val PROBE_INTERVAL_MS = 5_000L
        const val PROBE_TIMEOUT_MS = 3_500
        const val FAIL_CLEAR_THRESHOLD = 2
        const val PROBE_HOST = "1.1.1.1"
        const val PROBE_PORT = 443
        const val PROBE_URL = "https://cp.cloudflare.com/generate_204"
        const val PROBE_HTTPS_HOST = "cp.cloudflare.com"
        const val PROBE_HTTPS_PATH = "/generate_204"

        /** Returns null when [rawMs] is outside the plausible Home range. */
        fun clampDelayMs(rawMs: Long): Int? {
            if (rawMs < MIN_PLAUSIBLE_MS || rawMs > MAX_PLAUSIBLE_MS) return null
            return rawMs.toInt()
        }

        /**
         * Parses `HTTP/1.x NNN …` status line → code, or null if malformed.
         */
        fun parseHttpStatusCode(statusLine: String): Int? {
            val parts = statusLine.trim().split(Regex("\\s+"), limit = 3)
            if (parts.size < 2) return null
            if (!parts[0].startsWith("HTTP/")) return null
            return parts[1].toIntOrNull()
        }

        fun isSocksReachable(
            host: String = GvisorTun2Socks.SOCKS_HOST,
            port: Int = GvisorTun2Socks.SOCKS_PORT,
            timeoutMs: Int = 400,
        ): Boolean =
            runCatching {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress(host, port), timeoutMs)
                    true
                }
            }.getOrDefault(false)

        /**
         * SOCKS5 no-auth CONNECT RTT to [destHost]:[destPort] via [socksHost]:[socksPort].
         * Returns elapsed ms on success, null on failure.
         */
        fun socks5ConnectRttMs(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            destHost: String = PROBE_HOST,
            destPort: Int = PROBE_PORT,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): Long? =
            runCatching {
                Socket().use { socket ->
                    socket.soTimeout = timeoutMs
                    socket.connect(InetSocketAddress(socksHost, socksPort), timeoutMs)
                    val out = DataOutputStream(socket.getOutputStream())
                    val inp = DataInputStream(socket.getInputStream())

                    socks5Greeting(out, inp)

                    val addr = InetAddress.getByName(destHost).address
                    require(addr.size == 4) { "IPv4 probe only" }

                    val started = System.nanoTime()
                    out.writeByte(0x05)
                    out.writeByte(0x01)
                    out.writeByte(0x00)
                    out.writeByte(0x01)
                    out.write(addr)
                    out.writeShort(destPort)
                    out.flush()

                    socks5ReadConnectReply(inp)
                    (System.nanoTime() - started) / 1_000_000L
                }
            }.getOrNull()

        /**
         * HTTPS generate_204 via SOCKS5 domain CONNECT + TLS (not HttpURLConnection).
         *
         * Xray resolves DNS for the domain ATYP; avoids flaky Java SOCKS+HTTPS.
         */
        fun socksHttpsProbe(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            url: String = PROBE_URL,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): SocksHttpsResult {
            val target = runCatching { URI(url) }.getOrElse {
                return SocksHttpsResult.Fail("bad_url=${it.message}")
            }
            val host = target.host ?: PROBE_HTTPS_HOST
            val port = when {
                target.port > 0 -> target.port
                else -> 443
            }
            val path = when {
                target.rawPath.isNullOrEmpty() -> PROBE_HTTPS_PATH
                target.rawQuery.isNullOrEmpty() -> target.rawPath
                else -> "${target.rawPath}?${target.rawQuery}"
            }

            return try {
                Socket().use { plain ->
                    plain.soTimeout = timeoutMs
                    plain.connect(InetSocketAddress(socksHost, socksPort), timeoutMs)
                    val out = DataOutputStream(plain.getOutputStream())
                    val inp = DataInputStream(plain.getInputStream())

                    socks5Greeting(out, inp)
                    socks5ConnectDomain(out, inp, host, port)

                    val sslFactory = SSLSocketFactory.getDefault() as SSLSocketFactory
                    val ssl = sslFactory.createSocket(plain, host, port, true) as SSLSocket
                    try {
                        ssl.soTimeout = timeoutMs
                        ssl.startHandshake()
                        val writer = ssl.getOutputStream()
                        val request =
                            "GET $path HTTP/1.1\r\n" +
                                "Host: $host\r\n" +
                                "Connection: close\r\n" +
                                "User-Agent: TeremokVpnProbe/1\r\n" +
                                "\r\n"
                        writer.write(request.toByteArray(StandardCharsets.US_ASCII))
                        writer.flush()

                        val reader = BufferedReader(
                            InputStreamReader(ssl.getInputStream(), StandardCharsets.US_ASCII),
                        )
                        val statusLine = reader.readLine()
                            ?: return SocksHttpsResult.Fail("empty_status")
                        val code = parseHttpStatusCode(statusLine)
                            ?: return SocksHttpsResult.Fail("bad_status=$statusLine")
                        if (code in 200..299) {
                            SocksHttpsResult.Ok(code)
                        } else {
                            SocksHttpsResult.Fail("code=$code")
                        }
                    } finally {
                        runCatching { ssl.close() }
                    }
                }
            } catch (e: SocketTimeoutException) {
                SocksHttpsResult.Fail("timeout=${e.message ?: "read"}")
            } catch (e: Exception) {
                val kind = e.javaClass.simpleName
                SocksHttpsResult.Fail("$kind=${e.message ?: "err"}")
            }
        }

        /** Boolean wrapper for call sites that only need pass/fail. */
        fun socksHttpsOk(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            url: String = PROBE_URL,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): Boolean = socksHttpsProbe(socksHost, socksPort, url, timeoutMs).isOk

        fun tcpConnectRttMs(
            host: String = PROBE_HOST,
            port: Int = PROBE_PORT,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): Long? =
            runCatching {
                Socket().use { socket ->
                    val started = System.nanoTime()
                    socket.connect(InetSocketAddress(host, port), timeoutMs)
                    (System.nanoTime() - started) / 1_000_000L
                }
            }.getOrNull()

        private fun socks5Greeting(out: DataOutputStream, inp: DataInputStream) {
            out.write(byteArrayOf(0x05, 0x01, 0x00))
            out.flush()
            val ver = inp.readUnsignedByte()
            val method = inp.readUnsignedByte()
            if (ver != 0x05 || method != 0x00) {
                error("socks greeting ver=$ver method=$method")
            }
        }

        /** SOCKS5 CONNECT with ATYP domain — proxy resolves DNS. */
        private fun socks5ConnectDomain(
            out: DataOutputStream,
            inp: DataInputStream,
            host: String,
            port: Int,
        ) {
            val hostBytes = host.toByteArray(StandardCharsets.US_ASCII)
            require(hostBytes.size in 1..255) { "host length ${hostBytes.size}" }
            out.writeByte(0x05)
            out.writeByte(0x01)
            out.writeByte(0x00)
            out.writeByte(0x03)
            out.writeByte(hostBytes.size)
            out.write(hostBytes)
            out.writeShort(port)
            out.flush()
            socks5ReadConnectReply(inp)
        }

        private fun socks5ReadConnectReply(inp: DataInputStream) {
            val repVer = inp.readUnsignedByte()
            val rep = inp.readUnsignedByte()
            inp.readUnsignedByte()
            val atyp = inp.readUnsignedByte()
            when (atyp) {
                0x01 -> inp.skipBytes(4)
                0x03 -> {
                    val len = inp.readUnsignedByte()
                    inp.skipBytes(len)
                }
                0x04 -> inp.skipBytes(16)
                else -> error("socks atyp=$atyp")
            }
            inp.skipBytes(2)
            if (repVer != 0x05 || rep != 0x00) {
                error("socks connect rep=$rep")
            }
        }
    }

    /** Outcome of [socksHttpsProbe] — [Fail.reason] is log-safe. */
    sealed class SocksHttpsResult {
        data class Ok(val code: Int) : SocksHttpsResult()
        data class Fail(val reason: String) : SocksHttpsResult()

        val isOk: Boolean get() = this is Ok
        val detail: String
            get() = when (this) {
                is Ok -> "code=$code"
                is Fail -> reason
            }
    }

    private val running = AtomicBoolean(false)
    private val consecutiveFails = AtomicInteger(0)
    private var worker: Thread? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        consecutiveFails.set(0)
        worker =
            Thread(
                {
                    Log.i(TAG, "ping monitor started (SOCKS CONNECT+HTTPS then TUN TCP)")
                    while (running.get()) {
                        probeOnce()
                        var waited = 0L
                        while (running.get() && waited < PROBE_INTERVAL_MS) {
                            try {
                                Thread.sleep(200)
                            } catch (_: InterruptedException) {
                                break
                            }
                            waited += 200
                        }
                    }
                    Log.i(TAG, "ping monitor stopped")
                },
                "teremok-ping-monitor",
            ).apply {
                isDaemon = true
                start()
            }
    }

    fun stop() {
        running.set(false)
        worker?.interrupt()
        worker = null
        consecutiveFails.set(0)
    }

    private fun probeOnce() {
        val sample = measureSample()
        if (sample != null) {
            consecutiveFails.set(0)
            Log.i(TAG, "ping sample path=${sample.path} ${sample.ms}ms")
            runCatching { onSample(sample.ms) }
                .onFailure { Log.w(TAG, "onSample failed: ${it.message}") }
            return
        }

        val fails = consecutiveFails.incrementAndGet()
        Log.i(TAG, "ping sample failed consecutive=$fails")
        if (fails >= FAIL_CLEAR_THRESHOLD) {
            Log.i(TAG, "ping cleared after $fails consecutive failures")
            runCatching { onSample(null) }
                .onFailure { Log.w(TAG, "onSample(null) failed: ${it.message}") }
        }
    }

    private data class Sample(val ms: Int, val path: String)

    private fun measureSample(): Sample? {
        if (isSocksReachable()) {
            val connectMs = socks5ConnectRttMs()
            if (connectMs == null) {
                Log.i(TAG, "SOCKS CONNECT failed")
            } else {
                val https = socksHttpsProbe()
                if (!https.isOk) {
                    Log.i(
                        TAG,
                        "SOCKS CONNECT ok (${connectMs}ms) but HTTPS generate_204 " +
                            "failed (${https.detail})",
                    )
                    // CONNECT alone is not enough — treat as fail (no TUN fallback
                    // when SOCKS is up: TUN path would lie about app traffic).
                    return null
                }
                val clamped = clampDelayMs(connectMs) ?: return null
                return Sample(clamped, "socks5+https")
            }
        } else {
            Log.i(TAG, "SOCKS unreachable — trying TUN TCP")
        }

        val tunMs = tcpConnectRttMs() ?: return null
        val clamped = clampDelayMs(tunMs) ?: return null
        return Sample(clamped, "tun-tcp")
    }
}
