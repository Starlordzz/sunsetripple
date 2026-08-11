package com.wt.intercom.audio

import io.github.jaredmdobson.concentus.OpusApplication
import io.github.jaredmdobson.concentus.OpusDecoder
import io.github.jaredmdobson.concentus.OpusEncoder

/**
 * Opus 编解码封装（Concentus 纯 JVM 实现，VoIP 模式）。
 * 非线程安全；编解码器内部有状态，每路流各建一个实例。
 */
class OpusCodec(bitrateBps: Int = 24_000) {
    private val encoder = OpusEncoder(
        AudioConfig.SAMPLE_RATE, 1, OpusApplication.OPUS_APPLICATION_VOIP
    ).also { it.bitrate = bitrateBps }
    private val decoder = OpusDecoder(AudioConfig.SAMPLE_RATE, 1)
    private val encBuf = ByteArray(512)

    /** 编码一帧（320 样本）PCM，返回 Opus 包。 */
    fun encode(pcm: ShortArray): ByteArray {
        val n = encoder.encode(pcm, 0, AudioConfig.FRAME_SAMPLES, encBuf, 0, encBuf.size)
        return encBuf.copyOf(n)
    }

    /** 解码一个 Opus 包为一帧 PCM；传 null 触发丢包隐藏（PLC）补帧。 */
    fun decode(packet: ByteArray?): ShortArray {
        val out = ShortArray(AudioConfig.FRAME_SAMPLES)
        if (packet == null) {
            decoder.decode(null, 0, 0, out, 0, AudioConfig.FRAME_SAMPLES, false)
        } else {
            decoder.decode(packet, 0, packet.size, out, 0, AudioConfig.FRAME_SAMPLES, false)
        }
        return out
    }
}
