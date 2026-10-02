package com.teremok.connect.teremok_connect

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Short in-process ring for owner diagnostic reports.
 *
 * Same line as the Dart buffer: millisecond UTC, level, source, event.
 * Survives until process death; Dart [AppLogBuffer] persists product events.
 */
internal object DiagnosticRing {
    const val MAX_LINES = 400

    private val lock = Any()
    private val lines = ArrayDeque<String>(MAX_LINES + 1)
    private val stamp: DateTimeFormatter = DateTimeFormatter
        .ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
        .withZone(ZoneOffset.UTC)
    private val ipv4 = Regex(
        """\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b""",
    )

    fun event(
        level: String,
        event: String,
        fields: String = "",
        nowMs: Long = System.currentTimeMillis(),
    ) {
        val source = event.substringBefore('.', "app")
        val body = if (fields.isBlank()) event else "$event ${fields.trim()}"
        val line = "${stamp.format(Instant.ofEpochMilli(nowMs))} [$level] [$source] ${redact(body)}"
        synchronized(lock) {
            lines.addLast(line)
            while (lines.size > MAX_LINES) {
                lines.removeFirst()
            }
        }
    }

    fun tail(maxLines: Int = MAX_LINES): String {
        val n = maxLines.coerceAtLeast(0)
        synchronized(lock) {
            if (lines.isEmpty() || n == 0) return ""
            return lines.toList().takeLast(n).joinToString("\n")
        }
    }

    fun clear() {
        synchronized(lock) { lines.clear() }
    }

    /** Strip secrets and node addresses so reports can leave the phone. */
    fun redact(message: String): String {
        var out = message
        out = AUTH_KV.replace(out, "$1=***")
        out = BEARER.replace(out, "Bearer ***")
        out = UUID_TOKEN.replace(out, "***")
        out = ipv4.replace(out) { match ->
            val parts = match.value.split('.')
            "${parts[0]}.${parts[1]}.***.***"
        }
        return out
    }

    private val AUTH_KV =
        Regex(
            "(?i)\\b(auth|token|password|secret|hysteriaAuth|authorization)\\s*[=:]\\s*\\S+",
        )
    private val BEARER = Regex("(?i)\\bBearer\\s+\\S+")
    private val UUID_TOKEN =
        Regex(
            "(?i)(hysteriaAuth|auth)\\s*[=:]\\s*[0-9a-f-]{8,}",
        )
}
