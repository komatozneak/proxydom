package com.proxydom.app

/**
 * Local SOCKS listen. Hy2 uses [SOCKS_PORT]. The VLESS share core uses
 * [SHARE_SOCKS_PORT]. TUN is pumped inside hy2bind, not libXray.
 */
object GvisorTun2Socks {
    const val SOCKS_HOST = "127.0.0.1"
    const val SOCKS_PORT = 10808

    /** VLESS share inbound. Go `shareSocks` and Dart `shareSocksPort`. */
    const val SHARE_SOCKS_PORT = 10809
}
