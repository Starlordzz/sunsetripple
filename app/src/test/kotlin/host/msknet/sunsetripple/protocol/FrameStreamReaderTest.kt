package host.msknet.sunsetripple.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.InputStream

class FrameStreamReaderTest {

    /** 模拟 TCP 分片：每次 read 只吐 1 字节。 */
    private class DribbleInputStream(private val data: ByteArray) : InputStream() {
        private var pos = 0
        override fun read(): Int = if (pos < data.size) data[pos++].toInt() and 0xFF else -1
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (pos >= data.size) return -1
            b[off] = data[pos++]
            return 1
        }
    }

    @Test
    fun `连续两帧按序切出后遇 EOF 返回 null`() {
        val f1 = Frame(FrameType.JOIN, 0, 0, "甲".toByteArray(Charsets.UTF_8))
        val f2 = Frame(FrameType.PING, 2, 7, ByteArray(0))
        val reader = FrameStreamReader(ByteArrayInputStream(f1.encode() + f2.encode()))
        val r1 = reader.readFrame()!!
        assertEquals(FrameType.JOIN, r1.type)
        assertArrayEquals("甲".toByteArray(Charsets.UTF_8), r1.payload)
        val r2 = reader.readFrame()!!
        assertEquals(FrameType.PING, r2.type)
        assertEquals(2, r2.senderId)
        assertNull(reader.readFrame())
    }

    @Test
    fun `逐字节到达也能切出完整帧`() {
        val f = Frame(FrameType.AUDIO, 5, 1234, ByteArray(60) { it.toByte() })
        val reader = FrameStreamReader(DribbleInputStream(f.encode()))
        val r = reader.readFrame()!!
        assertEquals(1234, r.seq)
        assertArrayEquals(ByteArray(60) { it.toByte() }, r.payload)
    }

    @Test
    fun `半个帧头遇 EOF 返回 null`() {
        val reader = FrameStreamReader(ByteArrayInputStream(byteArrayOf(1, 0, 0)))
        assertNull(reader.readFrame())
    }
}
