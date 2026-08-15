package host.msknet.sunsetripple.transport

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReconnectPolicyTest {

    @Test
    fun `最多三次且延迟按一二四秒递增`() {
        val policy = ReconnectPolicy()

        assertEquals(1_000L, policy.nextDelayMs())
        assertEquals(2_000L, policy.nextDelayMs())
        assertEquals(4_000L, policy.nextDelayMs())
        assertNull(policy.nextDelayMs())
    }

    @Test
    fun `连接恢复会重置次数`() {
        val policy = ReconnectPolicy()
        policy.nextDelayMs()

        policy.reset()

        assertEquals(1_000L, policy.nextDelayMs())
    }
}
