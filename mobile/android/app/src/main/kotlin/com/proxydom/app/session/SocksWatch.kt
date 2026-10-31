package com.proxydom.app.session

import com.proxydom.app.GvisorTun2Socks
import com.proxydom.app.isHysteriaCore
import com.proxydom.app.isVlessShareCore

/**
 * SOCKS inbound the path watch must probe for this session.
 *
 * Hy2 listens on [GvisorTun2Socks.SOCKS_PORT]. The VLESS share core listens on
 * [GvisorTun2Socks.SHARE_SOCKS_PORT] (Go `shareSocks`, Dart `shareSocksPort`).
 * An unknown core is null: callers must not substitute the Hy2 port.
 */
data class SocksWatch(
    val adapter: PathHealth.CoreAdapter,
    val port: Int,
)

fun hysteriaSocksListen(params: Map<String, Any?>): String {
    val raw = (params["hysteriaSocksListen"] as? String)?.trim().orEmpty()
    if (raw.isEmpty()) {
        return "${GvisorTun2Socks.SOCKS_HOST}:${GvisorTun2Socks.SOCKS_PORT}"
    }
    return raw
}

internal fun socksPortFromListen(listen: String): Int? {
    val raw = listen.substringAfterLast(':', missingDelimiterValue = "")
    val port = raw.toIntOrNull() ?: return null
    if (port !in 1..65535) return null
    return port
}

fun socksWatchFor(params: Map<String, Any?>): SocksWatch? {
    if (isVlessShareCore(params)) {
        // Both share engines (v2ray family and REALITY) listen here: only one
        // runs at a time.
        return SocksWatch(
            adapter = PathHealth.CoreAdapter.ShareSocks,
            port = GvisorTun2Socks.SHARE_SOCKS_PORT,
        )
    }
    if (!isHysteriaCore(params)) return null
    val port = socksPortFromListen(hysteriaSocksListen(params)) ?: return null
    return SocksWatch(
        adapter = PathHealth.CoreAdapter.HysteriaSocks,
        port = port,
    )
}
