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
        if (running) return
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
                val packet = jitter.poll()
                // 必须无条件调用 poll()——started 标志只在 poll 内部翻转，
                // 把 hasStarted() 当调用前置条件会自锁（预缓冲永远攒不满）。
                val out = if (packet == null && !jitter.hasStarted()) silence
                          else decoder.decode(packet)
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
