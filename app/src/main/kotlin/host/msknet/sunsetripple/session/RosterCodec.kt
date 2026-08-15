package host.msknet.sunsetripple.session

import host.msknet.sunsetripple.protocol.Frame
import java.io.ByteArrayOutputStream

data class MemberInfo(val id: Int, val nickname: String, val ip: String)

data class Roster(val yourId: Int, val members: List<MemberInfo>)

/** ROSTER 帧载荷编解码。昵称按 UTF-8 截断在 60 字节内，防止载荷超帧上限。 */
object RosterCodec {

    /** 昵称 UTF-8 字节上限。 */
    const val MAX_NICK_BYTES = 60

    /**
     * 按 [encode] 的同一口径截断昵称（<= [MAX_NICK_BYTES] 字节，不劈开多字节字符）。
     * 传输层入表前先过一遍，主机自己看到的昵称才和下发给成员的一致。
     */
    fun truncateNickname(s: String): String =
        String(truncateUtf8(s, MAX_NICK_BYTES), Charsets.UTF_8)

    fun encode(yourId: Int, members: List<MemberInfo>): ByteArray {
        require(yourId in 0..255) { "yourId 越界: $yourId" }
        require(members.size in 0..255) { "成员数越界: ${members.size}" }
        val out = ByteArrayOutputStream()
        out.write(yourId)
        out.write(members.size)
        for (m in members) {
            require(m.id in 0..255) { "成员ID越界: ${m.id}" }
            val nick = truncateUtf8(m.nickname, MAX_NICK_BYTES)
            out.write(m.id)
            out.write(nick.size)
            out.write(nick)
            val ip = m.ip.toByteArray(Charsets.US_ASCII)
            require(ip.size in 0..255) { "IP 长度越界: ${ip.size}" }
            out.write(ip.size)
            out.write(ip)
        }
        val bytes = out.toByteArray()
        require(bytes.size <= Frame.MAX_PAYLOAD) {
            "成员表载荷超上限: ${bytes.size} > ${Frame.MAX_PAYLOAD}（成员数 ${members.size}）"
        }
        return bytes
    }

    fun decode(payload: ByteArray): Roster {
        var i = 0
        require(payload.size >= 2) { "成员表载荷不足帧头: ${payload.size}" }
        val yourId = payload[i++].toInt() and 0xFF
        val count = payload[i++].toInt() and 0xFF
        val members = ArrayList<MemberInfo>(count)
        repeat(count) { idx ->
            require(payload.size - i >= 2) { "成员 $idx 字段不完整" }
            val id = payload[i++].toInt() and 0xFF
            val nickLen = payload[i++].toInt() and 0xFF
            require(payload.size - i >= nickLen) { "成员 $idx 昵称长度越界: $nickLen" }
            val nick = String(payload, i, nickLen, Charsets.UTF_8); i += nickLen
            require(payload.size - i >= 1) { "成员 $idx 缺少 IP 长度" }
            val ipLen = payload[i++].toInt() and 0xFF
            require(payload.size - i >= ipLen) { "成员 $idx IP 长度越界: $ipLen" }
            val ip = String(payload, i, ipLen, Charsets.US_ASCII); i += ipLen
            members.add(MemberInfo(id, nick, ip))
        }
        require(i == payload.size) { "成员表载荷尾部多余 ${payload.size - i} 字节" }
        return Roster(yourId, members)
    }

    /** 按字符边界截断到 <= [maxBytes] 个 UTF-8 字节，不劈开多字节字符或代理对。 */
    private fun truncateUtf8(s: String, maxBytes: Int): ByteArray {
        val full = s.toByteArray(Charsets.UTF_8)
        if (full.size <= maxBytes) return full
        var used = 0
        var end = 0
        while (end < s.length) {
            val cp = s.codePointAt(end)
            val cpChars = Character.charCount(cp)
            val cpBytes = when {
                cp < 0x80 -> 1
                cp < 0x800 -> 2
                cp < 0x10000 -> 3
                else -> 4
            }
            if (used + cpBytes > maxBytes) break
            used += cpBytes
            end += cpChars
        }
        return s.substring(0, end).toByteArray(Charsets.UTF_8)
    }
}
