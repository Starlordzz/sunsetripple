package com.wt.intercom.transport

import com.wt.intercom.protocol.Frame
import com.wt.intercom.session.RosterCodec
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

data class ResumeJoin(val token: ByteArray, val nickname: String)

object ResumeJoinCodec {
    private const val VERSION = 1
    private const val TOKEN_BYTES = 16
    private const val PREFIX_BYTES = 1 + TOKEN_BYTES

    fun encode(token: ByteArray, nickname: String): ByteArray {
        require(token.size == TOKEN_BYTES) { "resumeToken 必须为 16 字节" }
        val nick = RosterCodec.truncateNickname(nickname).toByteArray(Charsets.UTF_8)
        val payload = byteArrayOf(VERSION.toByte()) + token + nick
        require(payload.size <= Frame.MAX_PAYLOAD) { "JOIN 载荷超上限: ${payload.size}" }
        return payload
    }

    fun decode(payload: ByteArray): ResumeJoin {
        require(payload.size <= Frame.MAX_PAYLOAD) { "JOIN 载荷超上限: ${payload.size}" }
        require(payload.size >= PREFIX_BYTES) { "JOIN 载荷不足 token" }
        require(payload[0].toInt() and 0xFF == VERSION) { "不支持的 JOIN 版本" }
        val nickname = runCatching {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(payload, PREFIX_BYTES, payload.size - PREFIX_BYTES))
                .toString()
        }.getOrElse { throw IllegalArgumentException("JOIN 昵称不是合法 UTF-8", it) }
        return ResumeJoin(
            token = payload.copyOfRange(1, PREFIX_BYTES),
            nickname = RosterCodec.truncateNickname(nickname),
        )
    }
}
