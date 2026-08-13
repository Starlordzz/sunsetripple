package com.wt.intercom.session

import com.wt.intercom.audio.AudioConfig
import com.wt.intercom.audio.AudioEngine
import com.wt.intercom.audio.AudioIo
import com.wt.intercom.audio.EngineAudioIo
import com.wt.intercom.audio.JitterBuffer
import com.wt.intercom.audio.MicGate
import com.wt.intercom.audio.Mixer
import com.wt.intercom.audio.OpusCodec
import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.transport.Transport
import com.wt.intercom.transport.TransportListener
import com.wt.intercom.transport.TransportLog
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class MemberUi(
    val id: Int,
    val nickname: String,
    val speaking: Boolean,
    val isSelf: Boolean,
    val presence: MemberPresence = MemberPresence.CONNECTED,
)

data class RoomUiState(
    val connected: Boolean = false,
    val members: List<MemberUi> = emptyList(),
    val micMuted: Boolean = false,
    val audioFocusInterrupted: Boolean = false,
    val endedReason: String? = null,
)

/**
 * 网状会议会话：自己的麦克风帧编码后广播给全房；
 * 每个远端成员一路 JitterBuffer + 解码器，播放线程逐帧混音。
 * 传输无关——蓝牙房/Nearby 房复用本类。
 *
 * 生命周期是一次性的：[start] 只能调用一次，[shutdown] 之后本对象不可重用。
 */
class RoomSession(private val selfNickname: String) : TransportListener {

    private val _state = MutableStateFlow(RoomUiState())
    val state: StateFlow<RoomUiState> = _state

    @Volatile private var transport: Transport? = null
    @Volatile private var engine: AudioIo? = null
    @Volatile private var playThread: Thread? = null
    @Volatile private var running = false
    @Volatile private var selfId = -1
    private val encoder = OpusCodec()
    private var seq = 0
    private val selfSpeaking = SpeakingDetector()
    private val micGate = MicGate()

    private val started = AtomicBoolean(false)
    private val stopped = AtomicBoolean(false)
    /** 连续发送失败计数；成功一次即清零。 */
    private val sendFailures = AtomicInteger(0)

    /** 测试可替换的音频引擎工厂（入参为采集回调）。 */
    internal var audioIoFactory: (((ShortArray) -> Unit), (Throwable) -> Unit) -> AudioIo =
        { onPcm, onFatalError ->
            EngineAudioIo(AudioEngine(onFatalError = onFatalError, onPcmFrame = onPcm))
        }

    private class RemoteStream(val member: MemberInfo) {
        val jitter = JitterBuffer()
        val decoder = OpusCodec()
        val speaking = SpeakingDetector()
    }

    private val remotes = linkedMapOf<Int, RemoteStream>()   // memberId -> 流（synchronized(remotes) 保护）
    private val presenceById = linkedMapOf<Int, MemberPresence>()

    /** 只接线传输、不启音频。传输层建立连接后即可绑定，音频由 [start] 拉起。 */
    fun attachTransport(transport: Transport) {
        this.transport = transport
    }

    /**
     * 拉起采集与播放。一次性语义：重复调用或已 shutdown 后调用抛 [IllegalStateException]
     * （二次 start 会覆盖 engine/playThread 引用，导致旧 AudioRecord/AudioTrack 泄漏）。
     * 音频设备初始化失败时回滚 running 并释放已建资源后重抛。
     */
    fun start(transport: Transport) {
        check(started.compareAndSet(false, true)) { "RoomSession 已启动，不可重复 start" }
        check(!stopped.get()) { "RoomSession 已结束，不可重用" }
        attachTransport(transport)
        running = true
        val eng = audioIoFactory(::onPcmCaptured, ::onAudioFatalError)
        eng.micMuted = micGate.effectiveMuted
        engine = eng
        try {
            eng.start()
        } catch (e: Throwable) {
            running = false
            engine = null
            runCatching { eng.stop() }
            publishState()
            throw e
        }
        playThread = Thread(::playbackLoop, "room-playback").apply { start() }
    }

    /**
     * 采集回调：整体包异常保护。传输层（如 WiFi socket 半关闭）抛出的异常若穿透，
     * 会打死 AudioEngine 采集线程——麦克风永久哑且 running 仍为 true。
     */
    private fun onPcmCaptured(pcm: ShortArray) {
        val id = selfId
        if (id < 0) return
        runCatching {
            selfSpeaking.feed(pcm)
            transport?.broadcast(Frame(FrameType.AUDIO, id, seq, encoder.encode(pcm)))
            seq = (seq + 1) and 0xFFFF
        }.onSuccess {
            sendFailures.set(0)
        }.onFailure { e ->
            val n = sendFailures.incrementAndGet()
            TransportLog.w("音频帧发送失败（连续 $n 次）: ${e.message}", e)
            if (n >= MAX_SEND_FAILURES) shutdown("发送失败")
        }
    }

    private fun onAudioFatalError(error: Throwable) {
        TransportLog.w("音频采集失败: ${error.message}", error)
        shutdown("音频采集失败")
    }

    private fun playbackLoop() {
        val silence = ShortArray(AudioConfig.FRAME_SAMPLES)
        while (running) {
            // 锁内只做快照，解码/VAD/混音在锁外——避免 Opus 解码占着 remotes 锁阻塞接收线程。
            // 快照后被 retainAll 移除的路，其解码结果本轮仍会被混入，可接受（至多多播一帧）。
            val streams = synchronized(remotes) { remotes.values.toList() }
            val frames = ArrayList<ShortArray>(streams.size)
            for (r in streams) {
                val packet = r.jitter.poll()
                // 必须无条件调用 poll()——started 只在 poll 内部翻转，
                // 把 hasStarted() 当前置条件会自锁（见 M1 P0 修复记录）。
                if (packet == null && !r.jitter.hasStarted()) continue
                val pcm = r.decoder.decode(packet)
                r.speaking.feed(pcm)
                frames.add(pcm)
            }
            try {
                engine?.playPcm(if (frames.isEmpty()) silence else Mixer.mix(frames))
            } catch (e: Exception) {
                TransportLog.w("音频播放失败: ${e.message}", e)
                shutdown("音频播放失败")
                break
            }
            publishState()
        }
    }

    fun setMicMuted(muted: Boolean) {
        micGate.setUserMuted(muted)
        engine?.micMuted = micGate.effectiveMuted
        publishState()
    }

    fun setAudioFocusInterrupted(interrupted: Boolean) {
        micGate.setFocusInterrupted(interrupted)
        engine?.micMuted = micGate.effectiveMuted
        publishState()
    }

    fun leave() {
        val id = selfId
        if (id >= 0) runCatching { transport?.broadcast(Frame(FrameType.LEAVE, id, 0, ByteArray(0))) }
        shutdown(null)
    }

    override fun onFrame(frame: Frame) {
        when (frame.type) {
            FrameType.AUDIO -> synchronized(remotes) {
                remotes[frame.senderId]?.jitter?.put(frame.seq, frame.payload)
            }
            FrameType.LEAVE -> {
                synchronized(remotes) {
                    remotes.remove(frame.senderId)
                    presenceById.remove(frame.senderId)
                }
                publishState()
            }
            else -> Unit   // JOIN/ROSTER/PING 由传输层消化
        }
    }

    override fun onRoster(roster: Roster) {
        selfId = roster.yourId
        synchronized(remotes) {
            val alive = roster.members.map { it.id }.toSet()
            remotes.keys.removeAll { it !in alive && presenceById[it] != MemberPresence.RECONNECTING }
            presenceById.keys.removeAll { it !in remotes && it != roster.yourId }
            for (m in roster.members) {
                if (m.id != roster.yourId) {
                    if (m.id !in remotes) remotes[m.id] = RemoteStream(m)
                    presenceById.putIfAbsent(m.id, MemberPresence.CONNECTED)
                }
            }
        }
        publishState()
    }

    override fun onMemberReconnecting(memberId: Int) {
        synchronized(remotes) {
            if (memberId in remotes) presenceById[memberId] = MemberPresence.RECONNECTING
        }
        publishState()
    }

    override fun onMemberReconnected(memberId: Int) {
        synchronized(remotes) {
            if (memberId in remotes) presenceById[memberId] = MemberPresence.CONNECTED
        }
        publishState()
    }

    override fun onMemberReconnectFailed(memberId: Int) {
        synchronized(remotes) {
            remotes.remove(memberId)
            presenceById.remove(memberId)
        }
        publishState()
    }

    override fun onDisconnected(reason: String) = shutdown(reason)

    /** 测试可见：某远端流当前缓存的包数；该成员不存在时返回 null。 */
    internal fun pendingPacketsFor(memberId: Int): Int? =
        synchronized(remotes) { remotes[memberId]?.jitter?.pendingCount() }

    /**
     * 释放全部资源。leave()（UI 线程）与 onDisconnected()（接收线程）会真实并发，
     * 用 CAS 保证释放只执行一次；状态更新无条件执行，首个非空 reason 生效。
     */
    private fun shutdown(reason: String?) {
        if (stopped.compareAndSet(false, true)) {
            running = false
            // 从采集线程触发时（发送连续失败），engine.stop() 内部对自身线程 join 会等到超时，
            // 不会死锁；播放线程 join 同理受 500ms 上限保护。
            playThread?.takeIf { it != Thread.currentThread() }?.join(500)
            playThread = null
            engine?.stop()
            engine = null
            runCatching { transport?.close() }
            transport = null
        }
        val cur = _state.value
        _state.value = cur.copy(connected = false, endedReason = cur.endedReason ?: reason)
    }

    private fun publishState() {
        val list = ArrayList<MemberUi>()
        if (selfId >= 0) list.add(MemberUi(selfId, selfNickname, selfSpeaking.isSpeaking(), true))
        synchronized(remotes) {
            for (r in remotes.values) {
                val presence = presenceById[r.member.id] ?: MemberPresence.CONNECTED
                list.add(MemberUi(
                    r.member.id,
                    r.member.nickname,
                    r.speaking.isSpeaking() && presence == MemberPresence.CONNECTED,
                    false,
                    presence,
                ))
            }
        }
        _state.value = RoomUiState(
            connected = selfId >= 0 && running,
            members = list,
            micMuted = micGate.userMuted,
            audioFocusInterrupted = micGate.focusInterrupted,
            endedReason = _state.value.endedReason,
        )
    }

    private companion object {
        /** 连续发送失败达此次数即判定链路已死并停机。 */
        const val MAX_SEND_FAILURES = 10
    }
}
