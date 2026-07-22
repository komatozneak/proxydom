package com.teremok.connect.teremok_connect

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Disconnect action from VPN foreground notification. */
class VpnActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_DISCONNECT) return
        Log.i(TAG, "notification disconnect tapped")
        val stop = Intent(context, TeremokVpnService::class.java).apply {
            action = TeremokVpnService.ACTION_STOP
        }
        context.startService(stop)
    }

    companion object {
        private const val TAG = "VpnActionReceiver"
        const val ACTION_DISCONNECT = "com.teremok.connect.VPN_DISCONNECT"
    }
}
