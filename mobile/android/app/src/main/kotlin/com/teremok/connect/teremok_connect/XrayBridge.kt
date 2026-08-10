package com.teremok.connect.teremok_connect

import android.content.Context
import android.net.VpnService
import android.util.Base64
import android.util.Log
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import libXray.DialerController
import libXray.LibXray
import org.json.JSONObject

/**
 * Bridge to Xray-core via libXray gomobile AAR ([libXray.LibXray]).
 *
 * Pinned to libXray **26.6.27** (pre-`invoke` API): base64 request/response
 * wrappers — [LibXray.runXrayFromJSON], [LibXray.testXray], [LibXray.stopXray].
 * Newer CalVer clients (26.7+) often fail Reality against older Marzban with
 * `REALITY: received real certificate`.
 *
 * Android wiring (gVisor TUN — 2026-08-09 pivot):
 * - [LibXray.setTunFd] — VpnService TUN fd into Xray `protocol:tun` (gVisor).
 * - [LibXray.registerDialerController] — socket protect via [VpnService.protect].
 * - datDir via API for geosite/geoip.
 * - SOCKS `127.0.0.1:10808` remains for probes only (not the device path).
 * - Replaces hev-socks5-tunnel TUN→SOCKS hop.
 *
 * Reference: https://github.com/XTLS/libXray/tree/v26.6.27
 */
class XrayBridge private constructor() {

    companion object {
        private const val TAG = "XrayBridge"
        private const val WORK_DIR = "xray"

        @JvmStatic
        val instance: XrayBridge by lazy { XrayBridge() }
    }

    private var appContext: Context? = null
    private var vpnService: VpnService? = null
    /** Absolute path to dir with geosite.dat / geoip.dat (libXray datDir). */
    private var assetDir: String? = null
    private val isSetup = AtomicBoolean(false)
    private val isRunning = AtomicBoolean(false)

    @Volatile
    var lastErrorMessage: String? = null
        private set

    /** Socket protect callback for Xray dialer (keeps proxy conn out of TUN). */
    private val dialerController = object : DialerController {
        override fun protectFd(fd: Long): Boolean {
            val svc = vpnService
            if (svc == null) {
                Log.e(TAG, "protectFd($fd): VpnService not bound")
                ProtectGuard.reportFailure(fd.toInt())
                return false
            }
            val ok = try {
                svc.protect(fd.toInt())
            } catch (e: Exception) {
                Log.e(TAG, "protectFd($fd) threw", e)
                false
            }
            if (!ok) {
                Log.w(TAG, "protectFd($fd) failed")
                ProtectGuard.reportFailure(fd.toInt())
            } else {
                Log.d(TAG, "protectFd($fd) ok")
            }
            return ok
        }
    }

    /**
     * Set context. If [context] is [VpnService], save for socket protect.
     */
    fun bind(context: Context) {
        appContext = context.applicationContext
        if (context is VpnService) {
            vpnService = context
        }
        ensureSetup()
    }

    /**
     * Initialize libXray runtime (geo data, dialer controller, version check).
     */
    fun loadLibrary(): Boolean {
        val ctx = appContext
        if (ctx == null) {
            Log.e(TAG, "loadLibrary: bind() not called")
            return false
        }
        return try {
            ensureSetup()
            Log.i(TAG, "loadLibrary: Xray-core ${xrayVersion()} ready")
            true
        } catch (e: Exception) {
            Log.e(TAG, "loadLibrary: libXray setup failed", e)
            false
        }
    }

    /**
     * Start Xray with JSON config. Pass [tunFd] from VpnService for gVisor
     * `protocol:tun` (0 = no TUN attach — SOCKS-only probe configs).
     */
    fun start(xrayConfigJson: String, tunFd: Int = 0): Boolean {
        if (isRunning.get()) {
            Log.w(TAG, "start: already running")
            return false
        }
        if (appContext == null) {
            Log.e(TAG, "start: bind() not called")
            return false
        }

        return try {
            lastErrorMessage = null
            if (vpnService == null) {
                Log.e(TAG, "start: VpnService not bound — VLESS dial would loop")
                lastErrorMessage = "VpnService not bound for protect()"
                return false
            }
            LibXray.registerDialerController(dialerController)
            GvisorTun2Socks.attachTunFd(tunFd)

            val datDir = assetDir
            if (datDir.isNullOrBlank()) {
                lastErrorMessage = "assetDir not ready"
                Log.e(TAG, "start: $lastErrorMessage")
                return false
            }

            val cleanJson = stripNonCoreKeys(xrayConfigJson)

            val configFile = File(datDir, "config.json")
            configFile.writeText(cleanJson)

            val testResult = decodeResponse(
                LibXray.testXray(
                    encodeRequest(
                        JSONObject()
                            .put("datDir", datDir)
                            .put("configPath", configFile.absolutePath),
                    ),
                ),
            )
            if (!testResult.optBoolean("success")) {
                lastErrorMessage = testResult.optString("error").ifEmpty { "testXray failed" }
                Log.e(TAG, "start: config invalid: $lastErrorMessage")
                return false
            }

            val runB64 = try {
                LibXray.newXrayRunFromJSONRequest(datDir, cleanJson)
            } catch (e: Exception) {
                lastErrorMessage = e.message ?: "newXrayRunFromJSONRequest failed"
                Log.e(TAG, "start: $lastErrorMessage", e)
                return false
            }

            val runResult = decodeResponse(LibXray.runXrayFromJSON(runB64))
            if (!runResult.optBoolean("success")) {
                lastErrorMessage = runResult.optString("error").ifEmpty { "runXrayFromJSON failed" }
                Log.e(TAG, "start: run failed: $lastErrorMessage")
                return false
            }

            isRunning.set(true)
            Log.i(
                TAG,
                "start: Xray-core started (${xrayVersion()}) tunFd=$tunFd",
            )
            true
        } catch (e: Exception) {
            lastErrorMessage = e.message ?: e.toString()
            Log.e(TAG, "start: failed", e)
            isRunning.set(false)
            false
        }
    }

    /**
     * Stop Xray instance.
     */
    fun stop() {
        if (!isRunning.get()) return
        try {
            Log.i(TAG, "stop: stopping Xray")
            val result = decodeResponse(LibXray.stopXray())
            if (!result.optBoolean("success")) {
                Log.w(TAG, "stop: ${result.optString("error")}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "stop: error", e)
        } finally {
            GvisorTun2Socks.attachTunFd(0)
            isRunning.set(false)
        }
    }

    /** Xray-core version string. */
    fun xrayVersion(): String {
        return try {
            val result = decodeResponse(LibXray.xrayVersion())
            when (val data = result.opt("data")) {
                is String -> data.ifEmpty { "unknown" }
                is JSONObject -> data.optString("version").ifEmpty {
                    data.optString("Version").ifEmpty { "unknown" }
                }
                else -> "unknown"
            }
        } catch (e: Exception) {
            Log.w(TAG, "xrayVersion failed", e)
            "unknown"
        }
    }

    /** True while managed Xray instance is running. */
    fun isRunning(): Boolean = isRunning.get()

    // ── Internal ────────────────────────────────────────────────

    private fun ensureSetup() {
        if (isSetup.get()) return
        val ctx = appContext ?: error("XrayBridge.bind(context) must be called first")

        val workingPath = File(ctx.filesDir, WORK_DIR).apply { mkdirs() }
        assetDir = workingPath.absolutePath
        copyAssetIfNeeded(ctx, "geoip.dat", workingPath)
        copyAssetIfNeeded(ctx, "geosite.dat", workingPath)

        // Touch LibXray (loads libgojni.so via go.Seq) then register protect.
        LibXray.touch()
        LibXray.registerDialerController(dialerController)

        isSetup.set(true)
        Log.i(TAG, "ensureSetup: Xray-core ${xrayVersion()} assets=$assetDir")
    }

    private fun copyAssetIfNeeded(ctx: Context, name: String, destDir: File) {
        val dest = File(destDir, name)
        val assetLen = try {
            ctx.assets.openFd(name).use { it.length }
        } catch (_: Exception) {
            // Compressed assets may not support openFd — fall through to stream copy.
            -1L
        }
        // Refresh when missing OR size differs (old Огонь dat lacked tld-ru → EOF on start).
        if (dest.exists() && assetLen > 0 && dest.length() == assetLen) return
        if (dest.exists() && assetLen < 0 && dest.length() > 0) {
            // Cannot compare sizes — overwrite once per process after APK update by
            // deleting when marker version mismatches.
            val marker = File(destDir, "$name.ver")
            val expected = "loyalsoldier-2026-08-08"
            if (marker.exists() && marker.readText().trim() == expected) return
        }
        try {
            ctx.assets.open(name).use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
            File(destDir, "$name.ver").writeText("loyalsoldier-2026-08-08")
            Log.i(TAG, "copied $name → ${dest.absolutePath} (${dest.length()} bytes)")
        } catch (e: Exception) {
            Log.w(TAG, "copyAssetIfNeeded($name) failed: ${e.message}")
        }
    }

    /**
     * Remove keys that libXray 26.7+ `invoke` understood but raw Xray-core rejects.
     */
    private fun stripNonCoreKeys(configJson: String): String {
        return try {
            val root = JSONObject(configJson)
            root.remove("env")
            root.toString()
        } catch (e: Exception) {
            Log.w(TAG, "stripNonCoreKeys failed, passing raw config: ${e.message}")
            configJson
        }
    }

    private fun encodeRequest(payload: JSONObject): String {
        return Base64.encodeToString(
            payload.toString().toByteArray(Charsets.UTF_8),
            Base64.NO_WRAP,
        )
    }

    private fun decodeResponse(base64Text: String): JSONObject {
        return try {
            val raw = String(Base64.decode(base64Text, Base64.DEFAULT), Charsets.UTF_8)
            JSONObject(raw)
        } catch (e: Exception) {
            JSONObject().apply {
                put("success", false)
                put("error", "invalid response: ${e.message}")
            }
        }
    }
}
