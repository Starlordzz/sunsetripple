package com.wt.intercom.transport

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.MemberInfo
import com.wt.intercom.session.RosterCodec

/** ROSTER 帧构造。yourId 因人而异，需按收件人分别编码后单播。 */
object RosterFrames {

    /**
     * 为收件人 [yourId] 编一帧成员表。
     * 载荷超上限（成员过多/昵称过长）时返回 null 并告警——绝不静默丢弃，
     * 否则成员表会停发而 UI 毫无察觉。
     */
    fun encode(hostId: Int, yourId: Int, members: List<MemberInfo>): Frame? {
        // 只吞 RosterCodec 的载荷超限异常；Frame 构造的参数错误属编程错误，让它穿透。
        val payload = try {
            RosterCodec.encode(yourId, members)
        } catch (e: IllegalArgumentException) {
            TransportLog.w("成员表编码失败，本次未下发（成员数 ${members.size}）: ${e.message}", e)
            return null
        }
        return Frame(FrameType.ROSTER, hostId, 0, payload)
    }
}
