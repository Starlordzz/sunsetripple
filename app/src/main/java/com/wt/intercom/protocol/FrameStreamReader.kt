package com.wt.intercom.protocol

import java.io.InputStream

/** 从流式连接（TCP/RFCOMM）按长度前缀切出完整帧。阻塞读；断流返回 null。 */
class FrameStreamReader(private val input: InputStream) {

    fun readFrame(): Frame? {
        val header = ByteArray(Frame.HEADER_SIZE)
        if (!readFully(header)) return null
        val len = ((header[4].toInt() and 0xFF) shl 8) or (header[5].toInt() and 0xFF)
        if (len > Frame.MAX_PAYLOAD) return null   // 协议错误，视为断流
        val payload = ByteArray(len)
        if (!readFully(payload)) return null
        return Frame.decode(header + payload)
    }

    private fun readFully(dst: ByteArray): Boolean {
        var off = 0
        while (off < dst.size) {
            val n = input.read(dst, off, dst.size - off)
            if (n < 0) return false
            off += n
        }
        return true
    }
}
