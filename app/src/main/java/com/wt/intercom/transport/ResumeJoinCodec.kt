package com.wt.intercom.transport

import com.wt.intercom.protocol.Frame
import com.wt.intercom.session.RosterCodec
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

data class ResumeJoin(
    val token: ByteArray,
    val nickname: String,
    val endpoint: String? = null,
)

object ResumeJoinCodec {
    private const val VERSION_1 = 1
    private const val VERSION_2 = 2
    private const val TOKEN_BYTES = 16
    private const val PREFIX_BYTES = 1 + TOKEN_BYTES

    fun encode(token: ByteArray, nickname: String, endpoint: String? = null): ByteArray {
        require(token.size == TOKEN_BYTES) { "resumeToken 必须为 16 字节" }
        val nick = RosterCodec.truncateNickname(nickname).toByteArray(Charsets.UTF_8)
        val payload = if (endpoint == null) {
            byteArrayOf(VERSION_1.toByte()) + token + nick
        } else {
            require(endpoint.isNotBlank()) { "JOIN 端点不能为空" }
            require(endpoint.all { it.code in 1..0x7F }) { "JOIN 端点必须为 ASCII" }
            val endpointBytes = endpoint.toByteArray(Charsets.US_ASCII)
            require(endpointBytes.size <= 255) { "JOIN 端点过长: ${endpointBytes.size}" }
            byteArrayOf(VERSION_2.toByte()) + token + endpointBytes.size.toByte() + endpointBytes + nick
        }
        require(payload.size <= Frame.MAX_PAYLOAD) { "JOIN 载荷超上限: ${payload.size}" }
        return payload
    }

    fun decode(payload: ByteArray): ResumeJoin {
        require(payload.size <= Frame.MAX_PAYLOAD) { "JOIN 载荷超上限: ${payload.size}" }
        require(payload.size >= PREFIX_BYTES) { "JOIN 载荷不足 token" }
        val version = payload[0].toInt() and 0xFF
        require(version == VERSION_1 || version == VERSION_2) { "不支持的 JOIN 版本" }
        val endpoint: String?
        val nicknameOffset: Int
        if (version == VERSION_1) {
            endpoint = null
            nicknameOffset = PREFIX_BYTES
        } else {
            require(payload.size > PREFIX_BYTES) { "JOIN v2 缺少端点长度" }
            val endpointLength = payload[PREFIX_BYTES].toInt() and 0xFF
            require(endpointLength > 0) { "JOIN 端点不能为空" }
            val endpointStart = PREFIX_BYTES + 1
            require(payload.size - endpointStart >= endpointLength) { "JOIN 端点长度越界" }
            val endpointBytes = payload.copyOfRange(endpointStart, endpointStart + endpointLength)
            require(endpointBytes.all { it.toInt() in 0..0x7F }) { "JOIN 端点不是 ASCII" }
            endpoint = String(endpointBytes, Charsets.US_ASCII)
            nicknameOffset = endpointStart + endpointLength
        }
        val nickname = runCatching {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(payload, nicknameOffset, payload.size - nicknameOffset))
                .toString()
        }.getOrElse { throw IllegalArgumentException("JOIN 昵称不是合法 UTF-8", it) }
        return ResumeJoin(
            token = payload.copyOfRange(1, PREFIX_BYTES),
            nickname = RosterCodec.truncateNickname(nickname),
            endpoint = endpoint,
        )
    }
}
