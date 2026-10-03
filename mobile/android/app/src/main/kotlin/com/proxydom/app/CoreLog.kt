package com.proxydom.app

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * Directory and level for the Go core log. The share document already travels
 * into [hy2bind.Hy2bind.startShare]; these two fields ride along so the AAR
 * does not need a new export.
 */
internal object CoreLog {
    private const val flutterPrefs = "FlutterSharedPreferences"
    private const val flutterLevelKey = "flutter.tunnel_log_level"

    @Volatile
    var override: String? = null

    fun resolve(context: Context): String {
        override?.let { return normalize(it) }
        val stored = context
            .getSharedPreferences(flutterPrefs, Context.MODE_PRIVATE)
            .getString(flutterLevelKey, null)
        return normalize(stored)
    }

    fun enrich(context: Context, configJson: String): String {
        return try {
            val obj = JSONObject(configJson)
            val dir = File(context.filesDir, "xray")
            dir.mkdirs()
            obj.put("proxydomLogDir", dir.absolutePath)
            obj.put("proxydomLogLevel", resolve(context))
            obj.toString()
        } catch (_: Exception) {
            configJson
        }
    }

    fun readTail(context: Context, maxLines: Int): String {
        val dir = File(context.filesDir, "xray")
        val lines = ArrayList<String>()
        for (name in listOf("core.1.log", "core.log")) {
            val file = File(dir, name)
            if (!file.exists()) continue
            val chunk = runCatching { file.readLines() }.getOrDefault(emptyList())
            lines.addAll(chunk)
        }
        if (lines.isEmpty() || maxLines <= 0) return ""
        return lines.takeLast(maxLines).joinToString("\n")
    }

    fun clear(context: Context) {
        val dir = File(context.filesDir, "xray")
        File(dir, "core.log").delete()
        File(dir, "core.1.log").delete()
    }

    private fun normalize(raw: String?): String {
        return when (raw) {
            "off", "error", "warn", "info", "debug" -> raw
            else -> "info"
        }
    }
}
