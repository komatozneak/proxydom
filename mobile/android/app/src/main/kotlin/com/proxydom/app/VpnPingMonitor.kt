package com.proxydom.app

import java.io.BufferedReader
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStreamReader
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.URI
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * Periodic path-latency probe for Home `ms`.
 *
 * When SOCKS is up: SOCKS5 CONNECT RTT to [PROBE_HOST]:443 (no TLS).
 * Fallback: direct TCP through TUN (no protect) when SOCKS is down.
 *
 * Connect/Auto prove uses [socksConnectProbe] (SOCKS CONNECT to
 * [PROBE_HOST]:443, no HTTP). Cloudflare generate_204 hangs through VPS.
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
        const val PROBE_HTTP_PORT = 80
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
         * SOCKS5 CONNECT to [PROBE_HOST]:443 — Connect/Auto gate.
         *
         * TCP handshake through the proxy only. HTTP/HTTPS generate_204 through
         * the VPS often never returns (Pixel: Read timed out, pages still load).
         */
        fun socksConnectProbe(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            destHost: String = PROBE_HOST,
            destPort: Int = PROBE_PORT,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): SocksHttpsResult =
            try {
                Socket().use { socket ->
                    socket.soTimeout = timeoutMs
                    socket.connect(InetSocketAddress(socksHost, socksPort), timeoutMs)
                    val out = DataOutputStream(socket.getOutputStream())
                    val inp = DataInputStream(socket.getInputStream())
                    socks5Greeting(out, inp)
                    val started = System.nanoTime()
                    socks5ConnectIpv4(out, inp, destHost, destPort)
                    val rttMs = ((System.nanoTime() - started) / 1_000_000L)
                        .toInt()
                        .coerceAtLeast(1)
                    SocksHttpsResult.Ok(rttMs)
                }
            } catch (e: SocketTimeoutException) {
                SocksHttpsResult.Fail("timeout=${e.message ?: "read"}")
            } catch (e: Exception) {
                SocksHttpsResult.Fail("${e.javaClass.simpleName}=${e.message ?: "err"}")
            }

        fun socksConnectOk(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): Boolean = socksConnectProbe(socksHost, socksPort, timeoutMs = timeoutMs).isOk

        /**
         * HTTP generate_204 via SOCKS5 — no TLS (Clash url-test / Android captive).
         *
         * First IPv4 CONNECT [PROBE_HOST]:80 + Host [PROBE_HTTPS_HOST] (no DNS).
         * If that fails, domain CONNECT [PROBE_HTTPS_HOST]:80.
         */
        fun socksHttpProbe(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): SocksHttpsResult {
            val ipv4 = socksHttpAfterConnect(
                socksHost = socksHost,
                socksPort = socksPort,
                timeoutMs = timeoutMs,
                connect = { out, inp ->
                    socks5ConnectIpv4(out, inp, PROBE_HOST, PROBE_HTTP_PORT)
                },
                hostHeader = PROBE_HTTPS_HOST,
            )
            if (ipv4.isOk) return ipv4
            runCatching { NativeLog.i(TAG, "HTTP 204 ipv4 fail (${ipv4.detail}) — domain :80") }
            return socksHttpAfterConnect(
                socksHost = socksHost,
                socksPort = socksPort,
                timeoutMs = timeoutMs,
                connect = { out, inp ->
                    socks5ConnectDomain(out, inp, PROBE_HTTPS_HOST, PROBE_HTTP_PORT)
                },
                hostHeader = PROBE_HTTPS_HOST,
            )
        }

        /**
         * Walk literal targets until one SOCKS CONNECT completes.
         *
         * `ipv4.icanhazip.com` is not a target: foreign exits reset that name.
         * An IP parsed from a trace is recorded on the sample and is not
         * required for [HttpProbeSample.tcp].
         */
        fun proveTunnel(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): TunnelAcceptance {
            val samples = ArrayList<HttpProbeSample>(3)
            val trace = probeTraceLiteral(socksHost, socksPort, timeoutMs)
            samples.add(trace)
            if (trace.tcp) return acceptTunnel(samples)
            val cloudflare = probeGenerate204Literal(
                socksHost = socksHost,
                socksPort = socksPort,
                timeoutMs = timeoutMs,
                name = "cp.cloudflare.com",
                port = 443,
                tls = true,
            )
            samples.add(cloudflare)
            if (cloudflare.tcp) return acceptTunnel(samples)
            samples.add(
                probeGenerate204Literal(
                    socksHost = socksHost,
                    socksPort = socksPort,
                    timeoutMs = timeoutMs,
                    name = "www.gstatic.com",
                    port = 80,
                    tls = false,
                ),
            )
            return acceptTunnel(samples)
        }

        /**
         * Public IPv4 via the name `ipv4.icanhazip.com`. Not an acceptance
         * gate: foreign exits reset that name. Callers may log the result.
         */
        fun socksExitIp(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): String? = runCatching {
            Socket().use { socket ->
                socket.soTimeout = timeoutMs
                socket.connect(InetSocketAddress(socksHost, socksPort), timeoutMs)
                val out = DataOutputStream(socket.getOutputStream())
                val inp = DataInputStream(socket.getInputStream())
                socks5Greeting(out, inp)
                socks5ConnectDomain(out, inp, "ipv4.icanhazip.com", 80)
                val request =
                    "GET / HTTP/1.0\r\nHost: ipv4.icanhazip.com\r\nConnection: close\r\n\r\n"
                out.write(request.toByteArray(StandardCharsets.US_ASCII))
                out.flush()
                val text = inp.readBytes().toString(StandardCharsets.US_ASCII)
                val body = text.substringAfter("\r\n\r\n", "")
                body.lineSequence()
                    .map { it.trim() }
                    .firstOrNull { it.isNotEmpty() && it.none { ch -> ch.isWhitespace() } }
            }
        }.getOrNull()

        /**
         * Exit IPv4 through SOCKS without a domain lookup. Xray has no DNS
         * config, so `ipv4.icanhazip.com` times out while a connect to
         * 1.1.1.1 still works.
         */
        data class ExitIp(val ip: String?, val reason: String)

        /** Exit IPv4 via the same SOCKS CONNECT to 1.1.1.1:443 that already succeeds. */
        fun socksExitIpByIpv4(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): ExitIp = try {
            Socket().use { plain ->
                plain.soTimeout = timeoutMs
                plain.connect(InetSocketAddress(socksHost, socksPort), timeoutMs)
                val out = DataOutputStream(plain.getOutputStream())
                val inp = DataInputStream(plain.getInputStream())
                socks5Greeting(out, inp)
                socks5ConnectIpv4(out, inp, "1.1.1.1", 443)
                val ssl = probeTls(plain)
                try {
                    ssl.soTimeout = timeoutMs
                    ssl.startHandshake()
                    val writer = ssl.getOutputStream()
                    writer.write(
                        (
                            "GET /cdn-cgi/trace HTTP/1.0\r\n" +
                                "Host: 1.1.1.1\r\nConnection: close\r\n\r\n"
                            ).toByteArray(StandardCharsets.US_ASCII),
                    )
                    writer.flush()
                    val text = ssl.getInputStream().readBytes()
                        .toString(StandardCharsets.US_ASCII)
                    val ip = Regex("""(?m)^ip=(\d{1,3}(?:\.\d{1,3}){3})\s*$""")
                        .find(text)
                        ?.groupValues
                        ?.getOrNull(1)
                    if (ip.isNullOrBlank()) {
                        ExitIp(null, "no_ip")
                    } else {
                        ExitIp(ip, "")
                    }
                } finally {
                    runCatching { ssl.close() }
                }
            }
        } catch (e: Exception) {
            ExitIp(null, "${e.javaClass.simpleName}=${e.message ?: "err"}")
        }

        fun socksHttpOk(
            socksHost: String = GvisorTun2Socks.SOCKS_HOST,
            socksPort: Int = GvisorTun2Socks.SOCKS_PORT,
            timeoutMs: Int = PROBE_TIMEOUT_MS,
        ): Boolean = socksHttpProbe(socksHost, socksPort, timeoutMs).isOk

        /**
         * HTTP generate_204 via TUN (no protect). IPv4 :80 then domain :80.
         */
        fun tunHttpOk(timeoutMs: Int = PROBE_TIMEOUT_MS): Boolean {
            if (tunHttpOnce(PROBE_HOST, PROBE_HTTP_PORT, PROBE_HTTPS_HOST, timeoutMs)) {
                return true
            }
            return tunHttpOnce(PROBE_HTTPS_HOST, PROBE_HTTP_PORT, PROBE_HTTPS_HOST, timeoutMs)
        }

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
                                "User-Agent: ProxyDomProbe/1\r\n" +
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

        /**
         * HTTPS generate_204 via the process default route (TUN when VPN is up).
         * Do not [android.net.VpnService.protect] this socket.
         */
        fun tunHttpsOk(timeoutMs: Int = PROBE_TIMEOUT_MS): Boolean =
            runCatching {
                val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
                (factory.createSocket() as SSLSocket).use { ssl ->
                    ssl.soTimeout = timeoutMs
                    ssl.connect(
                        InetSocketAddress(PROBE_HTTPS_HOST, PROBE_PORT),
                        timeoutMs,
                    )
                    ssl.startHandshake()
                    val out = ssl.outputStream
                    val req = "GET $PROBE_HTTPS_PATH HTTP/1.1\r\n" +
                        "Host: $PROBE_HTTPS_HOST\r\n" +
                        "Connection: close\r\n\r\n"
                    out.write(req.toByteArray(StandardCharsets.US_ASCII))
                    out.flush()
                    val line = BufferedReader(
                        InputStreamReader(ssl.inputStream, StandardCharsets.US_ASCII),
                    ).readLine() ?: return@runCatching false
                    val code = parseHttpStatusCode(line) ?: return@runCatching false
                    code in 200..399
                }
            }.getOrDefault(false)

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

        private fun probeTraceLiteral(
            socksHost: String,
            socksPort: Int,
            timeoutMs: Int,
        ): HttpProbeSample {
            val target = "1.1.1.1:443"
            return try {
                Socket().use { plain ->
                    plain.soTimeout = timeoutMs
                    plain.connect(InetSocketAddress(socksHost, socksPort), timeoutMs)
                    val out = DataOutputStream(plain.getOutputStream())
                    val inp = DataInputStream(plain.getInputStream())
                    socks5Greeting(out, inp)
                    socks5ConnectIpv4(out, inp, "1.1.1.1", 443)
                    try {
                        val ssl = probeTls(plain, "1.1.1.1", 443)
                        ssl.soTimeout = timeoutMs
                        ssl.startHandshake()
                        val writer = ssl.getOutputStream()
                        writer.write(
                            (
                                "GET /cdn-cgi/trace HTTP/1.0\r\n" +
                                    "Host: 1.1.1.1\r\nConnection: close\r\n\r\n"
                                ).toByteArray(StandardCharsets.US_ASCII),
                        )
                        writer.flush()
                        val text = ssl.getInputStream().readBytes()
                            .toString(StandardCharsets.US_ASCII)
                        runCatching { ssl.close() }
                        val status = text.lineSequence().firstOrNull()?.let(::parseHttpStatusCode)
                        val ip = Regex("""(?m)^ip=(\d{1,3}(?:\.\d{1,3}){3})\s*$""")
                            .find(text)
                            ?.groupValues
                            ?.getOrNull(1)
                        HttpProbeSample(
                            target = target,
                            tcp = true,
                            httpStatus = status,
                            exitIp = ip,
                            detail = "http=${status ?: "none"}",
                        )
                    } catch (e: Exception) {
                        HttpProbeSample(
                            target = target,
                            tcp = true,
                            httpStatus = null,
                            exitIp = null,
                            detail = "${e.javaClass.simpleName}=${e.message ?: "err"}",
                        )
                    }
                }
            } catch (e: Exception) {
                HttpProbeSample(
                    target = target,
                    tcp = false,
                    httpStatus = null,
                    exitIp = null,
                    detail = "${e.javaClass.simpleName}=${e.message ?: "err"}",
                )
            }
        }

        private fun probeGenerate204Literal(
            socksHost: String,
            socksPort: Int,
            timeoutMs: Int,
            name: String,
            port: Int,
            tls: Boolean,
        ): HttpProbeSample {
            val target = "$name:$port"
            val literal = resolveIpv4(name)
            if (literal == null) {
                return HttpProbeSample(
                    target = target,
                    tcp = false,
                    httpStatus = null,
                    exitIp = null,
                    detail = "dns",
                )
            }
            return try {
                Socket().use { plain ->
                    plain.soTimeout = timeoutMs
                    plain.connect(InetSocketAddress(socksHost, socksPort), timeoutMs)
                    val out = DataOutputStream(plain.getOutputStream())
                    val inp = DataInputStream(plain.getInputStream())
                    socks5Greeting(out, inp)
                    socks5ConnectIpv4(out, inp, literal, port)
                    try {
                        val status = if (tls) {
                            val ssl = probeTls(plain, name, port)
                            ssl.soTimeout = timeoutMs
                            ssl.startHandshake()
                            val code = httpGenerate204(ssl, name)
                            runCatching { ssl.close() }
                            code
                        } else {
                            httpGenerate204(plain, name)
                        }
                        val http = (status as? SocksHttpsResult.Ok)?.code
                        HttpProbeSample(
                            target = target,
                            tcp = true,
                            httpStatus = http,
                            exitIp = null,
                            detail = status.detail,
                        )
                    } catch (e: Exception) {
                        HttpProbeSample(
                            target = target,
                            tcp = true,
                            httpStatus = null,
                            exitIp = null,
                            detail = "${e.javaClass.simpleName}=${e.message ?: "err"}",
                        )
                    }
                }
            } catch (e: Exception) {
                HttpProbeSample(
                    target = target,
                    tcp = false,
                    httpStatus = null,
                    exitIp = null,
                    detail = "${e.javaClass.simpleName}=${e.message ?: "err"}",
                )
            }
        }

        private fun resolveIpv4(name: String): String? = runCatching {
            InetAddress.getAllByName(name)
                .firstOrNull { it is Inet4Address }
                ?.hostAddress
        }.getOrNull()

        private fun probeTls(plain: Socket, host: String = "1.1.1.1", port: Int = 443): SSLSocket {
            val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = Unit
                override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) = Unit
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            })
            val context = SSLContext.getInstance("TLS")
            context.init(null, trustAll, SecureRandom())
            val ssl = context.socketFactory.createSocket(plain, host, port, true) as SSLSocket
            val params = ssl.sslParameters
            params.endpointIdentificationAlgorithm = null
            ssl.sslParameters = params
            return ssl
        }

        private fun socks5ConnectIpv4(
            out: DataOutputStream,
            inp: DataInputStream,
            destHost: String,
            destPort: Int,
        ) {
            val addr = InetAddress.getByName(destHost).address
            require(addr.size == 4) { "IPv4 probe only" }
            out.writeByte(0x05)
            out.writeByte(0x01)
            out.writeByte(0x00)
            out.writeByte(0x01)
            out.write(addr)
            out.writeShort(destPort)
            out.flush()
            socks5ReadConnectReply(inp)
        }

        private fun socksHttpAfterConnect(
            socksHost: String,
            socksPort: Int,
            timeoutMs: Int,
            connect: (DataOutputStream, DataInputStream) -> Unit,
            hostHeader: String,
        ): SocksHttpsResult =
            try {
                Socket().use { socket ->
                    socket.soTimeout = timeoutMs
                    socket.connect(InetSocketAddress(socksHost, socksPort), timeoutMs)
                    val out = DataOutputStream(socket.getOutputStream())
                    val inp = DataInputStream(socket.getInputStream())
                    socks5Greeting(out, inp)
                    connect(out, inp)
                    httpGenerate204(socket, hostHeader)
                }
            } catch (e: SocketTimeoutException) {
                SocksHttpsResult.Fail("timeout=${e.message ?: "read"}")
            } catch (e: Exception) {
                SocksHttpsResult.Fail("${e.javaClass.simpleName}=${e.message ?: "err"}")
            }

        private fun tunHttpOnce(
            connectHost: String,
            port: Int,
            hostHeader: String,
            timeoutMs: Int,
        ): Boolean =
            runCatching {
                Socket().use { socket ->
                    socket.soTimeout = timeoutMs
                    socket.connect(InetSocketAddress(connectHost, port), timeoutMs)
                    httpGenerate204(socket, hostHeader).isOk
                }
            }.getOrDefault(false)

        private fun httpGenerate204(socket: Socket, hostHeader: String): SocksHttpsResult {
            val request =
                "GET $PROBE_HTTPS_PATH HTTP/1.1\r\n" +
                    "Host: $hostHeader\r\n" +
                    "Connection: close\r\n" +
                    "User-Agent: ProxyDomProbe/1\r\n" +
                    "\r\n"
            socket.getOutputStream().write(request.toByteArray(StandardCharsets.US_ASCII))
            socket.getOutputStream().flush()
            val statusLine = BufferedReader(
                InputStreamReader(socket.getInputStream(), StandardCharsets.US_ASCII),
            ).readLine() ?: return SocksHttpsResult.Fail("empty_status")
            val code = parseHttpStatusCode(statusLine)
                ?: return SocksHttpsResult.Fail("bad_status=$statusLine")
            return if (code in 200..299) {
                SocksHttpsResult.Ok(code)
            } else {
                SocksHttpsResult.Fail("code=$code")
            }
        }

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
                    NativeLog.i(TAG, "ping monitor started (SOCKS CONNECT RTT, then TUN TCP)")
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
                    NativeLog.i(TAG, "ping monitor stopped")
                },
                "proxydom-ping-monitor",
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
            NativeLog.i(TAG, "ping sample path=${sample.path} ${sample.ms}ms")
            runCatching { onSample(sample.ms) }
                .onFailure { NativeLog.w(TAG, "onSample failed: ${it.message}") }
            return
        }

        val fails = consecutiveFails.incrementAndGet()
        NativeLog.i(TAG, "ping sample failed consecutive=$fails")
        if (fails >= FAIL_CLEAR_THRESHOLD) {
            NativeLog.i(TAG, "ping cleared after $fails consecutive failures")
            runCatching { onSample(null) }
                .onFailure { NativeLog.w(TAG, "onSample(null) failed: ${it.message}") }
        }
    }

    private data class Sample(val ms: Int, val path: String)

    private fun measureSample(): Sample? {
        if (isSocksReachable()) {
            val connectMs = socks5ConnectRttMs()
            if (connectMs == null) {
                NativeLog.i(TAG, "SOCKS CONNECT failed")
            } else {
                DiagnosticRing.event("debug", "net.path", "ok=true")
                val clamped = clampDelayMs(connectMs) ?: return null
                return Sample(clamped, "socks5")
            }
        } else {
            NativeLog.i(TAG, "SOCKS unreachable — trying TUN TCP")
        }

        val tunMs = tcpConnectRttMs() ?: return null
        val clamped = clampDelayMs(tunMs) ?: return null
        return Sample(clamped, "tun-tcp")
    }
}
