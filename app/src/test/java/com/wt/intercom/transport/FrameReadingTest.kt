package com.wt.intercom.transport

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameStreamReader
import com.wt.intercom.protocol.FrameType
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayInputStream

class FrameReadingTest {

    @Test
    fun `正常帧照常读出`() {
        val bytes = Frame(FrameType.AUDIO, 7, 9, byteArrayOf(1, 2)).encode()
        val reader = FrameStreamReader(ByteArrayInputStream(bytes))
        val f = reader.readFrameSafely()!!
        assertEquals(FrameType.AUDIO, f.type)
        assertEquals(7, f.senderId)
        assertArrayEquals(byteArrayOf(1, 2), f.payload)
    }

    @Test
    fun `未知帧类型不抛异常而是返回 null 触发断开`() {
        val bytes = Frame(FrameType.AUDIO, 1, 1, byteArrayOf(9)).encode()
        bytes[0] = 99   // 未知类型字节
        val reader = FrameStreamReader(ByteArrayInputStream(bytes))
        assertNull(reader.readFrameSafely())
    }

    @Test
    fun `未知帧类型会上报协议错误日志`() {
        val logged = ArrayList<String>()
        val prev = TransportLog.sink
        TransportLog.sink = { msg, _ -> logged.add(msg) }
        try {
            val bytes = Frame(FrameType.AUDIO, 1, 1, byteArrayOf(9)).encode()
            bytes[0] = 99
            FrameStreamReader(ByteArrayInputStream(bytes)).readFrameSafely()
        } finally {
            TransportLog.sink = prev
        }
        assertEquals(1, logged.size)
    }

    @Test
    fun `断流返回 null`() {
        assertNull(FrameStreamReader(ByteArrayInputStream(ByteArray(0))).readFrameSafely())
    }
}
