package com.wt.intercom.session

import org.junit.Assert.assertEquals
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
}
