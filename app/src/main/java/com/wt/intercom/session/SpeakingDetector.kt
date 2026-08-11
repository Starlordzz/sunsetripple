package com.wt.intercom.session

import kotlin.math.sqrt

/** 简单能量 VAD：一帧 RMS 超阈值即视为说话，并保持 hangoverFrames 帧余晖防闪烁。 */
class SpeakingDetector(
    private val threshold: Double = 500.0,
    private val hangoverFrames: Int = 15,   // 约 300ms
) {
    private var hangover = 0

    fun feed(pcm: ShortArray) {
        var sum = 0.0
        for (s in pcm) sum += s.toDouble() * s
        val rms = sqrt(sum / pcm.size)
        if (rms > threshold) hangover = hangoverFrames
        else if (hangover > 0) hangover--
    }

    fun isSpeaking(): Boolean = hangover > 0
}
