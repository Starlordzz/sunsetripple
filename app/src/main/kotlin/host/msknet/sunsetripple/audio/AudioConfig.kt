package host.msknet.sunsetripple.audio

/** 全项目统一的音频参数。改动会破坏与旧版本 App 的互通，谨慎修改。 */
object AudioConfig {
    const val SAMPLE_RATE = 16_000
    const val FRAME_MILLIS = 20
    const val FRAME_SAMPLES = SAMPLE_RATE * FRAME_MILLIS / 1000   // 320
}
