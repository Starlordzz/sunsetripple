package com.wt.intercom.session

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.transport.Transport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RoomSessionTest {

    private class FakeTransport : Transport {
        val sent = ArrayList<Frame>()
        var closed = false
        override fun broadcast(frame: Frame) { sent.add(frame) }
        override fun close() { closed = true }
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
    fun `断开连接记录原因且置为未连接`() {
        val s = RoomSession("我")
        s.onRoster(roster(1, 1, 2))
        s.onDisconnected("对端断开")
        assertEquals("对端断开", s.state.value.endedReason)
        assertFalse(s.state.value.connected)
    }
}
