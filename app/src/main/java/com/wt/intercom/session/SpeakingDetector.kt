package com.wt.intercom.session

import kotlin.math.sqrt

/**
 * 简单能量 VAD：一帧 RMS 超阈值即视为说话，并保持 hangoverFrames 帧余晖防闪烁。
 *
 * 线程模型：feed 只由单一生产者线程调用（自己那路=音频采集线程，远端每路=播放线程），
 * isSpeaking 可能被其他线程（UI/主线程经 publishState）读取，
 * 故 hangover 标 @Volatile 保证跨线程可见性；自增只在生产者线程内发生，无竞态。
 */
class SpeakingDetector(
    private val threshold: Double = 500.0,
    private val hangoverFrames: Int = 15,   // 约 300ms
) {
    @Volatile private var hangover = 0

    fun feed(pcm: ShortArray) {
        var sum = 0.0
        for (s in pcm) sum += s.toDouble() * s
        val rms = sqrt(sum / pcm.size)
        if (rms > threshold) hangover = hangoverFrames
        else if (hangover > 0) hangover--
    }

    fun isSpeaking(): Boolean = hangover > 0
}
