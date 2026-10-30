package com.proxydom.app.session

import com.proxydom.app.FakeSocksServer
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The first Home sample must not wait one whole interval.
 *
 * The loop used to sleep five seconds before its first probe, so Home showed an
 * ellipsis for that long on every connect — the ping looked like it was still
 * measuring long after the tunnel was up.
 */
class PathHealthFirstSampleTest {
    @Test
    fun `the first sample arrives without waiting for the five second tick`() {
        FakeSocksServer(statusLine = "HTTP/1.0 204 No Content", holdBackMs = 0)
            .use { server ->
                val samples = CopyOnWriteArrayList<Long>()
                val health = PathHealth()
                health.startContinuous(
                    adapter = PathHealth.CoreAdapter.HysteriaSocks,
                    socksPort = server.port,
                    listener = { result ->
                        if (result is PathHealth.HealthResult.Ok) {
                            samples.add(result.rttMs)
                        }
                    },
                    alive = { true },
                )
                try {
                    val deadline = System.currentTimeMillis() + 1_500
                    while (samples.isEmpty() &&
                        System.currentTimeMillis() < deadline
                    ) {
                        Thread.sleep(20)
                    }
                    assertTrue(
                        "first sample must arrive immediately, got ${samples.toList()}",
                        samples.isNotEmpty(),
                    )
                } finally {
                    health.stopContinuous()
                }
            }
    }
}
