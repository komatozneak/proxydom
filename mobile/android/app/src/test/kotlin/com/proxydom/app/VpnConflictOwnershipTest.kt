package com.proxydom.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Conflict detection must not read our own VPN network as another app's VPN.
 *
 * `stop()` closes the TUN before ConnectivityService drops the network from
 * `allNetworks`, so for a few milliseconds a live VPN transport exists while
 * [ProxyDomVpnService.isOurSessionOccupying] is false. Treating that as foreign
 * made «Переподключить» fail with «Мешает другой VPN» on a Pixel 7 Pro.
 */
class VpnConflictOwnershipTest {

    @Test
    fun ourOwnVpnTransportIsNotForeign() {
        assertFalse(isForeignVpnTransport(isVpn = true, ownerUid = 10251, myUid = 10251))
    }

    @Test
    fun anotherAppsVpnTransportIsForeign() {
        assertTrue(isForeignVpnTransport(isVpn = true, ownerUid = 10300, myUid = 10251))
    }

    @Test
    fun unknownOwnerStaysForeign() {
        assertTrue(isForeignVpnTransport(isVpn = true, ownerUid = -1, myUid = 10251))
    }

    @Test
    fun nonVpnTransportIsNeverForeign() {
        assertFalse(isForeignVpnTransport(isVpn = false, ownerUid = 10300, myUid = 10251))
    }
}
