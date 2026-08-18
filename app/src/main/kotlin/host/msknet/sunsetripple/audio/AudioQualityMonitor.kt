package host.msknet.sunsetripple.audio

enum class NetworkQuality { UNKNOWN, GOOD, FAIR, POOR }

data class AudioQualitySnapshot(
    val receivedFrames: Long = 0,
    val concealedFrames: Long = 0,
    val underruns: Long = 0,
    val averageRecoveryMillis: Long = 0,
) {
    val lossPercent: Int
        get() = if (receivedFrames + concealedFrames == 0L) 0
        else ((concealedFrames * 100) / (receivedFrames + concealedFrames)).toInt()

    val networkQuality: NetworkQuality
        get() = when {
            receivedFrames + concealedFrames < 20 -> NetworkQuality.UNKNOWN
            lossPercent <= 2 && averageRecoveryMillis <= 80 -> NetworkQuality.GOOD
            lossPercent <= 8 && averageRecoveryMillis <= 250 -> NetworkQuality.FAIR
            else -> NetworkQuality.POOR
        }
}

class AudioQualityMonitor(private val clockMillis: () -> Long = { System.nanoTime() / 1_000_000 }) {
    private var receivedFrames = 0L
    private var concealedFrames = 0L
    private var underruns = 0L
    private var outageStartedAt: Long? = null
    private var recoveryTotalMillis = 0L
    private var recoveryCount = 0L

    @Synchronized
    fun recordReceived() {
        receivedFrames += 1
        outageStartedAt?.let { started ->
            recoveryTotalMillis += (clockMillis() - started).coerceAtLeast(0)
            recoveryCount += 1
            outageStartedAt = null
        }
    }

    @Synchronized
    fun recordConcealment() {
        concealedFrames += 1
        if (outageStartedAt == null) outageStartedAt = clockMillis()
    }

    @Synchronized
    fun recordUnderrun() {
        underruns += 1
        if (outageStartedAt == null) outageStartedAt = clockMillis()
    }

    @Synchronized
    fun snapshot(): AudioQualitySnapshot = AudioQualitySnapshot(
        receivedFrames = receivedFrames,
        concealedFrames = concealedFrames,
        underruns = underruns,
        averageRecoveryMillis = if (recoveryCount == 0L) 0 else recoveryTotalMillis / recoveryCount,
    )
}

data class AdaptiveAudioTuning(val bitrateBps: Int, val prebufferFrames: Int, val usePlc: Boolean)

object AdaptiveAudioPolicy {
    fun select(lossPercent: Int, jitterMillis: Int, roundTripMillis: Int): AdaptiveAudioTuning = when {
        lossPercent >= 12 || jitterMillis >= 120 || roundTripMillis >= 500 ->
            AdaptiveAudioTuning(12_000, 6, true)
        lossPercent >= 4 || jitterMillis >= 60 || roundTripMillis >= 250 ->
            AdaptiveAudioTuning(16_000, 4, true)
        else -> AdaptiveAudioTuning(24_000, 3, true)
    }
}
