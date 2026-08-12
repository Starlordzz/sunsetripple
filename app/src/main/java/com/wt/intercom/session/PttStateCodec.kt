package com.wt.intercom.session

/** 单字节 PTT 状态负载：0=松开，1=按下。 */
object PttStateCodec {
    fun encode(pressed: Boolean): ByteArray = byteArrayOf(if (pressed) 1 else 0)

    fun decode(payload: ByteArray): Boolean {
        require(payload.size == 1) { "PTT_STATE 负载必须为 1 字节" }
        return when (payload[0].toInt()) {
            0 -> false
            1 -> true
            else -> throw IllegalArgumentException("未知 PTT 状态: ${payload[0].toInt() and 0xFF}")
        }
    }
}
