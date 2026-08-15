package host.msknet.sunsetripple.transport

class ReconnectPolicy {
    private var nextAttempt = 0

    fun nextDelayMs(): Long? = DELAYS_MS.getOrNull(nextAttempt++)

    fun reset() {
        nextAttempt = 0
    }

    private companion object {
        val DELAYS_MS = longArrayOf(1_000L, 2_000L, 4_000L)
    }
}
