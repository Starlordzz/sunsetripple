package com.wt.intercom.ui

/** 三屏导航。 */
enum class Screen { HOME, SCAN, BLUETOOTH_SCAN, NEARBY_SCAN, ROOM, LOOPBACK }

/** 用户在首页表达的意图。真实主客身份仍以系统协商结果为准，见 [RoomFlow.decide]。 */
enum class RoomRole { NONE, HOST, GUEST }

/**
 * `WifiP2pInfo` 的传输无关快照。
 * 单独立一个 data class 有两个理由：`WifiP2pInfo` 是 Android 类进不了 JVM 单测；
 * 它也没有 equals，直接当 Compose 的 key 会每收一次广播就重启一次副作用。
 */
data class GroupInfo(
    val groupFormed: Boolean,
    val isGroupOwner: Boolean,
    /** 组主 IP：来自系统的 `groupOwnerAddress.hostAddress`，未就绪时为 null。 */
    val ownerAddress: String?,
)

/** [RoomFlow.decide] 的结论。 */
sealed interface RoomStart {
    /** 什么都不做（没有入房意图 / 组还没建 / 会话已在跑）。 */
    data object Idle : RoomStart

    /** 组已建但组主地址还没下来，等下一次连接广播——不许拿默认 IP 顶上。 */
    data object AwaitingAddress : RoomStart

    /** 自己是组主，用 [hostIp] 作为成员表里公布的本机地址开房。 */
    data class Host(val hostIp: String) : RoomStart

    /** 自己是成员，连 [hostIp] 入房。 */
    data class Guest(val hostIp: String) : RoomStart
}

/**
 * 进房与散房的纯归约。抽出来是为了能在 JVM 单测里钉住两条真机上最贵的规则：
 * 组主地址必须用系统给的真实值；Host 侧必须有房间死亡信号。
 */
object RoomFlow {

    const val ADDRESS_WAIT_TIMEOUT_MILLIS = 10_000L
    const val REASON_ADDRESS_TIMEOUT = "未能获取 WiFi 组主地址，请重新连接"
    const val REASON_GROUP_GONE = "房间已结束（WiFi 组已解散）"
    const val REASON_CHANNEL_LOST = "房间已结束（WiFi 直连已断开）"

    /**
     * 组网状态变化时该不该起会话、以谁的身份起。
     *
     * 主客身份取系统的 `isGroupOwner` 而不是用户点的按钮：点"加入"被协商成组主、
     * 点"建房"被别人拉进已有组，都是 WiFi Direct 的常态，按意图起会两头都当客户端。
     */
    fun decide(group: GroupInfo?, role: RoomRole, sessionActive: Boolean): RoomStart {
        if (sessionActive || role == RoomRole.NONE) return RoomStart.Idle
        if (group == null || !group.groupFormed) return RoomStart.Idle
        val ip = group.ownerAddress?.trim()?.takeIf { it.isNotEmpty() } ?: return RoomStart.AwaitingAddress
        return if (group.isGroupOwner) RoomStart.Host(ip) else RoomStart.Guest(ip)
    }

    /** 只有持续等待组主地址达到上限才返回错误；其他进房状态不参与超时。 */
    fun addressTimeoutReason(start: RoomStart, elapsedMillis: Long): String? =
        REASON_ADDRESS_TIMEOUT.takeIf {
            start == RoomStart.AwaitingAddress && elapsedMillis >= ADDRESS_WAIT_TIMEOUT_MILLIS
        }

    /**
     * 房间是否已死，返回给用户看的原因；活着返回 null。
     *
     * 组主侧的传输层没有任何断线回调（客户端全走了也只是空房），P2P 组消失与 channel 断开
     * 是这一侧仅有的死亡信号，必须由此驱动 RoomSession 停机。
     *
     * group 为 null（还没收到过连接广播、或离房时已清空）一律不算死亡：
     * 只认 `groupFormed=false` 这种明确信号，避免离房竞态里冒出一条假的"房间已结束"。
     */
    fun deathReason(sessionActive: Boolean, group: GroupInfo?, channelLost: Boolean): String? {
        if (!sessionActive) return null
        if (channelLost) return REASON_CHANNEL_LOST
        if (group != null && !group.groupFormed) return REASON_GROUP_GONE
        return null
    }
}
