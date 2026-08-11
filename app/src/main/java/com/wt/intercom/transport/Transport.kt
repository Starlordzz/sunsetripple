package com.wt.intercom.transport

import com.wt.intercom.protocol.Frame
import com.wt.intercom.session.Roster

/** 房间传输抽象：蓝牙/WiFi/Nearby 各自实现。 */
interface Transport {
    /** 向房间内所有其他成员发送一帧。AUDIO 走不可靠通道，其余走可靠通道。 */
    fun broadcast(frame: Frame)
    fun close()
}

/** 传输层事件回调（由 RoomSession 实现）。 */
interface TransportListener {
    fun onFrame(frame: Frame)
    fun onRoster(roster: Roster)
    fun onDisconnected(reason: String)
}
