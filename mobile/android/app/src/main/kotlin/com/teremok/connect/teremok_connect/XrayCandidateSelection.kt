package com.teremok.connect.teremok_connect

/**
 * One Xray JSON document ready for [XrayBridge.start], plus host metadata for
 * probes / UI. Parsed from MethodChannel `xrayCandidateConfigs`.
 */
data class XrayRuntimeCandidate(
    val id: String,
    val host: String,
    val label: String,
    val configJson: String,
)

/** Nest: probe only the primary candidate (ADR 005 soft failover budget). */
const val AUTO_CANDIDATE_LIMIT = 1

const val XRAY_SOCKS_PROBE_TIMEOUT_MS = 4_000
const val XRAY_SOCKS_PROBE_ATTEMPTS = 3
/** Inter-attempt pause after SOCKS not-ready / HTTPS fail. */
const val XRAY_SOCKS_PROBE_RETRY_SLEEP_MS = 150L
/** Max time spent polling SOCKS accept readiness before first HTTPS probe. */
const val XRAY_SOCKS_WARMUP_BUDGET_MS = 400L
const val XRAY_SOCKS_WARMUP_POLL_MS = 200

/**
 * Probe order for nest. [autoSelect] is retained for the MethodChannel contract;
 * both paths take at most [AUTO_CANDIDATE_LIMIT].
 */
fun candidateProbeOrder(
    candidates: List<XrayRuntimeCandidate>,
    autoSelect: Boolean,
): List<XrayRuntimeCandidate> =
    candidates.take(AUTO_CANDIDATE_LIMIT)

/** Prefer the lowest measured latency among successful probes. */
fun fastestCandidate(
    successful: List<Pair<XrayRuntimeCandidate, Long>>,
): Pair<XrayRuntimeCandidate, Long>? =
    successful.minByOrNull { it.second }

/** Dual-core switch (ADR 006): exact string `"trusttunnel"` only. */
internal fun isTrustTunnelCore(params: Map<String, Any?>): Boolean =
    params["vpnCore"] == TeremokVpnService.VPN_CORE_TRUSTTUNNEL

/** Parse `xrayCandidateConfigs` from paramsJson (List of maps). */
internal fun runtimeCandidates(params: Map<String, Any?>): List<XrayRuntimeCandidate> {
    val raw = params["xrayCandidateConfigs"] as? List<*> ?: return emptyList()
    return raw.mapNotNull { item ->
        val map = item as? Map<*, *> ?: return@mapNotNull null
        val id = (map["id"] as? String)?.trim().orEmpty()
        val host = (map["host"] as? String)?.trim().orEmpty()
        val label = (map["label"] as? String)?.trim().orEmpty().ifEmpty { id }
        val configJson = (map["configJson"] as? String)?.trim().orEmpty()
        if (id.isEmpty() || host.isEmpty() || configJson.isEmpty()) return@mapNotNull null
        XrayRuntimeCandidate(id = id, host = host, label = label, configJson = configJson)
    }
}
