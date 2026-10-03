package com.proxydom.app.session

/**
 * Sequential Auto prove (not TCP RTT). First item whose [prove] returns true wins.
 * Manual Locations never uses this — PathIncompatible stays on the chosen node.
 */
object AutoProveLoop {
    fun <T> firstSuccess(items: List<T>, prove: (T) -> Boolean): T? {
        for (item in items) {
            if (prove(item)) return item
        }
        return null
    }
}
