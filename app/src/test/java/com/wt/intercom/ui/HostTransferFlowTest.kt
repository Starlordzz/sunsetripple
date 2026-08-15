package com.wt.intercom.ui

import com.wt.intercom.transport.HostTransferMember
import com.wt.intercom.transport.HostTransferPlan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HostTransferFlowTest {

    private val plan = HostTransferPlan(
        successorId = 4,
        members = listOf(
            HostTransferMember(4, 10, "第一", "endpoint-4"),
            HostTransferMember(2, 20, "第二", "endpoint-2"),
        ),
    )

    @Test
    fun `继任者创建新主机并获得 seed`() {
        val action = HostTransferFlow.decide(plan, selfId = 4)

        assertTrue(action is HostTransferAction.BecomeHost)
        action as HostTransferAction.BecomeHost
        assertEquals(4, action.seed.host.previousId)
        assertEquals(0, action.seed.host.newId)
    }

    @Test
    fun `其他在线成员连接继任者端点`() {
        val action = HostTransferFlow.decide(plan, selfId = 2)

        assertEquals(HostTransferAction.JoinHost("endpoint-4"), action)
    }

    @Test
    fun `不在交接成员表中的设备忽略旧计划`() {
        assertEquals(HostTransferAction.Ignore, HostTransferFlow.decide(plan, selfId = 9))
    }
}
