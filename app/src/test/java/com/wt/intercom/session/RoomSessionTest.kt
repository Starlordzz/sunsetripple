package com.wt.intercom.session

import com.wt.intercom.audio.AudioIo
import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.transport.Transport
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.HostTransferMember
import com.wt.intercom.transport.HostTransferPlan
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class RoomSessionTest {

    private class FakeTransport(override val isHost: Boolean = false) : Transport {
        val sent = ArrayList<Frame>()
        var closed = false
        @Volatile var failSend = false
        var closeCount = 0
        var prepareCount = 0
        var transferPlan: HostTransferPlan? = null
        override fun broadcast(frame: Frame) {
            if (failSend) throw IOException("socket 已半关闭")
            sent.add(frame)
        }
        override fun close() { closed = true; closeCount++ }
        override fun prepareHostTransfer(): HostTransferPlan? {
            prepareCount++
            return transferPlan
        }
    }

    /** 假音频引擎：不碰 Android 设备，暴露采集回调供测试手动触发。 */
    private class FakeAudioIo(
        val onPcm: (ShortArray) -> Unit,
        val onFatalError: (Throwable) -> Unit,
        private val failOnStart: Boolean = false,
    ) : AudioIo {
        override var micMuted = false
        @Volatile var failPlay = false
        var started = false
        var stopCount = 0
        override fun start() {
            if (failOnStart) throw IllegalStateException("音频设备初始化失败")
            started = true
        }
        override fun playPcm(pcm: ShortArray) {
            Thread.sleep(1)
            if (failPlay) throw IllegalStateException("AudioTrack write 失败")
        }
        override fun stop() { stopCount++ }
    }

    private fun sessionWithFakeIo(failOnStart: Boolean = false): Pair<RoomSession, () -> FakeAudioIo?> {
        val s = RoomSession("我")
        var io: FakeAudioIo? = null
        s.audioIoFactory = { cb, onFatalError ->
            FakeAudioIo(cb, onFatalError, failOnStart).also { io = it }
        }
        return s to { io }
    }

    private fun roster(yourId: Int, vararg ids: Int) =
        Roster(yourId, ids.map { MemberInfo(it, "用户$it", "192.168.49.$it") })

    @Test
    fun `收到成员表后自己与远端都出现在 UI 状态里`() {
        val s = RoomSession("我")
        s.onRoster(roster(1, 1, 2, 3))
        val members = s.state.value.members
        assertEquals(listOf(1, 2, 3), members.map { it.id })
        assertTrue(members.first { it.id == 1 }.isSelf)
        assertEquals("我", members.first { it.id == 1 }.nickname)
        assertEquals("用户2", members.first { it.id == 2 }.nickname)
        assertFalse(members.first { it.id == 2 }.isSelf)
    }

    @Test
    fun `成员表更新会移除已离开成员并保留原有流`() {
        val s = RoomSession("我")
        s.onRoster(roster(1, 1, 2, 3))
        s.onFrame(Frame(FrameType.AUDIO, 2, 0, ByteArray(3)))
        s.onRoster(roster(1, 1, 2))
        assertEquals(listOf(1, 2), s.state.value.members.map { it.id })
        assertEquals(1, s.pendingPacketsFor(2))   // 流未被重建，缓存仍在
    }

    @Test
    fun `成员临时断线时保留为重连中恢复后回到已连接`() {
        val s = RoomSession("我")
        s.onRoster(roster(1, 1, 2, 3))

        s.onMemberReconnecting(3)
        s.onRoster(roster(1, 1, 2))

        assertEquals(MemberPresence.RECONNECTING, s.state.value.members.first { it.id == 3 }.presence)

        s.onMemberReconnected(3)

        assertEquals(MemberPresence.CONNECTED, s.state.value.members.first { it.id == 3 }.presence)
    }

    @Test
    fun `成员重连最终失败才从列表移除`() {
        val s = RoomSession("我")
        s.onRoster(roster(1, 1, 2))

        s.onMemberReconnecting(2)
        assertTrue(s.state.value.members.any { it.id == 2 })

        s.onMemberReconnectFailed(2)

        assertFalse(s.state.value.members.any { it.id == 2 })
    }

    @Test
    fun `AUDIO 帧进入对应成员的抖动缓冲`() {
        val s = RoomSession("我")
        s.onRoster(roster(1, 1, 2))
        s.onFrame(Frame(FrameType.AUDIO, 2, 0, ByteArray(4)))
        s.onFrame(Frame(FrameType.AUDIO, 2, 1, ByteArray(4)))
        assertEquals(2, s.pendingPacketsFor(2))
    }

    @Test
    fun `未知发送者的 AUDIO 帧被忽略`() {
        val s = RoomSession("我")
        s.onRoster(roster(1, 1, 2))
        s.onFrame(Frame(FrameType.AUDIO, 9, 0, ByteArray(4)))
        assertNull(s.pendingPacketsFor(9))
    }

    @Test
    fun `LEAVE 帧移除成员`() {
        val s = RoomSession("我")
        s.onRoster(roster(1, 1, 2, 3))
        s.onFrame(Frame(FrameType.LEAVE, 3, 0, ByteArray(0)))
        assertEquals(listOf(1, 2), s.state.value.members.map { it.id })
    }

    @Test
    fun `leave 会广播 LEAVE 帧并关闭传输`() {
        val s = RoomSession("我")
        val t = FakeTransport()
        s.attachTransport(t)
        s.onRoster(roster(5, 5, 6))
        s.leave()
        assertEquals(1, t.sent.size)
        assertEquals(FrameType.LEAVE, t.sent[0].type)
        assertEquals(5, t.sent[0].senderId)
        assertTrue(t.closed)
        assertFalse(s.state.value.connected)
    }

    @Test
    fun `焦点恢复保留用户静音且状态区分焦点中断`() {
        val (s, io) = sessionWithFakeIo()
        s.start(FakeTransport())
        s.onRoster(roster(1, 1, 2))

        s.setMicMuted(true)
        s.setAudioFocusInterrupted(true)
        s.setAudioFocusInterrupted(false)

        assertTrue(io()!!.micMuted)
        assertTrue(s.state.value.micMuted)
        assertFalse(s.state.value.audioFocusInterrupted)
        s.leave()
    }

    @Test
    fun `启动前已失去焦点时新音频设备保持静音`() {
        val (s, io) = sessionWithFakeIo()
        s.setAudioFocusInterrupted(true)

        s.start(FakeTransport())

        assertTrue(io()!!.micMuted)
        assertTrue(s.state.value.audioFocusInterrupted)
        s.leave()
    }

    @Test
    fun `音频采集持久性故障可靠结束会话且只释放一次`() {
        val (s, io) = sessionWithFakeIo()
        val t = FakeTransport()
        s.start(t)
        s.onRoster(roster(1, 1, 2))

        io()!!.onFatalError(IllegalStateException("read=-6"))
        s.leave()

        assertEquals("音频采集失败", s.state.value.endedReason)
        assertEquals(1, io()!!.stopCount)
        assertEquals(1, t.closeCount)
    }

    @Test
    fun `断开连接记录原因且置为未连接`() {
        val s = RoomSession("我")
        s.onRoster(roster(1, 1, 2))
        s.onDisconnected("对端断开")
        assertEquals("对端断开", s.state.value.endedReason)
        assertFalse(s.state.value.connected)
    }

    @Test
    fun `客户端有房主快照时断线升级为交接而不是散会`() {
        val (s, io) = sessionWithFakeIo()
        val t = FakeTransport(isHost = false)
        val plan = transferPlan()
        s.start(t)
        s.onRoster(roster(1, 0, 1, 2))

        s.onHostTransferSnapshot(plan)
        s.onDisconnected("旧房主失联")

        assertEquals(plan, s.state.value.hostTransfer)
        assertNull(s.state.value.endedReason)
        assertFalse(s.state.value.connected)
        assertEquals(1, io()!!.stopCount)
        assertEquals(1, t.closeCount)
    }

    @Test
    fun `不含本机的房主快照不会触发异常交接`() {
        val (s, _) = sessionWithFakeIo()
        val t = FakeTransport(isHost = false)
        s.start(t)
        s.onRoster(roster(3, 0, 3))

        s.onHostTransferSnapshot(transferPlan())
        s.onDisconnected("旧房主失联")

        assertNull(s.state.value.hostTransfer)
        assertEquals("旧房主失联", s.state.value.endedReason)
    }

    @Test
    fun `收到房主交接时关闭旧链路但不记录散会原因`() {
        val (s, io) = sessionWithFakeIo()
        val t = FakeTransport()
        s.start(t)
        s.onRoster(roster(1, 0, 1, 2))
        val plan = transferPlan()

        s.onHostTransfer(plan)

        assertEquals(plan, s.state.value.hostTransfer)
        assertEquals(null, s.state.value.endedReason)
        assertEquals(1, io()!!.stopCount)
        assertEquals(1, t.closeCount)
    }

    @Test
    fun `房主离开准备成功后不广播普通 LEAVE`() {
        val (s, _) = sessionWithFakeIo()
        val t = FakeTransport(isHost = true).apply { transferPlan = transferPlan() }
        s.start(t)
        s.onRoster(roster(0, 0, 1, 2))

        s.leave()

        assertEquals(1, t.prepareCount)
        assertTrue(t.sent.none { it.type == FrameType.LEAVE })
    }

    // ---- 审查修复：采集回调异常保护 / shutdown 幂等 / start 一次性与失败回滚 ----

    private fun pcm() = ShortArray(com.wt.intercom.audio.AudioConfig.FRAME_SAMPLES)

    private fun transferPlan() = HostTransferPlan(
        1,
        listOf(
            HostTransferMember(1, 1, "用户1", "endpoint-1"),
            HostTransferMember(2, 2, "用户2", "endpoint-2"),
        ),
    )

    @Test
    fun `发送异常不穿透采集回调且被告警`() {
        val (s, io) = sessionWithFakeIo()
        val t = FakeTransport()
        val logs = ArrayList<String>()
        val old = TransportLog.sink
        TransportLog.sink = { m, _ -> logs.add(m) }
        try {
            s.start(t)
            s.onRoster(roster(1, 1, 2))
            t.failSend = true
            io()!!.onPcm(pcm())        // 不抛出即为通过
            assertTrue(logs.any { it.contains("发送失败") })
            assertTrue(s.state.value.connected)   // 未达阈值不停机
        } finally {
            TransportLog.sink = old
            s.leave()
        }
    }

    @Test
    fun `连续发送失败达阈值触发停机而中途成功会清零计数`() {
        val (s, io) = sessionWithFakeIo()
        val t = FakeTransport()
        val old = TransportLog.sink
        TransportLog.sink = { _, _ -> }
        try {
            s.start(t)
            s.onRoster(roster(1, 1, 2))
            t.failSend = true
            repeat(9) { io()!!.onPcm(pcm()) }
            assertTrue("9 次尚未达阈值", s.state.value.connected)
            t.failSend = false
            io()!!.onPcm(pcm())                  // 成功一次，计数清零
            t.failSend = true
            repeat(9) { io()!!.onPcm(pcm()) }
            assertTrue("清零后 9 次仍不该停机", s.state.value.connected)
            io()!!.onPcm(pcm())                  // 第 10 次
            assertEquals("发送失败", s.state.value.endedReason)
            assertFalse(s.state.value.connected)
            assertTrue(t.closed)
        } finally {
            TransportLog.sink = old
        }
    }

    @Test
    fun `shutdown 幂等——重复 leave 只释放一次且首个原因生效`() {
        val (s, io) = sessionWithFakeIo()
        val t = FakeTransport()
        s.start(t)
        s.onRoster(roster(1, 1, 2))
        s.onDisconnected("对端断开")
        s.leave()
        s.onDisconnected("又断一次")
        assertEquals(1, io()!!.stopCount)
        assertEquals(1, t.closeCount)
        assertEquals("对端断开", s.state.value.endedReason)
        assertFalse(s.state.value.connected)
    }

    @Test
    fun `leave 与 onDisconnected 并发只释放一次`() {
        repeat(20) {
            val (s, io) = sessionWithFakeIo()
            val t = FakeTransport()
            s.start(t)
            s.onRoster(roster(1, 1, 2))
            val gate = CountDownLatch(1)
            val done = CountDownLatch(2)
            val errors = AtomicInteger(0)
            listOf({ s.leave() }, { s.onDisconnected("对端断开") }).forEach { action ->
                Thread {
                    gate.await()
                    runCatching { action() }.onFailure { errors.incrementAndGet() }
                    done.countDown()
                }.start()
            }
            gate.countDown()
            done.await()
            assertEquals(0, errors.get())
            assertEquals(1, io()!!.stopCount)
            assertEquals(1, t.closeCount)
            assertFalse(s.state.value.connected)
        }
    }

    @Test
    fun `重复 start 被拒绝——旧引擎引用不被覆盖`() {
        val (s, io) = sessionWithFakeIo()
        val t = FakeTransport()
        s.start(t)
        val first = io()!!
        val e = runCatching { s.start(FakeTransport()) }.exceptionOrNull()
        assertTrue(e is IllegalStateException)
        assertSame(first, io()!!)
        assertEquals(0, first.stopCount)
        s.leave()
        assertEquals(1, first.stopCount)
    }

    @Test
    fun `shutdown 之后不可重用`() {
        val (s, _) = sessionWithFakeIo()
        s.attachTransport(FakeTransport())
        s.leave()
        val e = runCatching { s.start(FakeTransport()) }.exceptionOrNull()
        assertNotNull(e)
        assertTrue(e is IllegalStateException)
    }

    @Test
    fun `start 失败回滚 running 并释放已建资源后重抛`() {
        val (s, io) = sessionWithFakeIo(failOnStart = true)
        val t = FakeTransport()
        s.onRoster(roster(1, 1, 2))
        val e = runCatching { s.start(t) }.exceptionOrNull()
        assertTrue(e is IllegalStateException)
        assertEquals(1, io()!!.stopCount)          // 已建资源被释放
        assertFalse(s.state.value.connected)       // running 已回滚
        s.leave()                                  // 收尾仍可正常关闭传输
        assertTrue(t.closed)
    }

    @Test
    fun `音频播放失败时结束会话并关闭传输`() {
        val (s, io) = sessionWithFakeIo()
        val t = FakeTransport()
        s.start(t)
        s.onRoster(roster(1, 1, 2))

        io()!!.failPlay = true

        val deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(2)
        while (s.state.value.endedReason == null && System.nanoTime() < deadline) Thread.sleep(10)
        assertEquals("音频播放失败", s.state.value.endedReason)
        assertFalse(s.state.value.connected)
        assertTrue(t.closed)
    }
}
