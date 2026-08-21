package host.msknet.sunsetripple.audio

/**
 * 跨平台音频硬件 I/O 抽象接缝：
 * - Android：由包装了 AudioRecord + AudioTrack 的 `EngineAudioIo` 实现。
 * - iOS：由基于 AudioUnit (VoiceProcessingIO) 的适配器实现。
 * - HarmonyOS NEXT：由基于 @ohos.multimedia.audio (AudioCapturer + AudioRenderer) 的适配器实现。
 * - 测试环境：可直接注入纯 JVM 的内存录制与播放 Mock。
 */
interface AudioIo {
    var micMuted: Boolean
    fun start()
    fun playPcm(pcm: ShortArray)
    fun stop()
}

