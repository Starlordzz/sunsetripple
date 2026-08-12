package com.wt.intercom.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PttStateCodecTest {

    @Test
    fun `按下与松开能往返编解码`() {
        assertTrue(PttStateCodec.decode(PttStateCodec.encode(true)))
        assertFalse(PttStateCodec.decode(PttStateCodec.encode(false)))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `空负载被拒绝`() {
        PttStateCodec.decode(ByteArray(0))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `非布尔字节被拒绝`() {
        PttStateCodec.decode(byteArrayOf(2))
    }
}
