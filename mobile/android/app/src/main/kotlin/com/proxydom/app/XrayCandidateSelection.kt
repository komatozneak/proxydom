package com.proxydom.app

/**
 * Dummy SOCKS HTTPS probe DTO for Hy2 PathHealth (not a live Xray document).
 */
data class SocksProbeCandidate(
    val id: String,
    val host: String,
    val label: String,
    val configJson: String,
)

/** Nest: probe only the primary candidate. */
const val AUTO_CANDIDATE_LIMIT = 1

const val XRAY_SOCKS_PROBE_TIMEOUT_MS = 1_000
const val XRAY_SOCKS_PROBE_ATTEMPTS = 2
const val XRAY_SOCKS_PROBE_RETRY_SLEEP_MS = 150L
const val XRAY_SOCKS_WARMUP_BUDGET_MS = 300L
const val XRAY_SOCKS_WARMUP_POLL_MS = 200

fun socksHttpsProbeBudgetMs(): Long =
    XRAY_SOCKS_WARMUP_BUDGET_MS +
        XRAY_SOCKS_PROBE_ATTEMPTS.toLong() *
        (XRAY_SOCKS_PROBE_TIMEOUT_MS + XRAY_SOCKS_PROBE_RETRY_SLEEP_MS + 800L)

fun candidateProbeOrder(
    candidates: List<SocksProbeCandidate>,
    autoSelect: Boolean,
): List<SocksProbeCandidate> =
    candidates.take(AUTO_CANDIDATE_LIMIT)

fun fastestCandidate(
    successful: List<Pair<SocksProbeCandidate, Long>>,
): Pair<SocksProbeCandidate, Long>? =
    successful.minByOrNull { it.second }

/** Hy2 core switch: exact string `"hysteria"` only. */
internal fun isHysteriaCore(params: Map<String, Any?>): Boolean =
    params["vpnCore"] == ProxyDomVpnService.VPN_CORE_HYSTERIA

/** Pasted non-Hy2 profile. Same gomobile runtime as Hy2. */
internal fun isVlessShareCore(params: Map<String, Any?>): Boolean =
    params["vpnCore"] == "vless"

private val legacyShareServer =
    Regex(""""address"\s*:\s*"([^"]+)"\s*,\s*"port"\s*:\s*(\d+)""")

/**
 * The share node, for the route bypass and the reach probe.
 *
 * Dart sends it as `shareServerHost`/`shareServerPort`. A session persisted by
 * an older build has only the v2ray document, whose first `address`/`port`
 * pair is the node; a REALITY document has no such pair, which is why the
 * explicit fields exist. Returns `"" to 0` when neither is there.
 */
internal fun shareServerOf(params: Map<String, Any?>): Pair<String, Int> {
    val host = (params["shareServerHost"] as? String)?.trim().orEmpty()
    val port = (params["shareServerPort"] as? Number)?.toInt() ?: 0
    if (host.isNotEmpty() && port in 1..65535) return host to port
    val config = (params["vlessConfig"] as? String).orEmpty()
    val match = legacyShareServer.find(config) ?: return "" to 0
    return match.groupValues[1] to (match.groupValues[2].toIntOrNull() ?: 0)
}
