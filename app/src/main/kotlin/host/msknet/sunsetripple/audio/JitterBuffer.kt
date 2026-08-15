package host.msknet.sunsetripple.audio

/**
 * 每路远端音频流一个实例。按 16 位回绕序号缓存 Opus 包：
 * 乱序重排、丢包位置吐 null（调用方用 Opus PLC 补帧）、
 * 攒满 prebufferFrames 帧才开始出帧以吸收网络抖动。
 * 线程安全：put 由网络/采集线程调用，poll 由播放线程调用。
 */
class JitterBuffer(
    private val prebufferFrames: Int = 3,
    private val maxBuffer: Int = 10,
) {
    private val buf = sortedMapOf<Long, ByteArray>()
    private var highestSeen = -1L   // 展开后的最大序号，用于 16 位回绕展开
    private var next = -1L          // 下一个应吐出的序号
    private var started = false

    @Synchronized
    fun put(seq16: Int, payload: ByteArray) {
        val seq = unwrap(seq16)
        if (started && seq < next) return                  // 迟到帧：该位置已播过
        buf[seq] = payload
        while (buf.size > maxBuffer) buf.remove(buf.firstKey())  // 防积压，丢最旧
    }

    @Synchronized
    fun poll(): ByteArray? {
        if (!started) {
            if (buf.size < prebufferFrames) return null
            started = true
            next = buf.firstKey()
        }
        if (buf.isEmpty()) return null                     // 欠载：等新包，不推进
        if (buf.firstKey() - next > maxBuffer) next = buf.firstKey()  // 断流后重新对齐
        val head = buf.remove(next)
        next++
        return head                                        // null = 该位置丢包，交给 PLC
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
