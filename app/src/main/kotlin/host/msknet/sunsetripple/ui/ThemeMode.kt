package host.msknet.sunsetripple.ui

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * 界面配色的三档取向。手动两档压过系统开关，[FOLLOW_SYSTEM] 才把决定权交回系统。
 */
enum class ThemeMode {
    FOLLOW_SYSTEM,
    LIGHT,
    DARK,
}

interface ThemeModePersistence {
    fun load(): ThemeMode
    fun save(mode: ThemeMode)
}

class ThemeCoordinator(
    private val persistence: ThemeModePersistence,
) {
    private val _mode = MutableStateFlow(persistence.load())
    val mode: StateFlow<ThemeMode> = _mode.asStateFlow()

    fun cycle() {
        val next = ThemeModeResolver.next(_mode.value)
        persistence.save(next)
        _mode.value = next
    }
}

/**
 * 主题判定与存档的纯逻辑，不碰 Android 也不碰 Compose，方便直接单测。
 */
object ThemeModeResolver {

    /** 存档用的稳定字符串：枚举改名不能影响用户已经存下的选择。 */
    private val storedValues = mapOf(
        ThemeMode.FOLLOW_SYSTEM to "system",
        ThemeMode.LIGHT to "light",
        ThemeMode.DARK to "dark",
    )

    private val labels = mapOf(
        ThemeMode.FOLLOW_SYSTEM to "跟随系统",
        ThemeMode.LIGHT to "浅色",
        ThemeMode.DARK to "深色",
    )

    fun isNight(mode: ThemeMode, systemInDark: Boolean): Boolean = when (mode) {
        ThemeMode.FOLLOW_SYSTEM -> systemInDark
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }

    /** 头图角落图标点一下走一档，循环回到起点。 */
    fun next(mode: ThemeMode): ThemeMode {
        val all = ThemeMode.entries
        return all[(all.indexOf(mode) + 1) % all.size]
    }

    fun label(mode: ThemeMode): String = labels.getValue(mode)

    fun toStoredValue(mode: ThemeMode): String = storedValues.getValue(mode)

    /** 认不出来的存档值（老版本、被改坏、首次安装）一律退回跟随系统。 */
    fun fromStoredValue(raw: String?): ThemeMode =
        storedValues.entries.firstOrNull { it.value == raw }?.key ?: ThemeMode.FOLLOW_SYSTEM
}
