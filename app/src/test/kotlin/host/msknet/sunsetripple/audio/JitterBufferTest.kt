package host.msknet.sunsetripple.audio

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class JitterBufferTest {

    private fun p(v: Int) = byteArrayOf(v.toByte())  // 用单字节区分不同包

    @Test
    fun `攒满预缓冲帧数才开始出帧`() {
        val jb = JitterBuffer(prebufferFrames = 3)
        jb.put(0, p(0)); jb.put(1, p(1))
        assertNull(jb.poll())
        assertFalse(jb.hasStarted())
        jb.put(2, p(2))
        assertArrayEquals(p(0), jb.poll())
        assertTrue(jb.hasStarted())
    }

    @Test
    fun `按序到达按序吐出`() {
        val jb = JitterBuffer(prebufferFrames = 1)
        jb.put(0, p(0))
        assertArrayEquals(p(0), jb.poll())
        jb.put(1, p(1)); jb.put(2, p(2))
        assertArrayEquals(p(1), jb.poll())
        assertArrayEquals(p(2), jb.poll())
    }

    @Test
    fun `乱序到达重排后吐出`() {
        val jb = JitterBuffer(prebufferFrames = 3)
        jb.put(1, p(1)); jb.put(0, p(0)); jb.put(2, p(2))
        assertArrayEquals(p(0), jb.poll())
        assertArrayEquals(p(1), jb.poll())
        assertArrayEquals(p(2), jb.poll())
    }

    @Test
    fun `丢包位置返回 null 之后继续`() {
        val jb = JitterBuffer(prebufferFrames = 1)
        jb.put(0, p(0))
        assertArrayEquals(p(0), jb.poll())
        jb.put(2, p(2))                       // 序号 1 丢失
        assertNull(jb.poll())                 // 1 的位置：null 交给 PLC
        assertArrayEquals(p(2), jb.poll())
    }

    @Test
    fun `迟到帧被丢弃`() {
        val jb = JitterBuffer(prebufferFrames = 1)
        jb.put(0, p(0))
        assertArrayEquals(p(0), jb.poll())
        jb.put(1, p(1))
        jb.put(0, p(9))                       // 已播过的位置迟到
        assertArrayEquals(p(1), jb.poll())    // 不受影响
        assertNull(jb.poll())                 // 迟到帧没有被入队（欠载）
    }

    @Test
    fun `16 位序号回绕不中断`() {
        val jb = JitterBuffer(prebufferFrames = 3)
        jb.put(65534, p(1)); jb.put(65535, p(2)); jb.put(0, p(3))
        assertArrayEquals(p(1), jb.poll())
        assertArrayEquals(p(2), jb.poll())
        assertArrayEquals(p(3), jb.poll())
    }

    @Test
    fun `欠载时不推进等待新包`() {
        val jb = JitterBuffer(prebufferFrames = 1)
        jb.put(0, p(0))
        assertArrayEquals(p(0), jb.poll())
        assertNull(jb.poll())                 // 缓冲空：等待
        jb.put(1, p(1))
        assertArrayEquals(p(1), jb.poll())    // 恢复后不丢帧
    }

    @Test
    fun `积压超上限丢最旧`() {
        val jb = JitterBuffer(prebufferFrames = 1, maxBuffer = 3)
        for (i in 0..5) jb.put(i, p(i))       // 只留 3、4、5
        assertEquals(3, jb.pendingCount())
    }
}
