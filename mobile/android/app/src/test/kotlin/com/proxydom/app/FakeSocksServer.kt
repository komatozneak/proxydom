package com.proxydom.app

import java.io.BufferedReader
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicInteger

/**
 * Minimal SOCKS5 listener for tests: greets, acks every CONNECT at once, then
 * answers HTTP requests with [statusLine] after [holdBackMs] — or closes the
 * stream without an answer when [statusLine] is null.
 *
 * The instant CONNECT ack mirrors the real core; that is exactly why a bare
 * CONNECT is not a latency sample. With [keepAlive] the connection serves one
 * answer per request and stays open, so a test can prove the probe reuses it.
 */
internal class FakeSocksServer(
    private val statusLine: String?,
    private val holdBackMs: Long,
    private val keepAlive: Boolean = false,
) : Closeable {
    private val server = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
    val port: Int = server.localPort

    /** How many TCP connections the probe opened; >1 means setup was repaid. */
    val connections = AtomicInteger(0)

    private val worker = Thread {
        while (!server.isClosed) {
            val client = runCatching { server.accept() }.getOrNull() ?: break
            connections.incrementAndGet()
            runCatching { serve(client) }
        }
    }.apply {
        isDaemon = true
        start()
    }

    private fun serve(client: Socket) {
        client.use { socket ->
            socket.soTimeout = 5_000
            val inp = DataInputStream(socket.getInputStream())
            val out = DataOutputStream(socket.getOutputStream())

            // Greeting: VER, NMETHODS, METHODS.
            inp.readUnsignedByte()
            repeat(inp.readUnsignedByte()) { inp.readUnsignedByte() }
            out.write(byteArrayOf(5, 0))
            out.flush()

            // CONNECT: VER, CMD, RSV, ATYP, ADDR, PORT. Acknowledge it at once.
            inp.readUnsignedByte()
            inp.readUnsignedByte()
            inp.readUnsignedByte()
            when (inp.readUnsignedByte()) {
                0x01 -> inp.skipBytes(4)
                0x03 -> inp.skipBytes(inp.readUnsignedByte())
                0x04 -> inp.skipBytes(16)
                else -> return
            }
            inp.skipBytes(2)
            out.write(byteArrayOf(5, 0, 0, 1, 0, 0, 0, 0, 0, 0))
            out.flush()

            val reader = BufferedReader(
                InputStreamReader(inp, StandardCharsets.US_ASCII),
            )
            do {
                // Request headers, up to the blank line.
                while (true) {
                    val line = reader.readLine() ?: return
                    if (line.isEmpty()) break
                }
                Thread.sleep(holdBackMs)
                val answer = statusLine ?: return
                out.write("$answer\r\n\r\n".toByteArray(StandardCharsets.US_ASCII))
                out.flush()
            } while (keepAlive)
        }
    }

    override fun close() {
        runCatching { server.close() }
        worker.join(1_000)
    }
}
