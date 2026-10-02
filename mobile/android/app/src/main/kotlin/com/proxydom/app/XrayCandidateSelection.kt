package com.teremok.connect.teremok_connect

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

/** Hy2 core switch (ADR 018): exact string `"hysteria"` only. */
internal fun isHysteriaCore(params: Map<String, Any?>): Boolean =
    params["vpnCore"] == TeremokVpnService.VPN_CORE_HYSTERIA

/** Pasted non-Hy2 profile. Same gomobile runtime as Hy2 (ADR 026). */
internal fun isXrayShareCore(params: Map<String, Any?>): Boolean =
    params["vpnCore"] == "xray"
