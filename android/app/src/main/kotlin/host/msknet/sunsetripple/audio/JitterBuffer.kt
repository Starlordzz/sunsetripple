package host.msknet.sunsetripple.audio

/** 从抖动缓冲取一帧的结果。 */
sealed class PollResult {
    /** 预缓冲未满或已欠载：这一拍不出声，不要用 PLC 硬补。 */
    object NotReady : PollResult()

    /** 该序号的包确实丢了：调用方应当用 Opus PLC 补一帧。 */
    object Lost : PollResult()

    /** 正常取到一个包。 */
    class Packet(val data: ByteArray) : PollResult()
}

/**
 * 每路远端音频流一个实例。按 16 位回绕序号缓存 Opus 包：
 * 乱序重排、丢包位置报 [PollResult.Lost]、攒满 [prebufferFrames] 帧才开始出帧以吸收网络抖动。
 *
 * 线程安全：[put] 由网络线程调用，[poll] 由播放线程调用。
 *
 * 移植自已发布的 Kotlin 版（alpha.7）。与原版唯一的差别是把「没准备好」和
 * 「丢包」这两种情况拆成了不同的返回值——原版都返回 null，调用方要靠
 * `hasStarted()` 才能分辨，很容易在欠载时错误地触发 PLC。
 */
class JitterBuffer(
    private val prebufferFrames: Int = 3,
    private val maxBuffer: Int = 10,
) {
    private val buf = sortedMapOf<Long, ByteArray>()
    private var highestSeen = -1L // 展开后的最大序号，用于 16 位回绕展开
    private var next = -1L        // 下一个应吐出的序号
    private var started = false

    @Synchronized
    fun put(seq16: Int, payload: ByteArray) {
        val seq = unwrap(seq16)
        if (started && seq < next) return // 迟到帧：该位置已播过
        buf[seq] = payload
        while (buf.size > maxBuffer) buf.remove(buf.firstKey()) // 防积压，丢最旧
    }

    @Synchronized
    fun poll(): PollResult {
        if (!started) {
            if (buf.size < prebufferFrames) return PollResult.NotReady
            started = true
            next = buf.firstKey()
        }
        if (buf.isEmpty()) return PollResult.NotReady // 欠载：等新包，不推进

        // 断流后重新对齐，避免 next 永远追不上
        if (buf.firstKey() - next > maxBuffer) next = buf.firstKey()

        val head = buf.remove(next)
        next++
        return if (head == null) PollResult.Lost else PollResult.Packet(head)
    }

    @Synchronized
    fun reset() {
        buf.clear()
        highestSeen = -1L
        next = -1L
        started = false
    }

    @Synchronized
    fun hasStarted(): Boolean = started

    @Synchronized
    fun pendingCount(): Int = buf.size

    /** 把 16 位回绕序号展开为单调递增的 Long。 */
    private fun unwrap(seq16: Int): Long {
        if (highestSeen < 0) {
            highestSeen = seq16.toLong()
            return highestSeen
        }
        val delta = ((seq16 - (highestSeen and 0xFFFF).toInt() + 0x8000) and 0xFFFF) - 0x8000
        val v = highestSeen + delta
        if (v > highestSeen) highestSeen = v
        return v
    }
}
