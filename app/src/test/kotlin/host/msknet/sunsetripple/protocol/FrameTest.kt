package host.msknet.sunsetripple.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class FrameTest {

    @Test
    fun `编码后解码还原所有字段`() {
        val f = Frame(FrameType.AUDIO, 3, 65535, byteArrayOf(1, 2, 3))
        val d = Frame.decode(f.encode())
        assertEquals(FrameType.AUDIO, d.type)
        assertEquals(3, d.senderId)
        assertEquals(65535, d.seq)
        assertArrayEquals(byteArrayOf(1, 2, 3), d.payload)
    }

    @Test
    fun `空负载帧`() {
        val d = Frame.decode(Frame(FrameType.LEAVE, 255, 0, ByteArray(0)).encode())
        assertEquals(FrameType.LEAVE, d.type)
        assertEquals(255, d.senderId)
        assertEquals(0, d.payload.size)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `头部声明长度超出实际数据抛异常`() {
        val bytes = Frame(FrameType.AUDIO, 1, 1, byteArrayOf(9, 9)).encode()
        Frame.decode(bytes.copyOfRange(0, bytes.size - 1))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `未知帧类型抛异常`() {
        Frame.decode(byteArrayOf(99, 0, 0, 0, 0, 0))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `负载超过上限拒绝构造`() {
        Frame(FrameType.AUDIO, 0, 0, ByteArray(Frame.MAX_PAYLOAD + 1))
    }
}
