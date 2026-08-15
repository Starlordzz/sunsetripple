package host.msknet.sunsetripple.transport

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HostTransferTest {

    @Test
    fun `选择仍在线且 joinOrder 最小的成员`() {
        val selected = HostElection.select(
            listOf(
                candidate(3, 30, connected = true),
                candidate(1, 10, connected = false),
                candidate(2, 20, connected = true),
            ),
        )

        assertEquals(2, selected?.memberId)
    }

    @Test
    fun `没有在线且带稳定端点的成员时不交接`() {
        assertNull(HostElection.plan(listOf(candidate(1, 1, connected = false))))
        assertNull(HostElection.plan(listOf(candidate(1, 1, endpoint = ""))))
    }

    @Test
    fun `计划只包含在线成员并按原始入房顺序排列`() {
        val plan = HostElection.plan(
            listOf(
                candidate(4, 40),
                candidate(2, 20),
                candidate(3, 30, connected = false),
            ),
        )!!

        assertEquals(2, plan.successorId)
        assertEquals(listOf(2, 4), plan.members.map { it.memberId })
    }

    @Test
    fun `交接载荷往返保留顺序昵称和端点`() {
        val plan = HostTransferPlan(
            successorId = 4,
            members = listOf(
                HostTransferMember(4, 7, "先到", "AA:BB:CC:DD:EE:04"),
                HostTransferMember(2, 11, "Later", "AA:BB:CC:DD:EE:02"),
            ),
        )

        assertEquals(plan, HostTransferCodec.decode(HostTransferCodec.encode(plan)))
    }

    @Test
    fun `解码拒绝重复成员和尾部多余字节`() {
        val duplicate = byteArrayOf(
            1, 1, 2,
            1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 'A'.code.toByte(), 1, 'a'.code.toByte(),
            1, 0, 0, 0, 0, 0, 0, 0, 2, 1, 'B'.code.toByte(), 1, 'b'.code.toByte(),
        )
        assertFails { HostTransferCodec.decode(duplicate) }

        val valid = HostTransferCodec.encode(
            HostTransferPlan(1, listOf(HostTransferMember(1, 1, "A", "aa"))),
        )
        assertFails { HostTransferCodec.decode(valid + 0) }
    }

    @Test
    fun `计划拒绝重复端点和重复 joinOrder`() {
        assertFails {
            HostTransferPlan(
                1,
                listOf(
                    HostTransferMember(1, 1, "A", "same"),
                    HostTransferMember(2, 2, "B", "same"),
                ),
            )
        }
        assertFails {
            HostTransferPlan(
                1,
                listOf(
                    HostTransferMember(1, 1, "A", "a"),
                    HostTransferMember(2, 1, "B", "b"),
                ),
            )
        }
    }

    @Test
    fun `继任者变为零号且其余成员保持原始顺序`() {
        val plan = HostTransferPlan(
            successorId = 4,
            members = listOf(
                HostTransferMember(7, 30, "第三", "cc"),
                HostTransferMember(4, 10, "第一", "aa"),
                HostTransferMember(2, 20, "第二", "bb"),
            ),
        )

        val seed = HostTransferSeed.from(plan)

        assertEquals(listOf(4, 2, 7), seed.members.map { it.previousId })
        assertEquals(listOf(0, 1, 2), seed.members.map { it.newId })
        assertEquals(31, seed.nextJoinOrder)
    }

    private fun candidate(
        id: Int,
        order: Long,
        endpoint: String = "endpoint-$id",
        connected: Boolean = true,
    ) = TransferCandidate(id, order, "成员$id", endpoint, connected)

    private fun assertFails(block: () -> Unit) {
        assertTrue(runCatching(block).exceptionOrNull() is IllegalArgumentException)
    }
}
