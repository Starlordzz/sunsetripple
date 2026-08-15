package host.msknet.sunsetripple.ui

import host.msknet.sunsetripple.transport.HostTransferPlan
import host.msknet.sunsetripple.transport.HostTransferSeed

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
