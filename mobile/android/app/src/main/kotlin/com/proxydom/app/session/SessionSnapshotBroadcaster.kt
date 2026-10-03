package com.proxydom.app.session

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicReference

/**
 * Broadcasts [SessionSnapshot] JSON to Flutter EventChannel `proxydom/vpn/session`.
 * Also mirrors legacy status string via optional [onLegacyStatus].
 */
object SessionSnapshotBroadcaster {
    private const val TAG = "SessionSnapshotBroadcast"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val last = AtomicReference(SessionSnapshot.idle())

    var onLegacyStatus: ((String) -> Unit)? = null

    fun current(): SessionSnapshot = last.get()

    fun register(events: EventChannel.EventSink) {
        sink = events
        val snap = last.get()
        mainHandler.post {
            runCatching { events.success(snap.toJsonString()) }
                .onFailure { Log.w(TAG, "replay failed: ${it.message}") }
        }
    }

    fun unregister() {
        sink = null
    }

    fun emit(snapshot: SessionSnapshot) {
        last.set(snapshot)
        onLegacyStatus?.invoke(snapshot.phase.toLegacyStatus())
        val events = sink ?: return
        mainHandler.post {
            runCatching { events.success(snapshot.toJsonString()) }
                .onFailure { Log.w(TAG, "emit failed: ${it.message}") }
        }
    }
}
