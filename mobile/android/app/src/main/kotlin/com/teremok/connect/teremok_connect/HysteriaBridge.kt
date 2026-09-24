package com.teremok.connect.teremok_connect

import android.net.VpnService
import android.util.Log
import hy2bind.Hy2bind
import hy2bind.Protector
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Official apernet/hysteria client via our gomobile AAR (`hy2bind`).
 *
 * Sole dataplane (ADR 018). TUN is [startTun] inside hy2bind.
 *
 * Fails closed when `libs/hysteria-client.aar` is not bundled — never soft-pass
 * "QUIC up". SOCKS prove stays in [TeremokVpnService]. [ProtectGuard.protect]
 * is required so QUIC sockets do not loop into TUN.
 *
 * UnsatisfiedLinkError is an Error, not Exception — catch [Throwable] on the
 * VPN session thread or Auto SIGKILLs the process.
 */
class HysteriaBridge private constructor() {

    companion object {
        private const val TAG = "HysteriaBridge"

        @JvmStatic
        val instance: HysteriaBridge by lazy { HysteriaBridge() }
    }

    private var vpnService: VpnService? = null
    private val isRunning = AtomicBoolean(false)
    private val libraryLoaded = AtomicBoolean(false)

    @Volatile
    var lastErrorMessage: String? = null
        private set

    fun bind(service: VpnService) {
        vpnService = service
    }

    /**
     * Load `libhyjni.so` before `hy.Seq` clinit.
     */
    fun loadLibrary(): Boolean {
        if (libraryLoaded.get()) return true
        return try {
            System.loadLibrary("hyjni")
            libraryLoaded.set(true)
            true
        } catch (t: Throwable) {
            lastErrorMessage = t.message ?: t.toString()
            Log.e(TAG, "loadLibrary: hyjni failed", t)
            DiagnosticRing.append(TAG, "hy2.socks start ok=false reason=load_failed")
            false
        }
    }

    fun start(
        server: String,
        auth: String,
        sni: String,
        socksListen: String,
        directDomainSuffixes: List<String> = emptyList(),
    ): Boolean {
        val svc = vpnService
        if (svc == null) {
            lastErrorMessage = "VpnService not bound for protect()"
            return false
        }
        val obj = org.json.JSONObject()
        obj.put("server", server)
        obj.put("auth", auth)
        obj.put("sni", sni)
        obj.put("socks_listen", socksListen)
        val suffixes = org.json.JSONArray()
        for (raw in directDomainSuffixes) {
            val s = raw.trim().lowercase()
            if (s.isNotEmpty()) suffixes.put(s)
        }
        if (suffixes.length() > 0) {
            obj.put("direct_domain_suffixes", suffixes)
        }
        if (!loadLibrary()) {
            return false
        }
        return try {
            lastErrorMessage = null
            Log.i(
                TAG,
                "start: Hy2bind.start server=$server sni=$sni socks=$socksListen " +
                    "directSuffixes=${suffixes.length()}",
            )
            Hy2bind.setProtector(Hy2VpnProtector(svc))
            val err: String? = Hy2bind.start(obj.toString())
            if (!err.isNullOrBlank()) {
                lastErrorMessage = err
                Log.e(TAG, "start: Hy2bind.start error=$err")
                DiagnosticRing.append(TAG, "hy2.socks start ok=false reason=hy2_start")
                return false
            }
            isRunning.set(true)
            Log.i(TAG, "start: Hy2 SOCKS on $socksListen server=$server")
            DiagnosticRing.append(TAG, "hy2.socks start ok=true")
            true
        } catch (t: Throwable) {
            lastErrorMessage = t.message ?: t.toString()
            Log.e(TAG, "start: failed", t)
            DiagnosticRing.append(TAG, "hy2.socks start ok=false reason=start_failed")
            false
        }
    }

    /**
     * gVisor TUN→SOCKS inside hy2bind (same Go runtime as Hy2).
     *
     * [tunFd] must already be detached from a [android.os.ParcelFileDescriptor]
     * (`detachFd()`). Go owns and closes it.
     */
    fun startTun(tunFd: Int, mtu: Int): Boolean {
        if (!isRunning.get()) {
            lastErrorMessage = "Hy2 SOCKS not running"
            return false
        }
        return try {
            val err: String? = Hy2bind.startTun(tunFd.toLong(), mtu.toLong())
            if (!err.isNullOrBlank()) {
                lastErrorMessage = err
                Log.e(TAG, "startTun: $err")
                return false
            }
            Log.i(TAG, "startTun: fd=$tunFd mtu=$mtu")
            true
        } catch (t: Throwable) {
            lastErrorMessage = t.message ?: t.toString()
            Log.e(TAG, "startTun: failed", t)
            false
        }
    }

    fun startShare(configJson: String): Boolean {
        val svc = vpnService
        if (svc == null) {
            lastErrorMessage = "VpnService not bound for protect()"
            return false
        }
        if (!loadLibrary()) return false
        return try {
            lastErrorMessage = null
            Hy2bind.setProtector(Hy2VpnProtector(svc))
            val err: String? = Hy2bind.startShare(configJson)
            if (!err.isNullOrBlank()) {
                lastErrorMessage = err
                Log.e(TAG, "startShare failed")
                return false
            }
            isRunning.set(true)
            Log.i(TAG, "startShare: local SOCKS ready")
            true
        } catch (t: Throwable) {
            lastErrorMessage = t.message ?: t.toString()
            Log.e(TAG, "startShare: failed", t)
            false
        }
    }

    fun startShareTun(tunFd: Int, mtu: Int): Boolean {
        return try {
            val err: String? = Hy2bind.startShareTun(tunFd.toLong(), mtu.toLong())
            if (!err.isNullOrBlank()) {
                lastErrorMessage = err
                Log.e(TAG, "startShareTun: $err")
                return false
            }
            true
        } catch (t: Throwable) {
            lastErrorMessage = t.message ?: t.toString()
            Log.e(TAG, "startShareTun: failed", t)
            false
        }
    }

    fun stop() {
        if (!isRunning.getAndSet(false)) return
        try {
            // Stop() already calls StopTun — do not stopTun()+stop() (double teardown).
            Hy2bind.stop()
        } catch (t: Throwable) {
            Log.w(TAG, "stop: ${t.message}")
        }
        lastErrorMessage = null
    }
}

/** gomobile [Protector] — `protect(long)`, not a Kotlin fun-interface lambda. */
private class Hy2VpnProtector(
    private val svc: VpnService,
) : Protector {
    override fun protect(n: Long): Boolean {
        val fd = n.toInt()
        val ok = try {
            svc.protect(fd)
        } catch (t: Throwable) {
            Log.e("HysteriaBridge", "protect($fd) threw", t)
            false
        }
        if (!ok) {
            ProtectGuard.reportFailure(fd)
        }
        return ok
    }
}
