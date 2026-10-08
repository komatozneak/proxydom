package com.proxydom.app

/**
 * One SOCKS attempt. [tcp] means the proxy completed CONNECT. [exitIp] is
 * optional text from a trace body. Reading that IP is not required for [tcp].
 */
data class HttpProbeSample(
    val target: String,
    val tcp: Boolean,
    val httpStatus: Int?,
    val exitIp: String?,
    val detail: String,
)

/**
 * Connected requires [carriesData]. [exitIp] is filled only when a target
 * returned one. A missing IP is not a failed tunnel.
 */
data class TunnelAcceptance(
    val carriesData: Boolean,
    val exitIp: String?,
    val target: String?,
    val detail: String,
)

/**
 * First sample that completed SOCKS CONNECT wins. Later samples are not
 * required. No CONNECT at all is the only refusal.
 */
fun acceptTunnel(samples: List<HttpProbeSample>): TunnelAcceptance {
    val hit = samples.firstOrNull { it.tcp }
    if (hit != null) {
        val ip = hit.exitIp?.trim()?.takeIf { it.isNotEmpty() }
        return TunnelAcceptance(
            carriesData = true,
            exitIp = ip,
            target = hit.target,
            detail = "tcp=ok target=${hit.target} http=${hit.httpStatus ?: "none"}",
        )
    }
    val detail = if (samples.isEmpty()) {
        "no targets"
    } else {
        samples.joinToString(separator = "; ") { "${it.target}=${it.detail}" }
    }
    return TunnelAcceptance(
        carriesData = false,
        exitIp = null,
        target = null,
        detail = detail,
    )
}

/**
 * Same address as the carrier is a suspicion. It does not refuse the session.
 * A missing IP is unread, not a dead tunnel. Null means nothing to warn.
 */
fun egressIpWarn(exitIp: String?, carrierIp: String?): String? {
    val exit = exitIp?.trim().orEmpty()
    if (exit.isEmpty()) return "egress ip unread"
    val carrier = carrierIp?.trim().orEmpty()
    if (carrier.isNotEmpty() && exit == carrier) return "egress ip matches carrier"
    return null
}
