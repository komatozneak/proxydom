package com.proxydom.app

import android.util.Log

/**
 * One logging call for the whole native layer.
 *
 * Why this exists: the native code used to have two sinks with two different
 * rules. `android.util.Log` went to logcat only — unredacted, and invisible to
 * the person who taps «Настройки → Журнал → Отправить отчёт». [DiagnosticRing]
 * was the other sink, and only ~20 call sites of ~170 wrote to it. So the report
 * a user actually sent told a *different* story from the logcat a developer read,
 * and the lines that explained the failure were usually the ones left behind.
 *
 * Now a single call writes both, redacts once, and the ring honours the level
 * the user picked in the log screen. `NativeLog.i(TAG, …)` becomes `NativeLog.i(TAG, …)`.
 *
 * Prefer [event] over the level helpers for anything that carries product
 * meaning: the event name is stable and greppable, the fields are typed, and a
 * future reader can count occurrences. The level helpers keep free text for
 * trace-level detail that no report should have to explain.
 */
internal object NativeLog {

    /**
     * Logcat is a developer channel. A release build still writes the
     * user-facing [DiagnosticRing] (a local file the person can send), but it
     * must not spray node addresses, subscription hosts or config structure
     * into a system log another process may read.
     */
    private val logcatEnabled = BuildConfig.DEBUG

    /** Level the user chose in the log screen. Written by the MethodChannel. */
    @Volatile
    var level: String = "info"

    /**
     * Dart session id ([ShareSessionLog.nextSid]) for the attempt in flight.
     * Set by Flutter before `start`, cleared on stop. Without it a native line
     * cannot be joined to the `vpn.phase` timeline in the same report.
     */
    @Volatile
    var sessionId: String? = null

    /**
     * Debug lines reach logcat only when the user picked `debug` in the log
     * screen, the same rule the ring follows. A release build used to print
     * every one of them — a path probe every five seconds for the whole
     * session — into a log nobody reads without adb.
     */
    fun d(tag: String, message: String, error: Throwable? = null) {
        if (level == "debug" && logcatEnabled) Log.d(tag, message, error)
        mirror("debug", tag, message, error)
    }

    fun i(tag: String, message: String, error: Throwable? = null) {
        if (logcatEnabled) Log.i(tag, message, error)
        mirror("info", tag, message, error)
    }

    fun w(tag: String, message: String, error: Throwable? = null) {
        if (logcatEnabled) Log.w(tag, message, error)
        mirror("warn", tag, message, error)
    }

    fun e(tag: String, message: String, error: Throwable? = null) {
        if (logcatEnabled) Log.e(tag, message, error)
        mirror("error", tag, message, error)
    }

    /**
     * Structured line: stable [name], `key=value` [fields], both greppable.
     *
     * [name] is `source.action`, lowercase, dot-separated — the log screen and
     * any future counting depend on that shape. `DiagnosticRing` takes the
     * source token from the part before the first dot.
     */
    fun event(level: String, name: String, fields: String = "") {
        if (!allows(level)) return
        DiagnosticRing.event(level, name, withSession(fields))
    }

    /** Append the stack to the ring when the throwable carries one. */
    private fun mirror(level: String, tag: String, message: String, error: Throwable?) {
        if (!allows(level)) return
        val body = if (error == null) message else "$message: ${error.javaClass.simpleName}"
        // `${camelTag(...)}` and not `$camelTag(...)`: inside a Kotlin template a
        // bare `$name` is a field read, and the compiler asks for the call.
        DiagnosticRing.event(level, "${sourceFor(tag)}.${camelTag(tag)}", withSession(body))
    }

    private fun withSession(fields: String): String {
        val sid = sessionId ?: return fields
        return if (fields.isBlank()) "sid=$sid" else "sid=$sid $fields"
    }

    private fun allows(level: String): Boolean = when (level) {
        "debug" -> selected() == "debug"
        "info" -> selected() == "info" || selected() == "debug"
        "warn" -> selected() != "error" && selected() != "off"
        "error" -> selected() != "off"
        else -> true
    }

    private fun selected(): String = level

    /**
     * Log screen group for [tag]. The viewer filters on `[vpn]`, `[net]`,
     * `[hy2]`, so native lines stay reachable from the chips users already know.
     */
    private fun sourceFor(tag: String): String = when {
        tag.startsWith("Hysteria") -> "hy2"
        tag.contains("Network") || tag.contains("Bind") || tag.contains("Ping") -> "net"
        tag.contains("Vpn") || tag.contains("Tunnel") || tag.contains("Path") -> "vpn"
        tag.contains("Core") -> "core"
        else -> "app"
    }

    /** `ProxyDomVpnService` → `ProxyDomVpnService` (kept: tags are already stable). */
    private fun camelTag(tag: String): String = tag.ifBlank { "app" }
}