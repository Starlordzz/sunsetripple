package host.msknet.sunsetripple.transport

import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.session.Roster

/** 房间传输抽象：蓝牙/WiFi/Nearby 各自实现。 */
interface Transport {
    val isHost: Boolean get() = false
    /** 向房间内所有其他成员发送一帧。AUDIO 走不可靠通道，其余走可靠通道。 */
    fun broadcast(frame: Frame)
    fun prepareHostTransfer(): HostTransferPlan? = null
    fun close()
}

/** 传输层事件回调（由 RoomSession 实现）。 */
interface TransportListener {
    fun onFrame(frame: Frame)
    fun onRoster(roster: Roster)
    fun onMemberReconnecting(memberId: Int) = Unit
    fun onMemberReconnected(memberId: Int) = Unit
    fun onMemberReconnectFailed(memberId: Int) = Unit
    fun onHostTransfer(plan: HostTransferPlan) = Unit
    fun onHostTransferSnapshot(plan: HostTransferPlan) = Unit
    fun onDisconnected(reason: String)
}
