package com.proxydom.app

/**
 * Local SOCKS listen used by official Hy2 (`hysteriaSocksListen`) and PathHealth
 * HTTPS probes. TUN is pumped inside hy2bind, not libXray.
 */
object GvisorTun2Socks {
    const val SOCKS_HOST = "127.0.0.1"
    const val SOCKS_PORT = 10808
}
