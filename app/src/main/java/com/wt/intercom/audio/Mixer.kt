package com.wt.intercom.audio

/** 多路 16-bit PCM 混音：逐样本相加 + 饱和截断。所有输入帧长必须一致。 */
object Mixer {

    fun mix(streams: List<ShortArray>): ShortArray {
        require(streams.isNotEmpty()) { "至少一路输入" }
        val len = streams[0].size
        require(streams.all { it.size == len }) { "各路帧长必须一致: ${streams.map { it.size }}" }
        val out = ShortArray(len)
        for (i in 0 until len) {
            var sum = 0
            for (s in streams) sum += s[i].toInt()
            out[i] = sum.coerceIn(-32768, 32767).toShort()
        }
        return out
    }
}
