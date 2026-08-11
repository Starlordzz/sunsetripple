package com.wt.intercom.session

import java.io.ByteArrayOutputStream

data class MemberInfo(val id: Int, val nickname: String, val ip: String)

data class Roster(val yourId: Int, val members: List<MemberInfo>)

/** ROSTER 帧载荷编解码。昵称按 UTF-8 截断在 60 字节内，防止载荷超帧上限。 */
object RosterCodec {

    fun encode(yourId: Int, members: List<MemberInfo>): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(yourId)
        out.write(members.size)
        for (m in members) {
            out.write(m.id)
            val nick = m.nickname.toByteArray(Charsets.UTF_8).let {
                if (it.size > 60) it.copyOf(60) else it
            }
            out.write(nick.size)
            out.write(nick)
            val ip = m.ip.toByteArray(Charsets.US_ASCII)
            out.write(ip.size)
            out.write(ip)
        }
        return out.toByteArray()
    }

    fun decode(payload: ByteArray): Roster {
        var i = 0
        val yourId = payload[i++].toInt() and 0xFF
        val count = payload[i++].toInt() and 0xFF
        val members = ArrayList<MemberInfo>(count)
        repeat(count) {
            val id = payload[i++].toInt() and 0xFF
            val nickLen = payload[i++].toInt() and 0xFF
            val nick = String(payload, i, nickLen, Charsets.UTF_8); i += nickLen
            val ipLen = payload[i++].toInt() and 0xFF
            val ip = String(payload, i, ipLen, Charsets.US_ASCII); i += ipLen
            members.add(MemberInfo(id, nick, ip))
        }
        return Roster(yourId, members)
    }
}
