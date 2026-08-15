package com.wt.intercom.session

import com.wt.intercom.audio.AudioConfig
import com.wt.intercom.audio.AudioEngine
import com.wt.intercom.audio.AudioIo
import com.wt.intercom.audio.EngineAudioIo
import com.wt.intercom.audio.JitterBuffer
import com.wt.intercom.audio.OpusCodec
import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.HostTransferPlan
import com.wt.intercom.transport.bluetooth.BluetoothRoomTransport
import com.wt.intercom.transport.bluetooth.BluetoothRoomTransportListener
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

internal interface BluetoothAudioCodec {
    fun encode(pcm: ShortArray): ByteArray
    fun decode(packet: ByteArray?): ShortArray
}

private class OpusBluetoothAudioCodec(bitrate: Int) : BluetoothAudioCodec {
    private val codec = OpusCodec(bitrate)
    override fun encode(pcm: ShortArray): ByteArray = codec.encode(pcm)
    override fun decode(packet: ByteArray?): ShortArray = codec.decode(packet)
}

/** 蓝牙星型 PTT 会话：隐藏采集门控、逐流解码与主机个性化下行混音。 */
class BluetoothRoomSession(
    private val selfNickname: String,
) : BluetoothRoomTransportListener {

    private val _state = MutableStateFlow(RoomUiState())
    val state: StateFlow<RoomUiState> = _state

    internal var audioIoFactory: (((ShortArray) -> Unit), (Throwable) -> Unit) -> AudioIo =
        { onPcm, onFatalError ->
            EngineAudioIo(AudioEngine(onFatalError = onFatalError, onPcmFrame = onPcm))
        }
    internal var codecFactory: (Int) -> BluetoothAudioCodec = ::OpusBluetoothAudioCodec
    internal var jitterFactory: () -> JitterBuffer = { JitterBuffer() }

    private class RemoteStream(
        val member: MemberInfo,
        val jitter: JitterBuffer,
        val decoder: BluetoothAudioCodec,
    )

    private val lock = Any()
    private val lifecycleLock = Any()
    private val remotes = linkedMapOf<Int, RemoteStream>()
    private val pttStates = linkedMapOf<Int, Boolean>()
    private val downlinkEncoders = linkedMapOf<Int, BluetoothAudioCodec>()
    private val downlinkSeq = linkedMapOf<Int, Int>()
    private val presenceById = linkedMapOf<Int, MemberPresence>()
    private val started = AtomicBoolean(false)
    private val stopped = AtomicBoolean(false)
    @Volatile private var running = false
    @Volatile private var pttPressed = false
    @Volatile private var audioFocusInterrupted = false
    @Volatile private var selfId = -1
    @Volatile private var transport: BluetoothRoomTransport? = null
    @Volatile private var recoverySnapshot: HostTransferPlan? = null
    @Volatile private var audio: AudioIo? = null
    @Volatile private var playbackThread: Thread? = null
    private val pendingHostPcm = AtomicReference<ShortArray?>()
    private lateinit var uplinkEncoder: BluetoothAudioCodec
    private var signalSeq = 0
    private var uplinkSeq = 0

    fun start(transport: BluetoothRoomTransport) {
        check(started.compareAndSet(false, true)) { "BluetoothRoomSession 已启动" }
        check(!stopped.get()) { "BluetoothRoomSession 已结束" }
        this.transport = transport
        uplinkEncoder = codecFactory(BLUETOOTH_BITRATE)
        val device = audioIoFactory(::onPcmCaptured, ::onAudioFatalError)
        audio = device
        running = true
        try {
            transport.start()
            synchronized(lifecycleLock) {
                if (stopped.get()) return
                device.start()
                if (stopped.get()) return
                playbackThread = Thread(::playbackLoop, "bluetooth-room-playback").apply { start() }
            }
        } catch (e: Throwable) {
            shutdown(null)
            throw e
        }
    }

    fun setPttPressed(pressed: Boolean) {
        if (pressed && audioFocusInterrupted) return
        if (pttPressed == pressed) return
        pttPressed = pressed
        if (!pressed) pendingHostPcm.set(null)
        val id = selfId
        if (id >= 0 && running) {
            transport?.broadcastSignal(
                Frame(FrameType.PTT_STATE, id, nextSignalSeq(), PttStateCodec.encode(pressed)),
            )
        }
        publishState()
    }

    fun setAudioFocusInterrupted(interrupted: Boolean) {
        audioFocusInterrupted = interrupted
        if (interrupted) setPttPressed(false)
        publishState()
    }

    private fun onPcmCaptured(pcm: ShortArray) {
        if (!running || !pttPressed) return
        val id = selfId
        if (id < 0) return
        if (transport?.isHost == true) {
            pendingHostPcm.set(pcm.copyOf())
        } else {
            runCatching {
                transport?.sendTo(
                    HOST_ID,
                    Frame(FrameType.AUDIO, id, nextUplinkSeq(), uplinkEncoder.encode(pcm)),
                )
            }.onFailure { shutdown("发送失败") }
        }
    }

    private fun onAudioFatalError(error: Throwable) {
        TransportLog.w("蓝牙房音频采集失败: ${error.message}", error)
        shutdown("音频采集失败")
    }

    private fun playbackLoop() {
        val silence = ShortArray(AudioConfig.FRAME_SAMPLES)
        while (running) {
            try {
                if (transport?.isHost == true) hostPlaybackTick(silence) else clientPlaybackTick(silence)
            } catch (e: Exception) {
                TransportLog.w("蓝牙房音频播放失败: ${e.message}", e)
                shutdown("音频播放失败")
                break
            }
            publishState()
        }
    }

    private fun hostPlaybackTick(silence: ShortArray) {
        val streams = synchronized(lock) { remotes.values.toList() }
        val remotePcm = linkedMapOf<Int, ShortArray>()
        for (stream in streams) {
            if (synchronized(lock) { pttStates[stream.member.id] != true }) continue
            val packet = stream.jitter.poll()
            if (packet == null && !stream.jitter.hasStarted()) continue
            remotePcm[stream.member.id] = stream.decoder.decode(packet)
        }
        val memberIds = synchronized(lock) { remotes.keys.toSet() }
        val hostPcm = pendingHostPcm.getAndSet(null)?.takeIf { pttPressed }
        val plan = BluetoothMixPlanner.plan(
            memberIds = memberIds,
            remotePcm = remotePcm,
            hostPcm = hostPcm,
            frameSamples = AudioConfig.FRAME_SAMPLES,
        )
        audio?.playPcm(if (pttPressed) silence else plan.hostPlayback)
        for ((memberId, pcm) in plan.downlinks) {
            if (hostPcm == null && remotePcm.keys.none { it != memberId }) continue
            val encoder = synchronized(lock) {
                downlinkEncoders.getOrPut(memberId) { codecFactory(BLUETOOTH_BITRATE) }
            }
            transport?.sendTo(
                memberId,
                Frame(FrameType.AUDIO, HOST_ID, nextDownlinkSeq(memberId), encoder.encode(pcm)),
            )
        }
    }

    private fun clientPlaybackTick(silence: ShortArray) {
        val host = synchronized(lock) { remotes[HOST_ID] }
        val packet = host?.jitter?.poll()
        val pcm = when {
            pttPressed -> silence
            host == null -> silence
            packet == null && !host.jitter.hasStarted() -> silence
            else -> host.decoder.decode(packet)
        }
        audio?.playPcm(pcm)
    }

    override fun onFrame(frame: Frame) {
        when (frame.type) {
            FrameType.AUDIO -> synchronized(lock) {
                remotes[frame.senderId]?.jitter?.put(frame.seq, frame.payload)
            }
            FrameType.PTT_STATE -> {
                val pressed = runCatching { PttStateCodec.decode(frame.payload) }.getOrNull() ?: return
                synchronized(lock) {
                    val wasPressed = pttStates[frame.senderId] == true
                    pttStates[frame.senderId] = pressed
                    if (pressed && !wasPressed) {
                        remotes[frame.senderId]?.let { previous ->
                            remotes[frame.senderId] = RemoteStream(
                                previous.member,
                                jitterFactory(),
                                codecFactory(BLUETOOTH_BITRATE),
                            )
                        }
                    }
                }
                if (transport?.isHost == true) transport?.broadcastSignal(frame)
                publishState()
            }
            FrameType.LEAVE -> {
                synchronized(lock) {
                    removeMember(frame.senderId)
                }
                publishState()
            }
            else -> Unit
        }
    }

    override fun onRoster(roster: Roster) {
        selfId = roster.yourId
        synchronized(lock) {
            val alive = roster.members.mapTo(linkedSetOf()) { it.id }
            remotes.keys.filter { it !in alive && presenceById[it] != MemberPresence.RECONNECTING }
                .forEach(::removeMember)
            for (member in roster.members) {
                if (member.id != roster.yourId && member.id !in remotes) {
                    remotes[member.id] = RemoteStream(
                        member,
                        jitterFactory(),
                        codecFactory(BLUETOOTH_BITRATE),
                    )
                }
                pttStates.putIfAbsent(member.id, false)
                if (member.id != roster.yourId) presenceById.putIfAbsent(member.id, MemberPresence.CONNECTED)
            }
        }
        publishState()
    }

    override fun onMemberReconnecting(memberId: Int) {
        synchronized(lock) {
            if (memberId in remotes) {
                presenceById[memberId] = MemberPresence.RECONNECTING
                pttStates[memberId] = false
            }
        }
        publishState()
    }

    override fun onMemberReconnected(memberId: Int) {
        synchronized(lock) {
            if (memberId in remotes) presenceById[memberId] = MemberPresence.CONNECTED
        }
        publishState()
    }

    override fun onMemberReconnectFailed(memberId: Int) {
        synchronized(lock) { removeMember(memberId) }
        publishState()
    }

    override fun onDisconnected(reason: String) {
        val snapshot = recoverySnapshot
        if (transport?.isHost == false && snapshot != null) {
            onHostTransfer(snapshot)
        } else {
            shutdown(reason)
        }
    }

    override fun onHostTransferSnapshot(plan: HostTransferPlan) {
        if (plan.members.any { it.memberId == selfId }) recoverySnapshot = plan
    }

    override fun onHostTransfer(plan: HostTransferPlan) {
        shutdown(null)
        _state.value = _state.value.copy(hostTransfer = plan)
    }

    fun leave() {
        val id = selfId
        val handoff = if (transport?.isHost == true) {
            runCatching { transport?.prepareHostTransfer() }.getOrNull()
        } else null
        if (id >= 0 && handoff == null) {
            runCatching {
                transport?.broadcastSignal(Frame(FrameType.LEAVE, id, nextSignalSeq(), ByteArray(0)))
            }
        }
        shutdown(null)
    }

    private fun shutdown(reason: String?) {
        if (stopped.compareAndSet(false, true)) {
            running = false
            val (thread, device, roomTransport) = synchronized(lifecycleLock) {
                Triple(playbackThread, audio, transport).also {
                    playbackThread = null
                    audio = null
                    transport = null
                }
            }
            thread?.takeIf { it != Thread.currentThread() }?.join(500)
            runCatching { device?.stop() }
            runCatching { roomTransport?.close() }
        }
        val current = _state.value
        _state.value = current.copy(connected = false, endedReason = current.endedReason ?: reason)
    }

    private fun publishState() {
        val members = synchronized(lock) {
            buildList {
                if (selfId >= 0) add(MemberUi(selfId, selfNickname, pttPressed, true))
                remotes.values.forEach { remote ->
                    val presence = presenceById[remote.member.id] ?: MemberPresence.CONNECTED
                    add(MemberUi(
                        remote.member.id,
                        remote.member.nickname,
                        pttStates[remote.member.id] == true && presence == MemberPresence.CONNECTED,
                        false,
                        presence,
                    ))
                }
            }
        }
        _state.value = RoomUiState(
            connected = running && selfId >= 0,
            members = members,
            audioFocusInterrupted = audioFocusInterrupted,
            pttPressed = pttPressed,
            endedReason = _state.value.endedReason,
            hostTransfer = _state.value.hostTransfer,
        )
    }

    @Synchronized
    private fun nextSignalSeq(): Int = signalSeq.also { signalSeq = (signalSeq + 1) and 0xFFFF }

    @Synchronized
    private fun nextUplinkSeq(): Int = uplinkSeq.also { uplinkSeq = (uplinkSeq + 1) and 0xFFFF }

    private fun nextDownlinkSeq(memberId: Int): Int = synchronized(lock) {
        val current = downlinkSeq[memberId] ?: 0
        downlinkSeq[memberId] = (current + 1) and 0xFFFF
        current
    }

    private fun removeMember(memberId: Int) {
        remotes.remove(memberId)
        pttStates.remove(memberId)
        downlinkEncoders.remove(memberId)
        downlinkSeq.remove(memberId)
        presenceById.remove(memberId)
    }

    private companion object {
        const val HOST_ID = 0
        const val BLUETOOTH_BITRATE = 16_000
    }
}
