package host.msknet.sunsetripple

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import host.msknet.sunsetripple.audio.JitterBuffer
import host.msknet.sunsetripple.audio.OpusCodec
import host.msknet.sunsetripple.audio.PollResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/**
 * 「落日后残波」的平台音频通道实现。
 *
 * 整条音频管线都在原生侧，Dart 只负责搬运 Opus 包：
 *
 *   麦克风 → AudioRecord(VOICE_COMMUNICATION + AEC/NS/AGC)
 *          → Opus 编码 → EventChannel 上行给 Dart（附带音量用于波形显示）
 *
 *   Dart 收到远端帧 → submitRemoteFrame → 按发送方分流进各自的 JitterBuffer
 *          → 播放线程每 20ms 取一帧 → Opus 解码（丢包走 PLC）→ 混音 → AudioTrack
 *
 * 之所以不放在 Dart：抖动缓冲和混音必须跟着音频时钟走，Dart 的 Timer.periodic
 * 有调度漂移；而且每帧都跨通道搬运 PCM（640 字节）比搬 Opus 包（约 60 字节）贵一个数量级。
 *
 * 音频参数与已发布的 Kotlin 版 alpha.7 严格一致（16kHz/单声道/20ms/VOIP），
 * 这是两个版本能互相听见的前提。
 */
class PlatformAudioPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "SunsetAudio"

        private const val METHOD_CHANNEL = "host.msknet.sunsetripple/audio"
        private const val EVENT_CHANNEL = "host.msknet.sunsetripple/audio_events"

        private const val SAMPLE_RATE = OpusCodec.SAMPLE_RATE
        private const val SAMPLES_PER_FRAME = OpusCodec.FRAME_SAMPLES // 320
        private const val BYTES_PER_FRAME = SAMPLES_PER_FRAME * 2     // 640

        private const val FRAME_HEADER_SIZE = 6
    }

    /** 一路远端音频流：抖动缓冲 + 它专属的解码器（Opus 解码器有状态，不能共用）。 */
    private class RemoteStream {
        val jitter = JitterBuffer()
        val codec = OpusCodec()
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var eventSink: EventChannel.EventSink? = null

    // 采集
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private val capturing = AtomicBoolean(false)
    private val muted = AtomicBoolean(false)
    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var gainControl: AutomaticGainControl? = null
    private var uplinkCodec: OpusCodec? = null
    private var currentBitrate = OpusCodec.DEFAULT_BITRATE

    // 播放
    private var audioTrack: AudioTrack? = null
    private var playbackThread: Thread? = null
    private val playing = AtomicBoolean(false)
    private val remotes = ConcurrentHashMap<Int, RemoteStream>()
    private var previousAudioMode: Int = AudioManager.MODE_NORMAL
    private var userWantsSpeaker: Boolean = true
    private var preferBuiltinMic: Boolean = false
    private var isDeviceCallbackRegistered = false

    private val audioDeviceCallback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                updateAudioRouting()
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                updateAudioRouting()
            }
        }
    } else null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun dispose() {
        stopCapture()
        stopPlayback()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ------------------------------------------------------------ EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ----------------------------------------------------------- MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startCapture" -> {
                if (!hasMicPermission()) {
                    result.error(
                        "PERMISSION_DENIED",
                        "缺少录音权限（RECORD_AUDIO），无法开启麦克风",
                        null,
                    )
                    return
                }
                currentBitrate = call.argument<Int>("bitrate") ?: OpusCodec.DEFAULT_BITRATE

                // AudioRecord / AudioTrack 的构造、AEC/NS/AGC 挂载、前台服务启动
                // 加起来动辄上百毫秒。MethodChannel 的处理跑在平台线程（= 主线程），
                // 放在这里做会直接卡住 UI，进房动画首当其冲。
                // 挪到后台线程，结果再 post 回主线程回复。
                Thread({
                    val playbackOk = startPlayback()
                    val captureOk = playbackOk && startCapture()
                    // 收尾也在后台做：stopPlayback 会 join 播放线程。
                    if (playbackOk && !captureOk) stopPlayback()

                    mainHandler.post {
                        when {
                            !playbackOk ->
                                result.error("PLAYBACK_FAILED", "扬声器初始化失败", null)
                            !captureOk ->
                                result.error("CAPTURE_FAILED", "麦克风初始化失败，可能被其他应用占用", null)
                            else -> result.success(true)
                        }
                    }
                }, "sunset-audio-start").start()
            }

            "stopCapture" -> {
                // 同理：stopCapture / stopPlayback 各自 join 一条线程，最坏 1 秒，
                // 不能压在主线程上，否则离开房间时界面会僵住。
                Thread({
                    stopCapture()
                    stopPlayback()
                    mainHandler.post { result.success(true) }
                }, "sunset-audio-stop").start()
            }

            // Dart 把收到的整帧（含 6 字节帧头）原样丢过来，这里解析发送方与序号后分流。
            "submitRemoteFrame" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null || data.size < FRAME_HEADER_SIZE) {
                    result.error("BAD_ARGS", "submitRemoteFrame 需要完整的帧字节", null)
                    return
                }
                submitRemoteFrame(data)
                result.success(true)
            }

            "removeRemoteMember" -> {
                val memberId = call.argument<Int>("memberId")
                if (memberId != null) remotes.remove(memberId)
                result.success(true)
            }

            "clearRemoteMembers" -> {
                remotes.clear()
                result.success(true)
            }

            "setBitrate" -> {
                val bitrate = call.argument<Int>("bitrate") ?: OpusCodec.DEFAULT_BITRATE
                currentBitrate = bitrate
                try {
                    uplinkCodec?.setBitrate(bitrate)
                } catch (e: IllegalArgumentException) {
                    result.error("BAD_ARGS", "码率非法：$bitrate", null)
                    return
                }
                result.success(true)
            }

            "stopPlayback" -> {
                stopPlayback()
                result.success(true)
            }

            "setMuted" -> {
                muted.set(call.argument<Boolean>("muted") ?: false)
                result.success(true)
            }

            "setSpeakerphone" -> {
                userWantsSpeaker = call.argument<Boolean>("enabled") ?: true
                updateAudioRouting()
                result.success(true)
            }

            "setUseBuiltinMic" -> {
                preferBuiltinMic = call.argument<Boolean>("useBuiltinMic") ?: false
                updateAudioRouting()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun hasMicPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun submitRemoteFrame(data: ByteArray) {
        val senderId = data[1].toInt() and 0xFF
        val seq = ((data[2].toInt() and 0xFF) shl 8) or (data[3].toInt() and 0xFF)
        val payloadLength = ((data[4].toInt() and 0xFF) shl 8) or (data[5].toInt() and 0xFF)

        if (payloadLength <= 0) return
        if (data.size < FRAME_HEADER_SIZE + payloadLength) {
            Log.w(TAG, "远端帧不完整：声称 $payloadLength 字节，实到 ${data.size - FRAME_HEADER_SIZE}")
            return
        }

        val packet = data.copyOfRange(FRAME_HEADER_SIZE, FRAME_HEADER_SIZE + payloadLength)
        remotes.getOrPut(senderId) { RemoteStream() }.jitter.put(seq, packet)
    }

    // ------------------------------------------------------------------ 采集

    private fun startCapture(): Boolean {
        if (capturing.get()) return true

        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            Log.e(TAG, "getMinBufferSize 返回 $minBuffer，设备不支持 16kHz 单声道采集")
            return false
        }
        val bufferSize = maxOf(minBuffer, BYTES_PER_FRAME * 4)

        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
        } catch (e: Exception) {
            Log.e(TAG, "创建 AudioRecord 失败", e)
            return false
        }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord 未初始化，state=${record.state}")
            record.release()
            return false
        }

        attachEffects(record.audioSessionId)

        previousAudioMode = audioManager.mode

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !isDeviceCallbackRegistered) {
            audioDeviceCallback?.let { audioManager.registerAudioDeviceCallback(it, mainHandler) }
            isDeviceCallbackRegistered = true
        }

        uplinkCodec = OpusCodec(currentBitrate)
        audioRecord = record
        capturing.set(true)

        updateAudioRouting()

        try {
            record.startRecording()
        } catch (e: IllegalStateException) {
            Log.e(TAG, "startRecording 失败", e)
            capturing.set(false)
            releaseCapture()
            return false
        }

        captureThread = Thread({ captureLoop(record) }, "sunset-capture").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }

        IntercomForegroundService.start(context)
        Log.i(TAG, "麦克风已开启（16kHz/mono/20ms，Opus ${currentBitrate}bps）")
        return true
    }

    private fun captureLoop(record: AudioRecord) {
        val pcm = ShortArray(SAMPLES_PER_FRAME)
        var consecutiveErrors = 0
        var offset = 0

        while (capturing.get()) {
            val read = try {
                record.read(pcm, offset, SAMPLES_PER_FRAME - offset)
            } catch (e: Exception) {
                Log.e(TAG, "读取麦克风数据失败", e)
                -1
            }

            if (read < 0) {
                consecutiveErrors++
                Log.w(TAG, "AudioRecord.read 返回 $read (连续 $consecutiveErrors 次)")
                if (consecutiveErrors > 50) {
                    Log.e(TAG, "AudioRecord 连续错误超过阈值，采集中止")
                    capturing.set(false)
                    break
                }
                try { Thread.sleep(20) } catch (_: InterruptedException) {}
                continue
            }

            if (read == 0) {
                try { Thread.sleep(5) } catch (_: InterruptedException) {}
                continue
            }

            consecutiveErrors = 0
            offset += read

            if (offset < SAMPLES_PER_FRAME) {
                // 仅读取部分采样点，继续补齐到整帧
                continue
            }

            // 读满一整帧（320 采样点 / 20ms）
            offset = 0

            if (muted.get()) continue

            val level = rms(pcm)
            val packet = try {
                uplinkCodec?.encode(pcm) ?: continue
            } catch (e: Exception) {
                Log.e(TAG, "Opus 编码失败", e)
                continue
            }

            val event = mapOf<String, Any>("data" to packet, "level" to level)
            mainHandler.post { eventSink?.success(event) }
        }
    }

    /** 归一化响度 0.0~1.0：先求均方，开方后按满量程 32768 归一。 */
    private fun rms(pcm: ShortArray): Double {
        var sum = 0.0
        for (s in pcm) {
            val v = s.toDouble()
            sum += v * v
        }
        return (sqrt(sum / pcm.size) / 32768.0).coerceIn(0.0, 1.0)
    }

    private fun attachEffects(sessionId: Int) {
        if (AcousticEchoCanceler.isAvailable()) {
            echoCanceler = AcousticEchoCanceler.create(sessionId)?.apply { enabled = true }
        } else {
            Log.w(TAG, "设备不支持硬件回声消除，免提时可能啸叫")
        }
        if (NoiseSuppressor.isAvailable()) {
            noiseSuppressor = NoiseSuppressor.create(sessionId)?.apply { enabled = true }
        }
        if (AutomaticGainControl.isAvailable()) {
            gainControl = AutomaticGainControl.create(sessionId)?.apply { enabled = true }
        }
    }

    private fun stopCapture() {
        if (!capturing.getAndSet(false)) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && isDeviceCallbackRegistered) {
            audioDeviceCallback?.let { audioManager.unregisterAudioDeviceCallback(it) }
            isDeviceCallbackRegistered = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        }
        @Suppress("DEPRECATION")
        if (audioManager.isBluetoothScoOn) {
            audioManager.stopBluetoothSco()
            audioManager.isBluetoothScoOn = false
        }

        captureThread?.join(500)
        captureThread = null
        releaseCapture()
        uplinkCodec = null

        audioManager.mode = previousAudioMode
        IntercomForegroundService.stop(context)
        Log.i(TAG, "麦克风已关闭")
    }

    private fun releaseCapture() {
        echoCanceler?.release(); echoCanceler = null
        noiseSuppressor?.release(); noiseSuppressor = null
        gainControl?.release(); gainControl = null

        audioRecord?.let { record ->
            try {
                if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    record.stop()
                }
            } catch (e: IllegalStateException) {
                Log.w(TAG, "停止 AudioRecord 时出错", e)
            }
            record.release()
        }
        audioRecord = null
    }

    // ------------------------------------------------------------------ 播放

    private fun startPlayback(): Boolean {
        if (playing.get()) return true

        val minBuffer = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            Log.e(TAG, "AudioTrack.getMinBufferSize 返回 $minBuffer")
            return false
        }
        val bufferSize = maxOf(minBuffer, BYTES_PER_FRAME * 4)

        val track = try {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } catch (e: Exception) {
            Log.e(TAG, "创建 AudioTrack 失败", e)
            return false
        }

        if (track.state != AudioTrack.STATE_INITIALIZED) {
            Log.e(TAG, "AudioTrack 未初始化，state=${track.state}")
            track.release()
            return false
        }

        audioTrack = track
        playing.set(true)
        track.play()

        updateAudioRouting()

        playbackThread = Thread({ playbackLoop(track) }, "sunset-playback").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }

        Log.i(TAG, "扬声器已就绪（缓冲 $bufferSize 字节）")
        return true
    }

    /**
     * 播放循环。节拍由 AudioTrack 自己决定——写满就阻塞，正好是 20ms 一帧，
     * 不需要额外的定时器，也就没有 Dart 侧 Timer.periodic 的漂移问题。
     * 没人说话时写静音帧，保持时钟连续，避免下次出声时的爆音与欠载。
     */
    private fun playbackLoop(track: AudioTrack) {
        val mix = IntArray(SAMPLES_PER_FRAME)
        val out = ShortArray(SAMPLES_PER_FRAME)
        var consecutiveErrors = 0

        while (playing.get()) {
            java.util.Arrays.fill(mix, 0)
            var contributors = 0

            for ((memberId, stream) in remotes) {
                val pcm = when (val polled = stream.jitter.poll()) {
                    is PollResult.Packet -> decodeSafely(stream, polled.data, memberId)
                    PollResult.Lost -> decodeSafely(stream, null, memberId) // PLC 补帧
                    PollResult.NotReady -> null
                } ?: continue

                for (i in 0 until SAMPLES_PER_FRAME) mix[i] += pcm[i].toInt()
                contributors++
            }

            if (contributors == 0) {
                java.util.Arrays.fill(out, 0)
            } else {
                for (i in 0 until SAMPLES_PER_FRAME) {
                    out[i] = mix[i].coerceIn(-32768, 32767).toShort()
                }
            }

            var offset = 0
            while (offset < SAMPLES_PER_FRAME && playing.get()) {
                val written = try {
                    track.write(out, offset, SAMPLES_PER_FRAME - offset)
                } catch (e: Exception) {
                    Log.e(TAG, "AudioTrack.write 异常", e)
                    -1
                }
                if (written < 0) {
                    consecutiveErrors++
                    Log.w(TAG, "AudioTrack.write 返回 $written (连续 $consecutiveErrors 次)")
                    if (consecutiveErrors > 50) {
                        Log.e(TAG, "AudioTrack 连续写入错误超过阈值，播放中止")
                        playing.set(false)
                        break
                    }
                    try { Thread.sleep(20) } catch (_: InterruptedException) {}
                    break
                }
                if (written == 0) {
                    try { Thread.sleep(5) } catch (_: InterruptedException) {}
                    continue
                }
                consecutiveErrors = 0
                offset += written
            }
        }
    }

    private fun decodeSafely(stream: RemoteStream, packet: ByteArray?, memberId: Int): ShortArray? =
        try {
            stream.codec.decode(packet)
        } catch (e: Exception) {
            Log.w(TAG, "解码成员 $memberId 的音频失败", e)
            null
        }

    private fun stopPlayback() {
        if (!playing.getAndSet(false)) return

        playbackThread?.join(500)
        playbackThread = null
        remotes.clear()

        audioTrack?.let { track ->
            try {
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.stop()
                }
            } catch (e: IllegalStateException) {
                Log.w(TAG, "停止 AudioTrack 时出错", e)
            }
            track.release()
        }
        audioTrack = null
        Log.i(TAG, "扬声器已关闭")
    }

    // ------------------------------------------------------------ 统一路由与设备选择

    @Synchronized
    private fun updateAudioRouting() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val commDevices = audioManager.availableCommunicationDevices
            val inputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            val outputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)

            val btComm = commDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_HEARING_AID
            }
            val wiredComm = commDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE
            }
            val speakerComm = commDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            val earpieceComm = commDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }

            val builtinMic = inputDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
            val externalMic = inputDevices.firstOrNull { dev ->
                dev.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                dev.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                dev.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                dev.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                dev.type == AudioDeviceInfo.TYPE_USB_DEVICE
            }

            val record = audioRecord
            val track = audioTrack

            // 1. 系统级通信设备与模式调度
            if (!preferBuiltinMic && btComm != null) {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.setCommunicationDevice(btComm)
                track?.setPreferredDevice(btComm)
                record?.setPreferredDevice(externalMic ?: btComm)
                Log.i(TAG, "音频路由: 蓝牙通信设备双向绑定 (${btComm.productName})")
            } else if (wiredComm != null) {
                audioManager.mode = AudioManager.MODE_NORMAL
                audioManager.setCommunicationDevice(wiredComm)
                track?.setPreferredDevice(wiredComm)
                if (preferBuiltinMic && builtinMic != null) {
                    record?.setPreferredDevice(builtinMic)
                    Log.i(TAG, "音频路由: 有线/USB耳机输出 + 手机麦拾音")
                } else {
                    record?.setPreferredDevice(externalMic ?: wiredComm)
                    Log.i(TAG, "音频路由: 有线/USB耳机双向绑定 (${wiredComm.productName})")
                }
            } else if (btComm != null) {
                // 蓝牙耳机已连接，但用户选择使用手机麦拾音
                audioManager.mode = AudioManager.MODE_NORMAL
                audioManager.clearCommunicationDevice()
                val btOutput = outputDevices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_HEARING_AID
                }
                track?.setPreferredDevice(btOutput)
                if (builtinMic != null) {
                    record?.setPreferredDevice(builtinMic)
                } else {
                    record?.setPreferredDevice(null)
                }
                Log.i(TAG, "音频路由: 蓝牙媒体通道输出 (A2DP/BLE) + 手机麦拾音")
            } else if (userWantsSpeaker) {
                audioManager.mode = AudioManager.MODE_NORMAL
                if (speakerComm != null) {
                    audioManager.setCommunicationDevice(speakerComm)
                }
                track?.setPreferredDevice(speakerComm)
                record?.setPreferredDevice(builtinMic)
                Log.i(TAG, "音频路由: 手机外放扬声器 + 内置麦克风")
            } else {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                if (earpieceComm != null) {
                    audioManager.setCommunicationDevice(earpieceComm)
                }
                track?.setPreferredDevice(earpieceComm)
                record?.setPreferredDevice(builtinMic)
                Log.i(TAG, "音频路由: 手机听筒 + 内置麦克风")
            }
        } else {
            // API < 31 (Android 6.0 ~ 11)
            @Suppress("DEPRECATION")
            val record = audioRecord
            val track = audioTrack

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val inputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                val outputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                val builtinMic = inputDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
                val externalMic = inputDevices.firstOrNull { dev ->
                    dev.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    dev.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    dev.type == AudioDeviceInfo.TYPE_USB_HEADSET
                }
                if (preferBuiltinMic || externalMic == null) {
                    builtinMic?.let { record?.setPreferredDevice(it) }
                } else {
                    record?.setPreferredDevice(externalMic)
                }

                if (preferBuiltinMic) {
                    val btOutput = outputDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }
                    btOutput?.let { track?.setPreferredDevice(it) }
                }
            }

            @Suppress("DEPRECATION")
            if (!preferBuiltinMic) {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                try {
                    audioManager.startBluetoothSco()
                    audioManager.isBluetoothScoOn = true
                } catch (e: Exception) {
                    Log.w(TAG, "startBluetoothSco 异常", e)
                }
                audioManager.isSpeakerphoneOn = false
            } else if (userWantsSpeaker) {
                if (audioManager.isBluetoothScoOn) {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                }
                audioManager.mode = AudioManager.MODE_NORMAL
                audioManager.isSpeakerphoneOn = true
            } else {
                if (audioManager.isBluetoothScoOn) {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                }
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.isSpeakerphoneOn = false
            }
        }
    }
}