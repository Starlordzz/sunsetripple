package host.msknet.sunsetripple.audio

import org.junit.Assert.assertEquals
import org.junit.Test

class AudioQualityMonitorTest {
    @Test
    fun measuresLossRecoveryAndQuality() {
        var now = 100L
        val monitor = AudioQualityMonitor { now }
        repeat(20) { monitor.recordReceived() }
        monitor.recordConcealment()
        now += 60
        monitor.recordReceived()

        val snapshot = monitor.snapshot()

        assertEquals(4, snapshot.lossPercent)
        assertEquals(60, snapshot.averageRecoveryMillis)
        assertEquals(NetworkQuality.FAIR, snapshot.networkQuality)
    }

    @Test
    fun adaptivePolicyReducesBitrateAndExpandsBuffer() {
        assertEquals(24_000, AdaptiveAudioPolicy.select(1, 20, 80).bitrateBps)
        assertEquals(4, AdaptiveAudioPolicy.select(5, 70, 150).prebufferFrames)
        assertEquals(12_000, AdaptiveAudioPolicy.select(15, 140, 600).bitrateBps)
    }
}
