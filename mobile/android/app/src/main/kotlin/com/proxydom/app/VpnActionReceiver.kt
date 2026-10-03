package com.proxydom.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Shade action: always stop the session (Amnezia contract). */
class VpnActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_DISCONNECT) return
        Log.i(TAG, "notification disconnect tapped")
        ProxyDomVpnService.stopVpnService(context)
    }

    companion object {
        private const val TAG = "VpnActionReceiver"
        const val ACTION_DISCONNECT = "com.proxy.dom.VPN_DISCONNECT"
    }
}
