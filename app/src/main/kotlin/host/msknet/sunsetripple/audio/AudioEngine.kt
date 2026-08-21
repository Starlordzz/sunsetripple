package host.msknet.sunsetripple.audio

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler

internal class EngineAudioIo(private val engine: AudioEngine) : AudioIo {
    override var micMuted: Boolean
        get() = engine.micMuted
        set(value) { engine.micMuted = value }
    override fun start() = engine.start()
    override fun playPcm(pcm: ShortArray) = engine.playPcm(pcm)
    override fun stop() = engine.stop()
}

/**
 * 麦克风采集 + 扬声器播放。
 * 采集线程每 20ms 回调一帧 PCM；播放由调用方线程经 playPcm 阻塞写入，
 * AudioTrack 的阻塞特性天然提供 20ms 节拍。
 * 音源用 VOICE_COMMUNICATION 以启用系统级回声消除/降噪。
 */
class AudioEngine(
    private val onFatalError: (Throwable) -> Unit = {},
    private val onPcmFrame: (ShortArray) -> Unit,
) {
    @Volatile var micMuted = false
    @Volatile private var running = false
    private var record: AudioRecord? = null
    private var track: AudioTrack? = null
    private var aec: AcousticEchoCanceler? = null
    private var captureThread: Thread? = null
    private val ioLock = Any()

    @SuppressLint("MissingPermission")  // 调用方保证已获 RECORD_AUDIO
    fun start() {
        val minRec = AudioRecord.getMinBufferSize(
            AudioConfig.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            AudioConfig.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minRec, AudioConfig.FRAME_SAMPLES * 4))
        val minPlay = AudioTrack.getMinBufferSize(
            AudioConfig.SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val trk: AudioTrack
        try {
            trk = AudioTrack(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
                AudioFormat.Builder()
                    .setSampleRate(AudioConfig.SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
                maxOf(minPlay, AudioConfig.FRAME_SAMPLES * 4),
                AudioTrack.MODE_STREAM,
                AudioManager.AUDIO_SESSION_ID_GENERATE)
        } catch (e: Throwable) {
            rec.release()
            throw IllegalStateException("音频输出初始化失败", e)
        }
        if (rec.state != AudioRecord.STATE_INITIALIZED || trk.state != AudioTrack.STATE_INITIALIZED) {
            rec.release(); trk.release()
            throw IllegalStateException("音频设备初始化失败（可能被其他应用占用）")
        }
        if (AcousticEchoCanceler.isAvailable()) {
            aec = AcousticEchoCanceler.create(rec.audioSessionId)?.apply { enabled = true }
        }
        record = rec
        track = trk
        rec.startRecording()
        trk.play()
        running = true
        captureThread = Thread({
            val buf = ShortArray(AudioConfig.FRAME_SAMPLES)
            while (running) {
                var off = 0
                var dead = false
                while (off < buf.size && running) {
                    val n = rec.read(buf, off, buf.size - off)
                    if (n <= 0) {
                        dead = true
                        if (running) {
                            onFatalError(IllegalStateException("音频采集失败: read=$n"))
                        }
                        break
                    }
                    off += n
                }
                if (dead) break   // 持久性错误：退出线程，避免 100% CPU 空转
                if (running && !micMuted) onPcmFrame(buf.copyOf())
            }
        }, "audio-capture").apply { start() }
    }

    /** 阻塞写入一帧待播放 PCM。 */
    fun playPcm(pcm: ShortArray) {
        synchronized(ioLock) {
            val written = track?.write(pcm, 0, pcm.size)
                ?: throw IllegalStateException("音频输出未启动")
            if (written < pcm.size) {
                throw IllegalStateException("音频输出写入失败: $written/${pcm.size}")
            }
        }
    }

    fun stop() {
        running = false
        captureThread?.join(500)
        captureThread = null
        runCatching { track?.stop() }   // 先 stop 解除 playPcm 中可能阻塞的 write，再进锁释放，防止主线程在 ioLock 上挂死
        synchronized(ioLock) {
            aec?.release()
            aec = null
            record?.let { runCatching { it.stop() }; it.release() }
            record = null
            track?.let { runCatching { it.stop() }; it.release() }
            track = null
        }
    }
}
