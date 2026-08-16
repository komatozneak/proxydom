package com.teremok.connect.teremok_connect

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import com.adguard.trusttunnel.CertificateVerificator
import com.adguard.trusttunnel.VpnClient
import com.adguard.trusttunnel.VpnClientListener
import com.adguard.trusttunnel.VpnState
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridge to the TrustTunnel native client ([com.adguard.trusttunnel.VpnClient])
 * running inside our own [TeremokVpnService] (ADR 006 dual-core).
 *
 * We deliberately do NOT use the adapter's `com.adguard.trusttunnel.VpnService`:
 * Teremok keeps its own lifecycle, foreground notification and status channel.
 * The bridge mirrors the official service's TUN conventions (fake-DNS IP when
 * custom upstreams are set, excludeCidr route math) and adds:
 * - socket protect via [VpnService.protect] (keeps endpoint conn out of TUN)
 * - system cert verification via [CertificateVerificator]
 * - [VpnState] → Teremok status mapping (CONNECTED only after native CONNECTED)
 *
 * Unlike Xray `quic-reject`, this AAR has no UDP/443 block under manual
 * `VpnClient.start(tunFd)` (SOCKS needs AutoSetup; socketpair-as-TUN is dead).
 * Live path: real TUN + http2-only profile. See ADR 006.
 */
class TrustTunnelBridge private constructor() {

    companion object {
        private const val TAG = "TrustTunnelBridge"

        /** TUN address convention from the official adapter VpnService. */
        const val TUN_ADDRESS = "172.20.2.13"
        const val TUN_ADDRESS_PREFIX = 32

        /** Advertised on TUN when dns_upstreams are set: native lib intercepts
         * DNS to this address and forwards to the configured upstreams. */
        const val FAKE_DNS_SERVER = "198.18.53.53"

        @JvmStatic
        val instance: TrustTunnelBridge by lazy { TrustTunnelBridge() }
    }

    /** Callbacks the host service cares about (status, fatal drop). */
    interface Host {
        fun onTrustTunnelState(state: VpnState)
    }

    private var vpnService: VpnService? = null
    private var client: VpnClient? = null
    private var certificateVerificator: CertificateVerificator? = null
    private val isRunning = AtomicBoolean(false)

    @Volatile
    var lastState: VpnState = VpnState.DISCONNECTED
        private set

    @Volatile
    var lastErrorMessage: String? = null
        private set

    fun bind(service: VpnService) {
        vpnService = service
    }

    private val listener = object : VpnClientListener {
        override fun protectSocket(socket: Int): Boolean {
            val svc = vpnService
            if (svc == null) {
                Log.e(TAG, "protectSocket($socket): VpnService not bound")
                ProtectGuard.reportFailure(socket)
                return false
            }
            val ok = try {
                svc.protect(socket)
            } catch (e: Exception) {
                Log.e(TAG, "protectSocket($socket) threw", e)
                false
            }
            if (!ok) {
                Log.w(TAG, "protectSocket($socket) failed")
                ProtectGuard.reportFailure(socket)
            }
            return ok
        }

        override fun verifyCertificate(
            certificate: ByteArray?,
            rawChain: List<ByteArray?>?,
        ): Boolean {
            val verificator = certificateVerificator ?: return false
            return verificator.verifyCertificate(certificate, rawChain)
        }

        override fun onStateChanged(state: Int) {
            val mapped = try {
                VpnState.getByCode(state)
            } catch (e: Exception) {
                Log.w(TAG, "unknown VpnState code $state")
                return
            }
            lastState = mapped
            Log.i(TAG, "state → $mapped")
            host?.onTrustTunnelState(mapped)
        }

        override fun onConnectionInfo(info: String) {
            Log.d(TAG, "conn: $info")
        }
    }

    @Volatile
    private var host: Host? = null

    /**
     * Start the native client with [configToml] on an established [tun] fd.
     * Takes ownership of [tun] (VpnClient.start detaches the fd).
     */
    fun start(configToml: String, tun: ParcelFileDescriptor, host: Host): Boolean {
        if (isRunning.get()) {
            Log.w(TAG, "start: already running")
            return false
        }
        if (vpnService == null) {
            lastErrorMessage = "VpnService not bound for protect()"
            Log.e(TAG, "start: $lastErrorMessage")
            return false
        }
        return try {
            lastErrorMessage = null
            certificateVerificator = CertificateVerificator()
            this.host = host
            val newClient = VpnClient(configToml, listener)
            client = newClient
            if (!newClient.start(tun)) {
                lastErrorMessage = "native start returned false"
                Log.e(TAG, "start: $lastErrorMessage")
                runCatching { newClient.close() }
                client = null
                return false
            }
            isRunning.set(true)
            Log.i(TAG, "start: TrustTunnel native client started")
            true
        } catch (e: Exception) {
            lastErrorMessage = e.message ?: e.toString()
            Log.e(TAG, "start: failed", e)
            runCatching { client?.close() }
            client = null
            isRunning.set(false)
            false
        }
    }

    fun stop() {
        val current = client ?: return
        try {
            Log.i(TAG, "stop: stopping TrustTunnel client")
            current.stop()
        } catch (e: Exception) {
            Log.e(TAG, "stop: error", e)
        } finally {
            runCatching { current.close() }
            client = null
            host = null
            isRunning.set(false)
            lastState = VpnState.DISCONNECTED
        }
    }

    fun isRunning(): Boolean = isRunning.get()
}
