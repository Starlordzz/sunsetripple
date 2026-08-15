package com.wt.intercom.transport

import com.wt.intercom.protocol.Frame
import com.wt.intercom.session.RosterCodec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ResumeJoinCodecTest {

    private val token = ByteArray(16) { it.toByte() }

    @Test
    fun `往返保留 128 位 token 并按 roster 口径截断昵称`() {
        val nickname = "落日".repeat(30)

        val decoded = ResumeJoinCodec.decode(ResumeJoinCodec.encode(token, nickname))

        assertArrayEquals(token, decoded.token)
        assertEquals(RosterCodec.truncateNickname(nickname), decoded.nickname)
        assertEquals(null, decoded.endpoint)
    }

    @Test
    fun `v2 往返保留稳定端点`() {
        val decoded = ResumeJoinCodec.decode(
            ResumeJoinCodec.encode(token, "成员", "AA:BB:CC:DD:EE:FF"),
        )

        assertArrayEquals(token, decoded.token)
        assertEquals("成员", decoded.nickname)
        assertEquals("AA:BB:CC:DD:EE:FF", decoded.endpoint)
    }

    @Test
    fun `decode 继续接受 v1 载荷`() {
        val decoded = ResumeJoinCodec.decode(byteArrayOf(1) + token + "旧成员".toByteArray())

        assertEquals("旧成员", decoded.nickname)
        assertEquals(null, decoded.endpoint)
    }

    @Test
    fun `encode 拒绝非 16 字节 token`() {
        assertFails { ResumeJoinCodec.encode(ByteArray(15), "成员") }
        assertFails { ResumeJoinCodec.encode(ByteArray(17), "成员") }
    }

    @Test
    fun `decode 拒绝错误版本和不足 16 字节 token`() {
        assertFails { ResumeJoinCodec.decode(byteArrayOf(3) + token + "成员".toByteArray()) }
        assertFails { ResumeJoinCodec.decode(byteArrayOf(1) + ByteArray(15)) }
    }

    @Test
    fun `decode 拒绝超帧载荷和畸形 UTF8`() {
        assertFails { ResumeJoinCodec.decode(ByteArray(Frame.MAX_PAYLOAD + 1)) }
        assertFails { ResumeJoinCodec.decode(byteArrayOf(1) + token + byteArrayOf(0xC3.toByte(), 0x28)) }
        assertFails { ResumeJoinCodec.decode(byteArrayOf(2) + token + byteArrayOf(2, 'a'.code.toByte())) }
        assertFails { ResumeJoinCodec.encode(token, "成员", "端点") }
    }

    @Test
    fun `decode 接受空昵称并复制 token 防止外部改写`() {
        val payload = byteArrayOf(1) + token

        val decoded = ResumeJoinCodec.decode(payload)
        payload[1] = 99

        assertEquals("", decoded.nickname)
        assertEquals(0, decoded.token[0].toInt())
    }

    private fun assertFails(block: () -> Unit) {
        assertTrue(runCatching(block).exceptionOrNull() is IllegalArgumentException)
    }
}
