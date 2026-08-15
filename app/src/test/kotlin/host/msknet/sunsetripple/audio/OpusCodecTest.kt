package host.msknet.sunsetripple.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt

class OpusCodecTest {

    private fun sineFrame(frameIndex: Int): ShortArray = ShortArray(AudioConfig.FRAME_SAMPLES) { n ->
        val t = (frameIndex * AudioConfig.FRAME_SAMPLES + n).toDouble() / AudioConfig.SAMPLE_RATE
        (sin(2 * PI * 440 * t) * 8000).toInt().toShort()
    }

    private fun rms(pcm: ShortArray): Double =
        sqrt(pcm.map { it.toDouble() * it }.average())

    @Test
    fun `正弦波编码解码后保留能量`() {
        val enc = OpusCodec()
        val dec = OpusCodec()
        var lastRms = 0.0
        repeat(10) { i ->
            val packet = enc.encode(sineFrame(i))
            assertTrue("包大小应在合理区间，实际 ${packet.size}", packet.size in 5..400)
            val out = dec.decode(packet)
            assertEquals(AudioConfig.FRAME_SAMPLES, out.size)
            lastRms = rms(out)
        }
        assertTrue("解码输出应有能量，实际 RMS=$lastRms", lastRms > 500)
    }

    @Test
    fun `PLC 丢包补帧返回完整一帧`() {
        val enc = OpusCodec()
        val dec = OpusCodec()
        repeat(5) { i -> dec.decode(enc.encode(sineFrame(i))) }   // 先建立解码状态
        val plc = dec.decode(null)
        assertEquals(AudioConfig.FRAME_SAMPLES, plc.size)
    }
}
