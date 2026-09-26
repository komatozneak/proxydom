package com.teremok.connect.teremok_connect

/**
 * Collapses a failed bind that succeeds again inside [windowMs] into one debug line.
 * A failure that is not followed by success becomes an error.
 */
internal class NetBindLog(
    private val emit: (level: String, event: String, fields: String) -> Unit,
    private val postDelayed: (delayMs: Long, task: Runnable) -> Unit,
    private val cancel: (task: Runnable) -> Unit,
    private val now: () -> Long = { System.currentTimeMillis() },
    private val windowMs: Long = 200,
) {
    private var pending: Runnable? = null
    private var pendingIface: String? = null
    private var retries = 0
    private var lastSuccessAt = Long.MIN_VALUE
    private var lastSuccessIface: String? = null

    fun record(iface: String, ok: Boolean) {
        val at = now()
        if (!ok) {
            if (pendingIface != null && pendingIface != iface) {
                fireError()
            }
            pendingIface = iface
            retries += 1
            pending?.let(cancel)
            val task = Runnable { fireError() }
            pending = task
            postDelayed(windowMs, task)
            return
        }
        val carried = if (pendingIface == null || pendingIface == iface) retries else 0
        val duplicate = carried == 0 &&
            lastSuccessIface == iface &&
            at - lastSuccessAt in 0..windowMs
        pending?.let(cancel)
        pending = null
        pendingIface = null
        retries = 0
        if (duplicate) return
        lastSuccessAt = at
        lastSuccessIface = iface
        emit("debug", "net.bind", "iface=$iface ok=true retries=$carried")
    }

    private fun fireError() {
        val iface = pendingIface ?: return
        val carried = retries
        pending = null
        pendingIface = null
        retries = 0
        emit("error", "net.bind", "iface=$iface ok=false retries=$carried")
    }
}
