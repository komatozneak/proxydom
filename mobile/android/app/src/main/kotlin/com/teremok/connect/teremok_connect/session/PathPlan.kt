package com.teremok.connect.teremok_connect.session

import android.net.Network

/**
 * First-class path for one establish/replan (ADR 014 PathPlan).
 * Transport is derived from the bound iface — LTE-only is a valid plan.
 */
enum class PathTransport {
    Wifi,
    Cellular,
    Unknown,
    ;

    fun toWire(): String = when (this) {
        Wifi -> "wifi"
        Cellular -> "cellular"
        Unknown -> "unknown"
    }

    companion object {
        fun fromIface(iface: String?): PathTransport {
            if (iface.isNullOrBlank()) return Unknown
            val lower = iface.lowercase()
            return when {
                lower.startsWith("wlan") || lower.startsWith("wifi") -> Wifi
                lower.startsWith("rmnet") ||
                    lower.startsWith("ccmni") ||
                    lower.startsWith("wwan") ||
                    lower.startsWith("pdp") ||
                    lower.startsWith("ncm") -> Cellular
                else -> Unknown
            }
        }

        fun fromWire(raw: String?): PathTransport = when (raw?.lowercase()) {
            "wifi" -> Wifi
            "cellular" -> Cellular
            else -> Unknown
        }
    }
}

data class PathPlan(
    val generation: Long,
    val transport: PathTransport,
    val interfaceName: String,
    val network: Network,
    val candidateId: String?,
    val candidateHost: String?,
    val core: String,
    /** True after one Engine-owned replan for this generation. */
    val replanUsed: Boolean = false,
) {
    fun withReplanUsed(): PathPlan = copy(replanUsed = true)

    fun sameTransportClass(otherIface: String?): Boolean =
        transport == PathTransport.fromIface(otherIface)
}
