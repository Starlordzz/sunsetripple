package host.msknet.sunsetripple.audio

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MicGateTest {

    @Test
    fun `焦点恢复不会覆盖用户主动静音`() {
        val gate = MicGate()

        gate.setUserMuted(true)
        gate.setFocusInterrupted(true)
        gate.setFocusInterrupted(false)

        assertTrue(gate.effectiveMuted)
        assertTrue(gate.userMuted)
        assertFalse(gate.focusInterrupted)
    }

    @Test
    fun `未手动静音时焦点丢失与恢复控制有效静音`() {
        val gate = MicGate()

        gate.setFocusInterrupted(true)
        assertTrue(gate.effectiveMuted)

        gate.setFocusInterrupted(false)
        assertFalse(gate.effectiveMuted)
    }
}
