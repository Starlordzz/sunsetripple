package com.wt.intercom.ui

import com.wt.intercom.transport.HostTransferPlan
import com.wt.intercom.transport.HostTransferSeed

sealed interface HostTransferAction {
    data class BecomeHost(val seed: HostTransferSeed) : HostTransferAction
    data class JoinHost(val endpoint: String) : HostTransferAction
    data object Ignore : HostTransferAction
}

object HostTransferFlow {
    fun decide(plan: HostTransferPlan, selfId: Int): HostTransferAction {
        if (plan.members.none { it.memberId == selfId }) return HostTransferAction.Ignore
        if (plan.successorId == selfId) return HostTransferAction.BecomeHost(HostTransferSeed.from(plan))
        val successor = plan.members.first { it.memberId == plan.successorId }
        return HostTransferAction.JoinHost(successor.endpoint)
    }
}
