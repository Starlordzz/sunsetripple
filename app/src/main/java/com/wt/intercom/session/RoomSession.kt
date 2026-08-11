package com.wt.intercom.session

import com.wt.intercom.audio.AudioConfig
import com.wt.intercom.audio.AudioEngine
import com.wt.intercom.audio.JitterBuffer
import com.wt.intercom.audio.Mixer
import com.wt.intercom.audio.OpusCodec
import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.transport.Transport
import com.wt.intercom.transport.TransportListener
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class MemberUi(val id: Int, val nickname: String, val speaking: Boolean, val isSelf: Boolean)

data class RoomUiState(
    val connected: Boolean = false,
    val members: List<MemberUi> = emptyList(),
    val micMuted: Boolean = false,
    val endedReason: String? = null,
)

/**
 * 网状会议会话：自己的麦克风帧编码后广播给全房；
 * 每个远端成员一路 JitterBuffer + 解码器，播放线程逐帧混音。
 * 传输无关——蓝牙房/Nearby 房复用本类。
 */
class RoomSession(private val selfNickname: String) : TransportListener {

    private val _state = MutableStateFlow(RoomUiState())
    val state: StateFlow<RoomUiState> = _state

    private var transport: Transport? = null
    private var engine: AudioEngine? = null
    private var playThread: Thread? = null
    @Volatile private var running = false
    @Volatile private var selfId = -1
    private val encoder = OpusCodec()
    private var seq = 0
    private val selfSpeaking = SpeakingDetector()

    private class RemoteStream(val member: MemberInfo) {
        val jitter = JitterBuffer()
        val decoder = OpusCodec()
        val speaking = SpeakingDetector()
    }

    private val remotes = linkedMapOf<Int, RemoteStream>()   // memberId -> 流（synchronized(remotes) 保护）

    /** 只接线传输、不启音频。传输层建立连接后即可绑定，音频由 [start] 拉起。 */
    fun attachTransport(transport: Transport) {
        this.transport = transport
    }

    fun start(transport: Transport) {
        attachTransport(transport)
        running = true
        val eng = AudioEngine { pcm ->
            val id = selfId
            if (id < 0) return@AudioEngine
            selfSpeaking.feed(pcm)
            this.transport?.broadcast(Frame(FrameType.AUDIO, id, seq, encoder.encode(pcm)))
            seq = (seq + 1) and 0xFFFF
        }
        engine = eng
        eng.start()
        playThread = Thread({
            val silence = ShortArray(AudioConfig.FRAME_SAMPLES)
            while (running) {
                val frames = ArrayList<ShortArray>(4)
                synchronized(remotes) {
                    for (r in remotes.values) {
                        val packet = r.jitter.poll()
                        // 必须无条件调用 poll()——started 只在 poll 内部翻转，
                        // 把 hasStarted() 当前置条件会自锁（见 M1 P0 修复记录）。
                        if (packet == null && !r.jitter.hasStarted()) continue
                        val pcm = r.decoder.decode(packet)
                        r.speaking.feed(pcm)
                        frames.add(pcm)
                    }
                }
                eng.playPcm(if (frames.isEmpty()) silence else Mixer.mix(frames))
                publishState()
            }
        }, "room-playback").apply { start() }
    }

    fun setMicMuted(muted: Boolean) {
        engine?.micMuted = muted
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
                synchronized(remotes) { remotes.remove(frame.senderId) }
                publishState()
            }
            else -> Unit   // JOIN/ROSTER/PING 由传输层消化
        }
    }

    override fun onRoster(roster: Roster) {
        selfId = roster.yourId
        synchronized(remotes) {
            val alive = roster.members.map { it.id }.toSet()
            remotes.keys.retainAll(alive)
            for (m in roster.members) {
                if (m.id != roster.yourId && m.id !in remotes) remotes[m.id] = RemoteStream(m)
            }
        }
        publishState()
    }

    override fun onDisconnected(reason: String) = shutdown(reason)

    /** 测试可见：某远端流当前缓存的包数；该成员不存在时返回 null。 */
    internal fun pendingPacketsFor(memberId: Int): Int? =
        synchronized(remotes) { remotes[memberId]?.jitter?.pendingCount() }

    private fun shutdown(reason: String?) {
        val wasRunning = running
        running = false
        if (wasRunning) {
            playThread?.join(500)
            playThread = null
            engine?.stop()
            engine = null
        }
        transport?.close()
        transport = null
        _state.value = _state.value.copy(connected = false, endedReason = reason)
    }

    private fun publishState() {
        val list = ArrayList<MemberUi>()
        if (selfId >= 0) list.add(MemberUi(selfId, selfNickname, selfSpeaking.isSpeaking(), true))
        synchronized(remotes) {
            for (r in remotes.values) {
                list.add(MemberUi(r.member.id, r.member.nickname, r.speaking.isSpeaking(), false))
            }
        }
        _state.value = RoomUiState(
            connected = selfId >= 0 && running,
            members = list,
            micMuted = engine?.micMuted ?: false,
            endedReason = _state.value.endedReason,
        )
    }
}
