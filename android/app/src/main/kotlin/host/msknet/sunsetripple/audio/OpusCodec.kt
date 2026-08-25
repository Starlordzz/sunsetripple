package host.msknet.sunsetripple.audio

import io.github.jaredmdobson.concentus.OpusApplication
import io.github.jaredmdobson.concentus.OpusDecoder
import io.github.jaredmdobson.concentus.OpusEncoder

/**
 * Opus 编解码封装（Concentus 纯 JVM 实现，VoIP 模式）。
 *
 * 参数与已发布的 Kotlin 版（alpha.7）完全一致，这是两版能互通的前提：
 * 16 kHz / 单声道 / 20 ms 一帧 / OPUS_APPLICATION_VOIP。
 *
 * **非线程安全**：编解码器内部有状态，每路流必须各建一个实例。
 */
class OpusCodec(bitrateBps: Int = DEFAULT_BITRATE) {

    companion object {
        const val SAMPLE_RATE = 16_000
        const val FRAME_SAMPLES = 320 // 20ms @ 16kHz

        /** WiFi 房码率。 */
        const val DEFAULT_BITRATE = 24_000

        /** 蓝牙房码率：BLE L2CAP 带宽有限，压到 16k。 */
        const val BLUETOOTH_BITRATE = 16_000

        /** 编码输出上限，与 Frame.maxPayloadSize 对齐。 */
        const val MAX_PACKET_BYTES = 512
    }

    private val encoder = OpusEncoder(
        SAMPLE_RATE, 1, OpusApplication.OPUS_APPLICATION_VOIP
    ).also { it.bitrate = bitrateBps }

    private val decoder = OpusDecoder(SAMPLE_RATE, 1)
    private val encodeBuffer = ByteArray(MAX_PACKET_BYTES)

    fun setBitrate(bitrateBps: Int) {
        require(bitrateBps in 6_000..64_000) { "码率超出 Opus 允许范围: $bitrateBps" }
        encoder.bitrate = bitrateBps
    }

    /** 编码一帧（320 样本）PCM，返回 Opus 包。 */
    fun encode(pcm: ShortArray): ByteArray {
        val n = encoder.encode(pcm, 0, FRAME_SAMPLES, encodeBuffer, 0, encodeBuffer.size)
        return encodeBuffer.copyOf(n)
    }

    /** 解码一个 Opus 包为一帧 PCM；传 null 触发丢包隐藏（PLC）补帧。 */
    fun decode(packet: ByteArray?): ShortArray {
        val out = ShortArray(FRAME_SAMPLES)
        if (packet == null) {
            decoder.decode(null, 0, 0, out, 0, FRAME_SAMPLES, false)
        } else {
            decoder.decode(packet, 0, packet.size, out, 0, FRAME_SAMPLES, false)
        }
        return out
    }
}
