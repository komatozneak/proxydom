package com.teremok.connect.teremok_connect

import io.nekohasekai.libbox.NetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.StringIterator

/** Empty [StringIterator] for stub [LibboxPlatform] responses. */
internal class EmptyStringIterator : StringIterator {
    override fun len(): Int = 0

    override fun hasNext(): Boolean = false

    override fun next(): String = error("empty iterator")
}

/** Wraps a Kotlin iterator as libbox [StringIterator]. */
internal class KotlinStringIterator(
    private val iterator: Iterator<String>,
) : StringIterator {
    override fun len(): Int = 0

    override fun hasNext(): Boolean = iterator.hasNext()

    override fun next(): String = iterator.next()
}

/** Empty [NetworkInterfaceIterator] for stub platform responses. */
internal class EmptyNetworkInterfaceIterator : NetworkInterfaceIterator {
    override fun hasNext(): Boolean = false

    override fun next(): NetworkInterface = error("empty iterator")
}
