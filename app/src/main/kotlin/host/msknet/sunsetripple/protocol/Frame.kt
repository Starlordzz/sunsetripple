package host.msknet.sunsetripple.protocol

enum class FrameType(val id: Int) {
    AUDIO(1), JOIN(2), ROSTER(3), PTT_STATE(4), PING(5), LEAVE(6), HOST_TRANSFER(7), HOST_SNAPSHOT(8);

    companion object {
        fun from(id: Int): FrameType = entries.firstOrNull { it.id == id }
            ?: throw IllegalArgumentException("未知帧类型 $id")
    }
}

/** 统一二进制帧：[类型 1B][发送者ID 1B][序号 2B][长度 2B][负载]。 */
class Frame(
    val type: FrameType,
    val senderId: Int,
    val seq: Int,
    val payload: ByteArray,
) {
    init {
        require(senderId in 0..255) { "senderId 越界: $senderId" }
        require(seq in 0..65535) { "seq 越界: $seq" }
        require(payload.size <= MAX_PAYLOAD) { "负载超上限: ${payload.size}" }
    }

    fun encode(): ByteArray {
        val out = ByteArray(HEADER_SIZE + payload.size)
        out[0] = type.id.toByte()
        out[1] = senderId.toByte()
        out[2] = (seq ushr 8).toByte()
        out[3] = seq.toByte()
        out[4] = (payload.size ushr 8).toByte()
        out[5] = payload.size.toByte()
        payload.copyInto(out, HEADER_SIZE)
        return out
    }

    companion object {
        const val HEADER_SIZE = 6
        const val MAX_PAYLOAD = 512

        fun decode(bytes: ByteArray): Frame {
            require(bytes.size >= HEADER_SIZE) { "不足一个帧头" }
            val len = ((bytes[4].toInt() and 0xFF) shl 8) or (bytes[5].toInt() and 0xFF)
            require(bytes.size >= HEADER_SIZE + len) { "负载不完整" }
            return Frame(
                FrameType.from(bytes[0].toInt()),
                bytes[1].toInt() and 0xFF,
                ((bytes[2].toInt() and 0xFF) shl 8) or (bytes[3].toInt() and 0xFF),
                bytes.copyOfRange(HEADER_SIZE, HEADER_SIZE + len),
            )
        }
    }
}
