package com.wt.intercom.audio

/**
 * M1 单机回环：麦克风 → Opus 编码 → JitterBuffer → Opus 解码 → 扬声器。
 * 数据路径与远端通话完全一致，后续计划只是把 put 的调用方换成网络接收。
 */
class LoopbackController {
    @Volatile private var running = false
    private var engine: AudioEngine? = null
    private var playThread: Thread? = null

    fun start() {
        val encoder = OpusCodec()
        val decoder = OpusCodec()
        val jitter = JitterBuffer()
        var seq = 0
        val eng = AudioEngine { pcm ->
            jitter.put(seq, encoder.encode(pcm))
            seq = (seq + 1) and 0xFFFF
        }
        engine = eng
        running = true
        eng.start()
        val silence = ShortArray(AudioConfig.FRAME_SAMPLES)
        playThread = Thread({
            while (running) {
                val out = if (jitter.hasStarted()) decoder.decode(jitter.poll()) else silence
                eng.playPcm(out)   // 阻塞写提供 20ms 节拍
            }
        }, "audio-playback").apply { start() }
    }

    fun stop() {
        running = false
        playThread?.join(500)
        playThread = null
        engine?.stop()
        engine = null
    }
}
