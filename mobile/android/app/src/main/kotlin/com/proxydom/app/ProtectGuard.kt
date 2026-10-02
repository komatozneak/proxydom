package com.teremok.connect.teremok_connect

import java.util.concurrent.atomic.AtomicBoolean

/**
 * Отслеживает сбои [android.net.VpnService.protect] при direct outbound.
 *
 * В lockdown-режиме без protect VLESS-сокет уходит в TUN-петлю.
 */
internal object ProtectGuard {
    private val failed = AtomicBoolean(false)

    var onFailure: (() -> Unit)? = null

    fun reset() {
        failed.set(false)
    }

    fun reportFailure(fd: Int) {
        if (failed.compareAndSet(false, true)) {
            onFailure?.invoke()
        }
    }

    fun hasFailed(): Boolean = failed.get()
}
