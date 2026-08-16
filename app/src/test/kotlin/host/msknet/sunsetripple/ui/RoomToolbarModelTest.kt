package host.msknet.sunsetripple.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RoomToolbarModelTest {

    @Test
    fun `全双工房保留三项但静音和扬声使用稳定标签`() {
        val items = roomToolbarItems(
            pushToTalk = false,
            micMuted = true,
            speakerOn = false,
        )

        assertEquals(
            listOf(RoomAction.MUTE, RoomAction.SPEAKER, RoomAction.LEAVE),
            items.map { it.action },
        )
        assertEquals(listOf("静音", "扬声器", "离开"), items.map { it.label })
        assertTrue(items.first().selected)
    }

    @Test
    fun `蓝牙按住说话房隐藏重复的静音入口`() {
        val items = roomToolbarItems(
            pushToTalk = true,
            micMuted = false,
            speakerOn = true,
        )

        assertEquals(
            listOf(RoomAction.SPEAKER, RoomAction.LEAVE),
            items.map { it.action },
        )
        assertTrue(items.first().selected)
        assertTrue(items.last().destructive)
    }
}
