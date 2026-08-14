package com.wt.intercom.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * 进房/散房的纯归约逻辑。真机上这两处最容易出错：
 * 组主地址回落硬编码默认值（换了网段就连不上），以及 Host 侧根本没有房间死亡信号。
 */
class RoomFlowTest {

    private val asOwner = GroupInfo(groupFormed = true, isGroupOwner = true, ownerAddress = "192.168.49.1")
    private val asMember = GroupInfo(groupFormed = true, isGroupOwner = false, ownerAddress = "192.168.49.77")

    @Test
    fun `没点建房也没点加入时组已建也不进房`() {
        assertEquals(RoomStart.Idle, RoomFlow.decide(asOwner, RoomRole.NONE, sessionActive = false))
    }

    @Test
    fun `组未建立不进房`() {
        assertEquals(RoomStart.Idle, RoomFlow.decide(null, RoomRole.HOST, sessionActive = false))
        assertEquals(
            RoomStart.Idle,
            RoomFlow.decide(asOwner.copy(groupFormed = false), RoomRole.HOST, sessionActive = false),
        )
    }

    @Test
    fun `会话已在跑不重复进房`() {
        assertEquals(RoomStart.Idle, RoomFlow.decide(asOwner, RoomRole.HOST, sessionActive = true))
    }

    @Test
    fun `组主用系统下发的真实地址建房`() {
        val info = asOwner.copy(ownerAddress = "192.168.49.5")
        assertEquals(RoomStart.Host("192.168.49.5"), RoomFlow.decide(info, RoomRole.HOST, sessionActive = false))
    }

    @Test
    fun `成员用系统下发的真实组主地址入房`() {
        assertEquals(RoomStart.Guest("192.168.49.77"), RoomFlow.decide(asMember, RoomRole.GUEST, sessionActive = false))
    }

    @Test
    fun `地址未就绪时等待下一次广播而不是回落默认 IP`() {
        assertEquals(
            RoomStart.AwaitingAddress,
            RoomFlow.decide(asOwner.copy(ownerAddress = null), RoomRole.HOST, sessionActive = false),
        )
        assertEquals(
            RoomStart.AwaitingAddress,
            RoomFlow.decide(asMember.copy(ownerAddress = "  "), RoomRole.GUEST, sessionActive = false),
        )
    }

    @Test
    fun `组主地址等待未达到上限时不超时`() {
        assertNull(
            RoomFlow.addressTimeoutReason(
                RoomStart.AwaitingAddress,
                elapsedMillis = RoomFlow.ADDRESS_WAIT_TIMEOUT_MILLIS - 1,
            ),
        )
    }

    @Test
    fun `组主地址等待达到上限时返回明确错误`() {
        assertEquals(
            RoomFlow.REASON_ADDRESS_TIMEOUT,
            RoomFlow.addressTimeoutReason(
                RoomStart.AwaitingAddress,
                elapsedMillis = RoomFlow.ADDRESS_WAIT_TIMEOUT_MILLIS,
            ),
        )
    }

    @Test
    fun `地址已经就绪时不会误触发等待超时`() {
        assertNull(
            RoomFlow.addressTimeoutReason(
                RoomStart.Host("192.168.49.1"),
                elapsedMillis = RoomFlow.ADDRESS_WAIT_TIMEOUT_MILLIS,
            ),
        )
    }

    @Test
    fun `主客身份以系统实际组主标志为准而非用户意图`() {
        // 点了"加入"，但协商结果是自己当组主
        assertEquals(RoomStart.Host("192.168.49.1"), RoomFlow.decide(asOwner, RoomRole.GUEST, sessionActive = false))
        // 点了"建房"，但被别人拉进了已有的组
        assertEquals(RoomStart.Guest("192.168.49.77"), RoomFlow.decide(asMember, RoomRole.HOST, sessionActive = false))
    }

    @Test
    fun `无会话时组解散不算房间死亡`() {
        assertNull(
            RoomFlow.deathReason(sessionActive = false, group = asOwner.copy(groupFormed = false), channelLost = false),
        )
    }

    @Test
    fun `会话进行中组解散判定房间结束`() {
        val reason =
            RoomFlow.deathReason(sessionActive = true, group = asOwner.copy(groupFormed = false), channelLost = false)
        assertEquals(RoomFlow.REASON_GROUP_GONE, reason)
    }

    @Test
    fun `会话进行中 P2P 通道断开判定房间结束`() {
        assertEquals(
            RoomFlow.REASON_CHANNEL_LOST,
            RoomFlow.deathReason(sessionActive = true, group = asOwner, channelLost = true),
        )
    }

    @Test
    fun `会话进行中组仍在不算死亡`() {
        assertNull(RoomFlow.deathReason(sessionActive = true, group = asOwner, channelLost = false))
        assertNull(RoomFlow.deathReason(sessionActive = true, group = asMember, channelLost = false))
    }

    @Test
    fun `尚未收到任何组信息不误判死亡`() {
        assertNull(RoomFlow.deathReason(sessionActive = true, group = null, channelLost = false))
    }
}
