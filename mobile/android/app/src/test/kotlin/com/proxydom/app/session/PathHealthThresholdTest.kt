package com.teremok.connect.teremok_connect.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PathHealthThresholdTest {
    @Test
    fun `dead takes more consecutive probe fails than degraded`() {
        assertTrue(PathHealth.DEAD_THRESHOLD > PathHealth.DEGRADED_THRESHOLD)
        assertEquals(2, PathHealth.DEGRADED_THRESHOLD)
        assertEquals(4, PathHealth.DEAD_THRESHOLD)
    }
}
