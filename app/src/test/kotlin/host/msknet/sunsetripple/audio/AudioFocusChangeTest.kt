package host.msknet.sunsetripple.audio

import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AudioFocusChangeTest {

    @Test
    fun `通话请求系统允许的独占瞬时音频焦点`() {
        assertEquals(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE, AudioFocusChange.focusGain)
        assertEquals(true, AudioFocusChange.pauseWhenDucked)
    }

    @Test
    fun `LOSS 系列进入只听而 GAIN 恢复上行`() {
        assertEquals(true, AudioFocusChange.interrupted(AudioManager.AUDIOFOCUS_LOSS))
        assertEquals(true, AudioFocusChange.interrupted(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT))
        assertEquals(true, AudioFocusChange.interrupted(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK))
        assertEquals(false, AudioFocusChange.interrupted(AudioManager.AUDIOFOCUS_GAIN))
    }

    @Test
    fun `未知焦点变化不改变只听状态`() {
        assertNull(AudioFocusChange.interrupted(Int.MIN_VALUE))
    }

    @Test
    fun `焦点申请结果区分正常延迟与拒绝`() {
        assertEquals(
            AudioFocusRequestState.GRANTED,
            AudioFocusChange.requestState(AudioManager.AUDIOFOCUS_REQUEST_GRANTED),
        )
        assertEquals(
            AudioFocusRequestState.DELAYED,
            AudioFocusChange.requestState(AudioManager.AUDIOFOCUS_REQUEST_DELAYED),
        )
        assertEquals(
            AudioFocusRequestState.DENIED,
            AudioFocusChange.requestState(AudioManager.AUDIOFOCUS_REQUEST_FAILED),
        )
    }
}
