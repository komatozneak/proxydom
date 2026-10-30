package com.proxydom.app

import com.proxydom.app.session.PathHealth
import com.proxydom.app.session.SessionReason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The Home `ms` number is the path-health RTT, and a path that stopped
 * answering has to clear it instead of freezing on the last good sample.
 */
class HomePingSampleTest {
    @Test
    fun `a live path reports the RTT it measured`() {
        assertEquals(
            5,
            homePingSample(PathHealth.HealthResult.Ok(rttMs = 5, attempt = 0)),
        )
        assertEquals(
            84,
            homePingSample(PathHealth.HealthResult.Ok(rttMs = 84, attempt = 0)),
        )
        assertEquals(
            5000,
            homePingSample(PathHealth.HealthResult.Ok(rttMs = 5000, attempt = 0)),
        )
    }

    @Test
    fun `an impossible RTT is no number at all`() {
        // The sample is now an HTTP round trip, which cannot happen locally:
        // under 5 ms it did not happen at all, over 5000 ms nobody waits on it.
        assertNull(homePingSample(PathHealth.HealthResult.Ok(rttMs = 0, attempt = 0)))
        assertNull(homePingSample(PathHealth.HealthResult.Ok(rttMs = 4, attempt = 0)))
        assertNull(homePingSample(PathHealth.HealthResult.Ok(rttMs = 5001, attempt = 0)))
    }

    @Test
    fun `a degraded path clears the number after two misses`() {
        assertNull(homePingSample(PathHealth.HealthResult.Degraded(2, "n=2")))
        assertNull(homePingSample(PathHealth.HealthResult.Dead(4, "n=4")))
    }

    @Test
    fun `a failed probe clears the number`() {
        assertNull(
            homePingSample(
                PathHealth.HealthResult.Fail(SessionReason.DialFail, "refused", 1),
            ),
        )
    }
}
