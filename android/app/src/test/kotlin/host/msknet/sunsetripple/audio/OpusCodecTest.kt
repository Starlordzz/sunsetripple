package host.msknet.sunsetripple.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * [OpusCodec] 的纯 JVM 单测（Concentus 实现，不需要真机/Robolectric）：
 * 包长上限、往返帧长、PLC 补帧、码率边界，以及「每路流各一个实例」这个前提。
 */
class OpusCodecTest {

    private fun toneFrame(amplitude: Double = 8_000.0, hz: Double = 440.0): ShortArray =
        ShortArray(OpusCodec.FRAME_SAMPLES) { i ->
            (Math.sin(2.0 * Math.PI * hz * i / OpusCodec.SAMPLE_RATE) * amplitude).toInt().toShort()
        }

    private fun silenceFrame(): ShortArray = ShortArray(OpusCodec.FRAME_SAMPLES)

    /** 采样绝对值之和，用来区分「有信号」和「静音」。 */
    private fun energy(pcm: ShortArray): Long = pcm.fold(0L) { acc, s -> acc + Math.abs(s.toInt()) }

    @Test
    fun encodeStaysWithinMaxPacketBytes() {
        val codec = OpusCodec()
        repeat(20) {
            val packet = codec.encode(toneFrame())
            assertTrue("编码结果不能为空", packet.isNotEmpty())
            assertTrue(
                "Opus 包 ${packet.size} 字节超出 Frame.maxPayloadSize(${OpusCodec.MAX_PACKET_BYTES})",
                packet.size <= OpusCodec.MAX_PACKET_BYTES,
            )
        }
    }

    @Test
    fun encodeDecodeRoundTripReturnsOneFullFrame() {
        val codec = OpusCodec()

        val decoded = codec.decode(codec.encode(toneFrame()))

        assertEquals(OpusCodec.FRAME_SAMPLES, decoded.size)
        assertTrue("往返后信号被抹平：energy=${energy(decoded)}", energy(decoded) > 100_000)
    }

    @Test
    fun decodeNullTriggersPlcWithoutThrowing() {
        val codec = OpusCodec()

        // 冷启动就丢包：PLC 要给出整帧静音，而不是抛异常或短帧。
        assertEquals(OpusCodec.FRAME_SAMPLES, codec.decode(null).size)

        // 有过正常帧之后再丢包：PLC 必须真的外推补出信号，而不是直接静音。
        codec.decode(codec.encode(toneFrame()))
        val concealed = codec.decode(null)

        assertEquals(OpusCodec.FRAME_SAMPLES, concealed.size)
        assertTrue("PLC 没有补齐信号：energy=${energy(concealed)}", energy(concealed) > 10_000)
    }

    @Test
    fun decodeRecoversAfterConsecutivePlcFrames() {
        val codec = OpusCodec()
        val packet = codec.encode(toneFrame())
        codec.decode(packet)

        repeat(3) { codec.decode(null) } // 连续丢 3 帧

        val recovered = codec.decode(codec.encode(toneFrame()))
        assertEquals("PLC 之后解码器不能卡在错误状态", OpusCodec.FRAME_SAMPLES, recovered.size)
        assertTrue("恢复后信号应当是正常的：energy=${energy(recovered)}", energy(recovered) > 100_000)
    }

    @Test
    fun setBitrateAcceptsBoundariesAndRejectsOutOfRange() {
        val codec = OpusCodec()

        codec.setBitrate(6_000)
        codec.setBitrate(64_000)
        codec.setBitrate(OpusCodec.DEFAULT_BITRATE)
        codec.setBitrate(OpusCodec.BLUETOOTH_BITRATE)

        assertThrows(IllegalArgumentException::class.java) { codec.setBitrate(5_999) }
        assertThrows(IllegalArgumentException::class.java) { codec.setBitrate(64_001) }
        assertThrows(IllegalArgumentException::class.java) { codec.setBitrate(0) }
    }

    @Test
    fun continuousStreamKeepsFrameSizeStable() {
        val codec = OpusCodec()
        val pcm = toneFrame()

        repeat(50) { i ->
            val decoded = codec.decode(codec.encode(pcm))
            assertEquals("第 $i 帧长度漂了", OpusCodec.FRAME_SAMPLES, decoded.size)
            assertTrue("第 $i 帧变成静音了：energy=${energy(decoded)}", energy(decoded) > 100_000)
        }
    }

    /**
     * 类注释写明「非线程安全：每路流必须各建一个实例」。
     * 这里让两路（高能量话音 / 静音）在各自线程里并发跑完整编解码，
     * 任何跨实例的状态泄漏都会让其中一路的能量特征崩掉。
     */
    @Test
    fun independentInstancesDoNotInterfereWhenUsedConcurrently() {
        val voice = OpusCodec(OpusCodec.DEFAULT_BITRATE)
        val quiet = OpusCodec(OpusCodec.BLUETOOTH_BITRATE)
        val start = CountDownLatch(1)
        val failure = AtomicReference<Throwable>()

        fun worker(
            name: String,
            codec: OpusCodec,
            pcm: ShortArray,
            minEnergy: Long,
            maxEnergy: Long,
        ) = Thread({
            try {
                start.await()
                repeat(40) { i ->
                    val decoded = codec.decode(codec.encode(pcm))
                    assertEquals("$name 第 $i 帧长度漂了", OpusCodec.FRAME_SAMPLES, decoded.size)
                    val e = energy(decoded)
                    assertTrue("$name 第 $i 帧能量异常：$e", e in minEnergy..maxEnergy)
                }
            } catch (t: Throwable) {
                failure.compareAndSet(null, t)
            }
        }, name)

        val voiceThread = worker("voice", voice, toneFrame(), 100_000, Long.MAX_VALUE)
        val quietThread = worker("quiet", quiet, silenceFrame(), 0, 2_000)
        voiceThread.start()
        quietThread.start()
        start.countDown()
        voiceThread.join(TimeUnit.MINUTES.toMillis(2))
        quietThread.join(TimeUnit.MINUTES.toMillis(2))

        assertFalse("并发编解码超时未结束", voiceThread.isAlive || quietThread.isAlive)
        failure.get()?.let { throw AssertionError("两个独立实例并发时互相干扰：${it.message}", it) }
    }
}
