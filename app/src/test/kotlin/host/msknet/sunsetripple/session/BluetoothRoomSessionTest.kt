package host.msknet.sunsetripple.session

import host.msknet.sunsetripple.audio.AudioConfig
import host.msknet.sunsetripple.audio.AudioIo
import host.msknet.sunsetripple.audio.JitterBuffer
import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.protocol.FrameType
import host.msknet.sunsetripple.transport.bluetooth.BluetoothRoomTransport
import host.msknet.sunsetripple.transport.HostTransferMember
import host.msknet.sunsetripple.transport.HostTransferPlan
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BluetoothRoomSessionTest {

    private class FakeTransport(override val isHost: Boolean) : BluetoothRoomTransport {
        val directed = CopyOnWriteArrayList<Pair<Int, Frame>>()
        val signals = CopyOnWriteArrayList<Frame>()
        var onStart: () -> Unit = {}
        var onClose: () -> Unit = {}
        var startCount = 0
        var closeCount = 0
        var prepareCount = 0
        var transferPlan: HostTransferPlan? = null
        override fun start() { startCount++; onStart() }
        override fun sendTo(memberId: Int, frame: Frame) { directed += memberId to frame }
        override fun broadcastSignal(frame: Frame) { signals += frame }
        override fun prepareHostTransfer(): HostTransferPlan? {
            prepareCount++
            return transferPlan
        }
        override fun close() { closeCount++; onClose() }
    }

    private class FakeAudioIo(
        val captureCallback: (ShortArray) -> Unit,
        val fatalErrorCallback: (Throwable) -> Unit,
        holdPlayback: Boolean,
    ) : AudioIo {
        override var micMuted = false
        val played = CopyOnWriteArrayList<ShortArray>()
        @Volatile var failPlay = false
        private val playbackGate = CountDownLatch(if (holdPlayback) 1 else 0)
        var startCount = 0
        var stopCount = 0
        override fun start() { startCount++ }
        override fun playPcm(pcm: ShortArray) {
            playbackGate.await()
            played += pcm.copyOf()
            if (failPlay) throw IllegalStateException("AudioTrack write 失败")
            Thread.sleep(1)
        }
        override fun stop() { stopCount++ }
        fun capture(value: Short) = captureCallback(ShortArray(AudioConfig.FRAME_SAMPLES) { value })
        fun releasePlayback() = playbackGate.countDown()
    }

    private class MarkerCodec : BluetoothAudioCodec {
        override fun encode(pcm: ShortArray): ByteArray = byteArrayOf(
            (pcm[0].toInt() ushr 8).toByte(),
            pcm[0].toByte(),
        )

        override fun decode(packet: ByteArray?): ShortArray {
            if (packet == null) return ShortArray(AudioConfig.FRAME_SAMPLES)
            val value = (((packet[0].toInt() and 0xFF) shl 8) or
                (packet[1].toInt() and 0xFF)).toShort()
            return ShortArray(AudioConfig.FRAME_SAMPLES) { value }
        }
    }

    private data class Harness(
        val session: BluetoothRoomSession,
        val transport: FakeTransport,
        val audio: FakeAudioIo,
        val requestedBitrates: List<Int>,
    )

    @Test
    fun `PTT 未按下时采集帧不发送`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1))

        h.audio.capture(100)

        assertTrue(h.transport.directed.isEmpty())
    }

    @Test
    fun `无人按下 PTT 时主机不发送静音下行`() {
        val h = harness(isHost = true, selfId = 0, memberIds = intArrayOf(0, 1, 2))

        Thread.sleep(30)

        assertTrue(h.transport.directed.isEmpty())
    }

    @Test
    fun `按下 PTT 广播状态并以 16 kbps 编码发送`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1))

        h.session.setPttPressed(true)
        h.audio.capture(123)

        assertTrue(PttStateCodec.decode(h.transport.signals.last().payload))
        assertEquals(FrameType.AUDIO, h.transport.directed.last().second.type)
        assertEquals(0, h.transport.directed.last().first)
        assertTrue(h.requestedBitrates.all { it == 16_000 })
    }

    @Test
    fun `松开 PTT 广播 false`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1))
        h.session.setPttPressed(true)

        h.session.setPttPressed(false)

        assertFalse(PttStateCodec.decode(h.transport.signals.last().payload))
    }

    @Test
    fun `UI 状态显式公开本机 PTT 供锁屏通知同步`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1))

        h.session.setPttPressed(true)
        assertTrue(h.session.state.value.pttPressed)

        h.session.setAudioFocusInterrupted(true)
        assertFalse(h.session.state.value.pttPressed)
        h.session.leave()
    }

    @Test
    fun `焦点丢失立即释放 PTT 且恢复后不自动重新按下`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1))

        h.session.setPttPressed(true)
        h.session.setAudioFocusInterrupted(true)
        val signalCountAfterLoss = h.transport.signals.size
        h.session.setPttPressed(true)
        h.session.setAudioFocusInterrupted(false)

        assertFalse(h.session.state.value.members.single { it.isSelf }.speaking)
        assertFalse(PttStateCodec.decode(h.transport.signals.last().payload))
        assertEquals(signalCountAfterLoss, h.transport.signals.size)
        h.session.leave()
    }

    @Test
    fun `音频采集持久性故障可靠结束蓝牙会话且只释放一次`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1))

        h.audio.fatalErrorCallback(IllegalStateException("read=-6"))
        h.session.leave()

        assertEquals("音频采集失败", h.session.state.value.endedReason)
        assertEquals(1, h.audio.stopCount)
        assertEquals(1, h.transport.closeCount)
    }

    @Test
    fun `客户端按住 PTT 时依然正常播放主机下行`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1))
        h.session.setPttPressed(true)
        h.audio.played.clear()

        repeat(3) { seq ->
            h.session.onFrame(Frame(FrameType.AUDIO, 0, seq, MarkerCodec().encode(pcm(500))))
        }
        await("按住期间正常播放主机下行") { h.audio.played.isNotEmpty() }

        assertTrue(h.audio.played.isNotEmpty())
        assertTrue(h.audio.played.any { it.any { sample -> sample == 500.toShort() } })
    }

    @Test
    fun `主机下行排除收件人自己的声音`() {
        val h = harness(isHost = true, selfId = 0, memberIds = intArrayOf(0, 1, 2), holdPlayback = true)
        h.session.onFrame(Frame(FrameType.PTT_STATE, 1, 0, PttStateCodec.encode(true)))
        h.session.onFrame(Frame(FrameType.PTT_STATE, 2, 0, PttStateCodec.encode(true)))

        h.session.onFrame(Frame(FrameType.AUDIO, 1, 0, MarkerCodec().encode(pcm(100))))
        h.session.onFrame(Frame(FrameType.AUDIO, 2, 0, MarkerCodec().encode(pcm(200))))
        h.audio.releasePlayback()

        await("主机生成排除收件人自己的下行") {
            h.transport.directed.any { it.first == 1 && decodeMarker(it.second.payload) == 200 } &&
                h.transport.directed.any { it.first == 2 && decodeMarker(it.second.payload) == 100 }
        }
        assertTrue(h.transport.directed.any { it.first == 1 && decodeMarker(it.second.payload) == 200 })
        assertTrue(h.transport.directed.any { it.first == 2 && decodeMarker(it.second.payload) == 100 })
    }

    @Test
    fun `主机按下 PTT 后本机语音下发给所有成员`() {
        val h = harness(isHost = true, selfId = 0, memberIds = intArrayOf(0, 1, 2))

        h.session.setPttPressed(true)
        h.audio.capture(10)

        await("所有成员收到主机语音") {
            listOf(1, 2).all { memberId ->
                h.transport.directed.any { it.first == memberId && decodeMarker(it.second.payload) == 10 }
            }
        }
    }

    @Test
    fun `两名成员同时 PTT 时第三名收到饱和混音`() {
        val h = harness(isHost = true, selfId = 0, memberIds = intArrayOf(0, 1, 2, 3), holdPlayback = true)
        h.session.onFrame(Frame(FrameType.PTT_STATE, 1, 0, PttStateCodec.encode(true)))
        h.session.onFrame(Frame(FrameType.PTT_STATE, 2, 0, PttStateCodec.encode(true)))
        h.session.onFrame(Frame(FrameType.AUDIO, 1, 0, MarkerCodec().encode(pcm(30_000))))
        h.session.onFrame(Frame(FrameType.AUDIO, 2, 0, MarkerCodec().encode(pcm(30_000))))

        h.audio.releasePlayback()

        await("第三名收到饱和混音") {
            h.transport.directed.any { it.first == 3 && decodeMarker(it.second.payload) == 32_767 }
        }
    }

    @Test
    fun `PTT 状态直接更新成员 speaking`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1, 2))

        h.session.onFrame(Frame(FrameType.PTT_STATE, 2, 0, PttStateCodec.encode(true)))
        assertTrue(h.session.state.value.members.first { it.id == 2 }.speaking)

        h.session.onFrame(Frame(FrameType.PTT_STATE, 2, 1, PttStateCodec.encode(false)))
        assertFalse(h.session.state.value.members.first { it.id == 2 }.speaking)
    }

    @Test
    fun `蓝牙成员临时断线保留到重连失败且恢复会清除重连态`() {
        val h = harness(isHost = true, selfId = 0, memberIds = intArrayOf(0, 1, 2))

        h.session.onMemberReconnecting(2)
        h.session.onRoster(Roster(0, listOf(MemberInfo(0, "用户0", "addr0"), MemberInfo(1, "用户1", "addr1"))))
        assertEquals(MemberPresence.RECONNECTING, h.session.state.value.members.first { it.id == 2 }.presence)

        h.session.onMemberReconnected(2)
        assertEquals(MemberPresence.CONNECTED, h.session.state.value.members.first { it.id == 2 }.presence)

        h.session.onMemberReconnecting(2)
        h.session.onMemberReconnectFailed(2)
        assertFalse(h.session.state.value.members.any { it.id == 2 })
    }

    @Test
    fun `远端重新按下 PTT 不播放上次讲话的缓存`() {
        val h = harness(isHost = true, selfId = 0, memberIds = intArrayOf(0, 1, 2), holdPlayback = true)
        h.session.onFrame(Frame(FrameType.PTT_STATE, 1, 0, PttStateCodec.encode(true)))
        h.session.onFrame(Frame(FrameType.AUDIO, 1, 0, MarkerCodec().encode(pcm(100))))
        h.session.onFrame(Frame(FrameType.PTT_STATE, 1, 1, PttStateCodec.encode(false)))
        h.session.onFrame(Frame(FrameType.PTT_STATE, 1, 2, PttStateCodec.encode(true)))
        h.session.onFrame(Frame(FrameType.AUDIO, 1, 1, MarkerCodec().encode(pcm(200))))

        h.audio.releasePlayback()

        await("第二次讲话下发") {
            h.transport.directed.any { it.first == 2 && decodeMarker(it.second.payload) == 200 }
        }
        assertFalse(h.transport.directed.any { it.first == 2 && decodeMarker(it.second.payload) == 100 })
    }

    @Test
    fun `主机为每个收件人维护独立连续的音频序号`() {
        val h = harness(isHost = true, selfId = 0, memberIds = intArrayOf(0, 1, 2))

        h.session.setPttPressed(true)
        repeat(3) { index ->
            h.audio.capture((index + 1).toShort())
            await("第 ${index + 1} 帧下行送达每位成员") {
                listOf(1, 2).all { memberId ->
                    h.transport.directed.count {
                        it.first == memberId && it.second.type == FrameType.AUDIO
                    } >= index + 1
                }
            }
        }

        await("每位成员收到至少三帧下行") {
            listOf(1, 2).all { memberId ->
                h.transport.directed.count { it.first == memberId && it.second.type == FrameType.AUDIO } >= 3
            }
        }

        for (memberId in listOf(1, 2)) {
            val seqs = h.transport.directed
                .filter { it.first == memberId && it.second.type == FrameType.AUDIO }
                .take(3)
                .map { it.second.seq }
            assertEquals(listOf(0, 1, 2), seqs)
        }
    }

    @Test
    fun `断线与播放失败并发只释放一次`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1))

        val a = Thread { h.session.onDisconnected("房间已结束") }
        val b = Thread { h.session.leave() }
        a.start(); b.start(); a.join(); b.join()

        assertEquals(1, h.audio.stopCount)
        assertEquals(1, h.transport.closeCount)
        assertFalse(h.session.state.value.connected)
    }

    @Test
    fun `播放失败会幂等停机会话`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1))
        h.audio.failPlay = true

        await("播放失败结束会话") { h.session.state.value.endedReason == "音频播放失败" }

        h.session.onDisconnected("再次断线")
        assertEquals(1, h.audio.stopCount)
        assertEquals(1, h.transport.closeCount)
        assertEquals("音频播放失败", h.session.state.value.endedReason)
    }

    @Test
    fun `传输启动期间同步断线不会在释放后启动音频`() {
        val session = BluetoothRoomSession("我").apply {
            codecFactory = { MarkerCodec() }
            jitterFactory = { JitterBuffer(prebufferFrames = 1) }
        }
        lateinit var audio: FakeAudioIo
        session.audioIoFactory = { callback, onFatalError ->
            FakeAudioIo(callback, onFatalError, false).also { audio = it }
        }
        val transport = FakeTransport(isHost = false).apply {
            onStart = { session.onDisconnected("连接失败") }
        }

        session.start(transport)

        assertEquals(0, audio.startCount)
        assertEquals(1, audio.stopCount)
        assertEquals(1, transport.closeCount)
        assertEquals("连接失败", session.state.value.endedReason)
    }

    @Test
    fun `客户端收到房主交接时关闭旧资源但不标记散会`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1, 2))
        val plan = transferPlan(successorId = 1)

        h.session.onHostTransfer(plan)

        assertEquals(plan, h.session.state.value.hostTransfer)
        assertEquals(null, h.session.state.value.endedReason)
        assertFalse(h.session.state.value.connected)
        assertEquals(1, h.audio.stopCount)
        assertEquals(1, h.transport.closeCount)
    }

    @Test
    fun `蓝牙客户端有房主快照时断线升级为交接`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1, 2))
        val plan = transferPlan(successorId = 1)

        h.session.onHostTransferSnapshot(plan)
        h.session.onDisconnected("旧房主失联")

        assertEquals(plan, h.session.state.value.hostTransfer)
        assertEquals(null, h.session.state.value.endedReason)
        assertFalse(h.session.state.value.connected)
        assertEquals(1, h.audio.stopCount)
        assertEquals(1, h.transport.closeCount)
    }

    @Test
    fun `蓝牙客户端主动离房时忽略关闭链路触发的同步断线回调`() {
        val h = harness(isHost = false, selfId = 1, memberIds = intArrayOf(0, 1, 2))
        h.session.onHostTransferSnapshot(transferPlan(successorId = 1))
        h.transport.onClose = { h.session.onDisconnected("关闭链路") }

        h.session.leave()

        assertNull(h.session.state.value.hostTransfer)
        assertNull(h.session.state.value.endedReason)
        assertEquals(1, h.transport.closeCount)
    }

    @Test
    fun `主机主动离开时先准备交接且不再广播普通 LEAVE`() {
        val h = harness(isHost = true, selfId = 0, memberIds = intArrayOf(0, 1, 2))
        h.transport.transferPlan = transferPlan(successorId = 1)

        h.session.leave()

        assertEquals(1, h.transport.prepareCount)
        assertTrue(h.transport.signals.none { it.type == FrameType.LEAVE })
        assertEquals(1, h.transport.closeCount)
    }

    private fun harness(
        isHost: Boolean,
        selfId: Int,
        memberIds: IntArray,
        holdPlayback: Boolean = false,
    ): Harness {
        val requested = CopyOnWriteArrayList<Int>()
        val session = BluetoothRoomSession("我").apply {
            codecFactory = { bitrate -> requested += bitrate; MarkerCodec() }
            jitterFactory = { JitterBuffer(prebufferFrames = 1) }
        }
        lateinit var audio: FakeAudioIo
        session.audioIoFactory = { callback, onFatalError ->
            FakeAudioIo(callback, onFatalError, holdPlayback).also { audio = it }
        }
        val transport = FakeTransport(isHost)
        session.start(transport)
        session.onRoster(
            Roster(selfId, memberIds.map { MemberInfo(it, "用户$it", "addr$it") }),
        )
        return Harness(session, transport, audio, requested)
    }

    private fun pcm(value: Int) = ShortArray(AudioConfig.FRAME_SAMPLES) { value.toShort() }

    private fun transferPlan(successorId: Int) = HostTransferPlan(
        successorId,
        listOf(
            HostTransferMember(1, 1, "用户1", "addr1"),
            HostTransferMember(2, 2, "用户2", "addr2"),
        ),
    )

    private fun decodeMarker(payload: ByteArray): Int =
        ((((payload[0].toInt() and 0xFF) shl 8) or (payload[1].toInt() and 0xFF)).toShort()).toInt()

    private fun await(what: String, timeoutMs: Long = 2_000, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (System.nanoTime() < deadline) {
            if (condition()) return
            Thread.sleep(5)
        }
        throw AssertionError("等待超时：$what")
    }
}

