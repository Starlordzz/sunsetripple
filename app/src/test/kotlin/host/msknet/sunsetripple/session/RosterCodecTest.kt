package host.msknet.sunsetripple.session

import host.msknet.sunsetripple.protocol.Frame
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RosterCodecTest {

    @Test
    fun `编码后解码还原成员表与自身ID`() {
        val members = listOf(
            MemberInfo(0, "主机", "192.168.49.1"),
            MemberInfo(1, "小明", "192.168.49.100"),
            MemberInfo(2, "Bob", "192.168.49.101"),
        )
        val roster = RosterCodec.decode(RosterCodec.encode(2, members))
        assertEquals(2, roster.yourId)
        assertEquals(members, roster.members)
    }

    @Test
    fun `中文昵称多字节安全`() {
        val members = listOf(MemberInfo(7, "会议室甲乙丙", "192.168.49.55"))
        val roster = RosterCodec.decode(RosterCodec.encode(7, members))
        assertEquals("会议室甲乙丙", roster.members[0].nickname)
    }

    @Test
    fun `空成员表`() {
        val roster = RosterCodec.decode(RosterCodec.encode(0, emptyList()))
        assertEquals(0, roster.members.size)
    }

    @Test
    fun `昵称恰好60字节不截断`() {
        val nick = "中".repeat(20) // 60 字节
        assertEquals(60, nick.toByteArray(Charsets.UTF_8).size)
        val roster = RosterCodec.decode(RosterCodec.encode(1, listOf(MemberInfo(1, nick, "10.0.0.1"))))
        assertEquals(nick, roster.members[0].nickname)
    }

    @Test
    fun `多字节字符跨60字节边界按字符截断`() {
        val nick = "中".repeat(19) + "😀" // 57 + 4 = 61 字节
        assertEquals(61, nick.toByteArray(Charsets.UTF_8).size)
        val roster = RosterCodec.decode(RosterCodec.encode(1, listOf(MemberInfo(1, nick, "10.0.0.1"))))
        val got = roster.members[0].nickname
        assertEquals("中".repeat(19), got)
        assertTrue("不得出现替换字符", !got.contains('�'))
    }

    @Test
    fun `中文昵称跨边界截断不劈开字符`() {
        val nick = "中".repeat(30) // 90 字节
        val roster = RosterCodec.decode(RosterCodec.encode(1, listOf(MemberInfo(1, nick, "10.0.0.1"))))
        val got = roster.members[0].nickname
        assertEquals("中".repeat(20), got)
        assertTrue(!got.contains('�'))
    }

    @Test
    fun `空昵称往返`() {
        val roster = RosterCodec.decode(RosterCodec.encode(3, listOf(MemberInfo(3, "", "10.0.0.9"))))
        assertEquals("", roster.members[0].nickname)
        assertEquals("10.0.0.9", roster.members[0].ip)
    }

    @Test
    fun `边界ID往返`() {
        val members = listOf(MemberInfo(0, "a", "1.1.1.1"), MemberInfo(255, "b", "2.2.2.2"))
        val roster = RosterCodec.decode(RosterCodec.encode(255, members))
        assertEquals(255, roster.yourId)
        assertEquals(members, roster.members)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `yourId越界抛异常`() {
        RosterCodec.encode(256, emptyList())
    }

    @Test(expected = IllegalArgumentException::class)
    fun `成员ID越界抛异常`() {
        RosterCodec.encode(0, listOf(MemberInfo(256, "a", "1.1.1.1")))
    }

    @Test
    fun `总长超帧上限时encode抛异常`() {
        // 每成员 1+1+60+1+15 = 78 字节，7 人 = 546 + 2 > 512
        val members = (1..7).map { MemberInfo(it, "中".repeat(20), "192.168.100.100") }
        try {
            RosterCodec.encode(1, members)
            throw AssertionError("应抛出 IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("${Frame.MAX_PAYLOAD}"))
        }
    }

    @Test
    fun `合法最大人数不超帧上限`() {
        val members = (1..6).map { MemberInfo(it, "中".repeat(20), "192.168.100.100") }
        assertTrue(RosterCodec.encode(1, members).size <= Frame.MAX_PAYLOAD)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `空载荷decode抛异常`() {
        RosterCodec.decode(ByteArray(0))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `单字节载荷decode抛异常`() {
        RosterCodec.decode(byteArrayOf(1))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `昵称长度超剩余字节decode抛异常`() {
        // yourId=1, count=1, id=1, nickLen=200, 但只剩 3 字节
        RosterCodec.decode(byteArrayOf(1, 1, 1, 200.toByte(), 65, 66, 67))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `IP长度超剩余字节decode抛异常`() {
        // yourId=1, count=1, id=1, nickLen=1, 'A', ipLen=100, 只剩 0 字节
        RosterCodec.decode(byteArrayOf(1, 1, 1, 1, 65, 100))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `成员字段缺失decode抛异常`() {
        RosterCodec.decode(byteArrayOf(1, 2, 1))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `尾部多余字节decode抛异常`() {
        val ok = RosterCodec.encode(1, listOf(MemberInfo(1, "a", "1.1.1.1")))
        RosterCodec.decode(ok + byteArrayOf(9, 9))
    }
}
