package com.teremok.connect.teremok_connect

import android.util.Log
import libXray.LibXray

/**
 * DedProxy-shaped packet path on OSS: VpnService TUN fd → **gVisor inside
 * libXray** (`protocol:tun` + [LibXray.setTunFd]), not hev-socks5-tunnel.
 *
 * SOCKS `127.0.0.1:10808` remains for pre-connect probes / diagnostics only;
 * app traffic enters via TUN inbound (no userspace TUN→SOCKS hop).
 *
 * Requires libXray **26.6.27+** (`setTunFd` + `proxy/tun`). Do not bump past
 * 26.6.27 without Marzban Reality lockstep.
 */
object GvisorTun2Socks {
    private const val TAG = "GvisorTun2Socks"

    const val SOCKS_HOST = "127.0.0.1"
    const val SOCKS_PORT = 10808

    /**
     * Attach VpnService TUN fd before [XrayBridge.start]. Pass `0` to clear.
     */
    fun attachTunFd(tunFd: Int) {
        LibXray.setTunFd(tunFd)
        Log.i(TAG, "attachTunFd: fd=$tunFd (gVisor tun inbound)")
    }
}
