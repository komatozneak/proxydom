package com.teremok.connect.teremok_connect

import android.os.Build
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState

/**
 * Minimal [PlatformInterface] for libbox [CommandServer].
 *
 * TUN fd wiring via [SingBoxBridge.setTunFd] — Commit 4 (TunForwarder).
 */
internal class LibboxPlatform(
    private val tunFdProvider: () -> Int?,
    private val protectSocket: (Int) -> Boolean,
) : PlatformInterface {

    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protectSocket(fd)
    }

    override fun openTun(options: TunOptions): Int {
        val fd = tunFdProvider()
            ?: error("TUN fd not set — wire TunForwarder in Commit 4")
        return fd
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        error("findConnectionOwner not implemented")
    }

    override fun getInterfaces() = EmptyNetworkInterfaceIterator()

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? = null

    override fun sendNotification(notification: Notification) {
        // no-op until foreground notification integration
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        // no-op — DefaultNetworkMonitor in SFA; optional for MVP
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        // no-op
    }

    override fun systemCertificates(): StringIterator = EmptyStringIterator()

    override fun underNetworkExtension(): Boolean = false

    override fun clearDNSCache() {
        // no-op
    }
}
