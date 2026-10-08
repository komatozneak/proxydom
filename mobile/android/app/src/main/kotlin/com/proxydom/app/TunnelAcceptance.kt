package com.proxydom.app

/**
 * One SOCKS attempt. [tcp] means the proxy completed CONNECT. That is not
 * proof the destination answered: Hy2 FastOpen returns the socket before the
 * server confirms it. A parsed [httpStatus] or a read [exitIp] is the answer.
 */
data class HttpProbeSample(
    val target: String,
    val tcp: Boolean,
    val httpStatus: Int?,
    val exitIp: String?,
    val detail: String,
)

/**
 * Connected requires [carriesData]: a parsed HTTP status or a read exit
 * address. A finished CONNECT alone is not enough. A missing IP is not a
 * failed tunnel when some sample still answered.
 */
data class TunnelAcceptance(
    val carriesData: Boolean,
    val exitIp: String?,
    val target: String?,
    val detail: String,
)

/**
 * First sample with a response wins. A response is any parsed HTTP status
 * or a non-blank [HttpProbeSample.exitIp]. CONNECT with neither is skipped.
 * No response from any sample is the refusal.
 */
fun acceptTunnel(samples: List<HttpProbeSample>): TunnelAcceptance {
    val hit = samples.firstOrNull { it.confirmsCarry() }
    if (hit != null) {
        val ip = hit.exitIp?.trim()?.takeIf { it.isNotEmpty() }
        return TunnelAcceptance(
            carriesData = true,
            exitIp = ip,
            target = hit.target,
            detail = "response target=${hit.target} http=${hit.httpStatus ?: "none"}",
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

/** A parsed status or a read address. A finished CONNECT is not this. */
fun HttpProbeSample.confirmsCarry(): Boolean =
    httpStatus != null || !exitIp.isNullOrBlank()

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
