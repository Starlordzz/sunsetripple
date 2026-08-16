package host.msknet.sunsetripple.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemeModeTest {

    @Test
    fun `跟随系统时夜间与否完全交给系统深色开关`() {
        assertTrue(ThemeModeResolver.isNight(ThemeMode.FOLLOW_SYSTEM, systemInDark = true))
        assertFalse(ThemeModeResolver.isNight(ThemeMode.FOLLOW_SYSTEM, systemInDark = false))
    }

    @Test
    fun `手动两档压过系统深色开关`() {
        assertFalse(ThemeModeResolver.isNight(ThemeMode.LIGHT, systemInDark = true))
        assertTrue(ThemeModeResolver.isNight(ThemeMode.DARK, systemInDark = false))
    }

    @Test
    fun `头图图标按跟随系统到浅色到深色的顺序循环`() {
        assertEquals(ThemeMode.LIGHT, ThemeModeResolver.next(ThemeMode.FOLLOW_SYSTEM))
        assertEquals(ThemeMode.DARK, ThemeModeResolver.next(ThemeMode.LIGHT))
        assertEquals(ThemeMode.FOLLOW_SYSTEM, ThemeModeResolver.next(ThemeMode.DARK))
    }

    @Test
    fun `三档各自有可读标签且互不相同`() {
        val labels = ThemeMode.entries.map { ThemeModeResolver.label(it) }

        assertEquals(listOf("跟随系统", "浅色", "深色"), labels)
        assertEquals(labels.size, labels.toSet().size)
    }

    @Test
    fun `存档值可往返且与枚举名解耦`() {
        ThemeMode.entries.forEach { mode ->
            val stored = ThemeModeResolver.toStoredValue(mode)

            assertEquals(mode, ThemeModeResolver.fromStoredValue(stored))
        }
    }

    @Test
    fun `缺失或损坏的存档值退回跟随系统`() {
        assertEquals(ThemeMode.FOLLOW_SYSTEM, ThemeModeResolver.fromStoredValue(null))
        assertEquals(ThemeMode.FOLLOW_SYSTEM, ThemeModeResolver.fromStoredValue(""))
        assertEquals(ThemeMode.FOLLOW_SYSTEM, ThemeModeResolver.fromStoredValue("midnight"))
    }
}
