package host.msknet.sunsetripple.transport

import host.msknet.sunsetripple.protocol.FrameType
import host.msknet.sunsetripple.session.MemberInfo
import host.msknet.sunsetripple.session.RosterCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RosterFramesTest {

    private fun members(n: Int) = (0 until n).map { MemberInfo(it % 256, "u$it", "192.168.49.$it") }

    @Test
    fun `正常成员表编成 ROSTER 帧`() {
        val f = RosterFrames.encode(hostId = 0, yourId = 3, members = members(3))!!
        assertEquals(FrameType.ROSTER, f.type)
        assertEquals(0, f.senderId)
        val roster = RosterCodec.decode(f.payload)
        assertEquals(3, roster.yourId)
        assertEquals(3, roster.members.size)
    }

    @Test
    fun `载荷超上限时返回 null 而非静默吞掉`() {
        assertNull(RosterFrames.encode(hostId = 0, yourId = 1, members = members(60)))
    }

    @Test
    fun `载荷超上限时打日志`() {
        val logged = ArrayList<String>()
        val prev = TransportLog.sink
        TransportLog.sink = { msg, _ -> logged.add(msg) }
        try {
            RosterFrames.encode(hostId = 0, yourId = 1, members = members(60))
        } finally {
            TransportLog.sink = prev
        }
        assertEquals(1, logged.size)
        assertTrue(logged[0].contains("成员表"))
    }
}
