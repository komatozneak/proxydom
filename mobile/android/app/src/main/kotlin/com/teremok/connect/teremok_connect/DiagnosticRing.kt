package com.teremok.connect.teremok_connect

/**
 * Short in-process ring for owner diagnostic reports.
 *
 * Captures TeremokVpn / VpnSessionEngine / PathHealth / HysteriaBridge
 * lines without tokens or Hy2 auth. Survives until process death; Dart
 * [AppLogBuffer] persists the product events across kills.
 */
internal object DiagnosticRing {
    const val MAX_LINES = 400

    private val lock = Any()
    private val lines = ArrayDeque<String>(MAX_LINES + 1)

    fun append(tag: String, message: String) {
        val line = "${System.currentTimeMillis()} ${redact("$tag $message")}"
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

    /** Strip secrets so reports can go to Telegram. */
    fun redact(message: String): String {
        var out = message
        out = AUTH_KV.replace(out, "$1=***")
        out = BEARER.replace(out, "Bearer ***")
        out = UUID_TOKEN.replace(out, "***")
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
