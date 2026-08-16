package host.msknet.sunsetripple.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 一整套配色的取值。两套实例共用同一批槽位，界面只认槽位语义、不认具体色号，
 * 于是白天的落日和夜里的月海能共用同一份绘制代码。
 */
@Immutable
data class SunsetPalette(
    val night: Boolean,
    /** 主强调：实心按钮、WiFi 强调条、PTT 按下态。承白字。 */
    val coral: Color,
    /** 深强调：蓝牙建房球一类的深色实心容器。同样承白字。 */
    val coralDark: Color,
    /** 备用强调（Nearby 入口目前隐藏）。 */
    val orange: Color,
    /** 次强调：蓝牙强调条、通话核心的圆环与活跃波纹。 */
    val gold: Color,
    /** 天体本身：白天是落日，夜里是月亮。也用作深色底上的高亮文字。 */
    val sun: Color,
    /** 天体最亮的那一点，只出现在头图径向渐变的中心。 */
    val sunCore: Color,
    /** [sun] 当容器色时（如工具栏选中态）压在上面的前景色。 */
    val onSun: Color,
    /** 实心强调容器上的前景色。 */
    val onAccent: Color,
    /** 主文字。 */
    val ink: Color,
    /** 次要文字。 */
    val muted: Color,
    /** 页面底色。 */
    val canvas: Color,
    /** 卡片与圆形控件的底色，比 [canvas] 高一档。 */
    val surface: Color,
    /** 柔和容器：状态提示条、静音态通话核心。 */
    val softCoral: Color,
    /** 描边与分隔线。 */
    val line: Color,
    /** 发言中的波纹色。 */
    val speaking: Color,
    val surfaceVariant: Color,
    val error: Color,
    /** 头图与房间页的竖向渐变，从天空到水面共三档。 */
    val backdrop: List<Color>,
)

/**
 * 落日：暖橙到赭红压到深褐，日光落在海面上。
 */
val SunsetDayPalette = SunsetPalette(
    night = false,
    coral = Color(0xFF9B4A52),
    coralDark = Color(0xFF392832),
    orange = Color(0xFFC97C66),
    gold = Color(0xFFC9A163),
    sun = Color(0xFFF3DCAA),
    sunCore = Color(0xFFFFF0C7),
    onSun = Color(0xFF2A2225),
    onAccent = Color.White,
    ink = Color(0xFF2A2225),
    muted = Color(0xFF6E625E),
    canvas = Color(0xFFF4F1EC),
    surface = Color(0xFFFCFAF7),
    softCoral = Color(0xFFE8D8D1),
    line = Color(0xFFD5C5BD),
    speaking = Color(0xFFB85A50),
    surfaceVariant = Color(0xFFEFE7E1),
    error = Color(0xFFA63F3C),
    backdrop = listOf(Color(0xFFC97C66), Color(0xFF9B4A52), Color(0xFF392832)),
)

/**
 * 月海：夜空靛蓝沉到深海近黑，月亮悬在海平线上，月光碎成一道道波纹。
 * 槽位语义与白天逐一对应，所以头图那轮天体不必改一笔几何就从落日变成月亮。
 */
val SunsetNightPalette = SunsetPalette(
    night = true,
    coral = Color(0xFF3F76AC),
    // 偏青的深水色。夜里两种房型都落在蓝里，靠色相区分才不至于糊成一片
    // （浅色态本来就是赭红对近黑，也是靠色相分的）。
    coralDark = Color(0xFF2A5A6E),
    orange = Color(0xFF4C79AE),
    gold = Color(0xFF93B8DF),
    sun = Color(0xFFE9EEF7),
    sunCore = Color(0xFFFFFFFF),
    onSun = Color(0xFF16233B),
    onAccent = Color(0xFFF4F8FD),
    ink = Color(0xFFE4EBF4),
    muted = Color(0xFF8FA2BC),
    canvas = Color(0xFF0E1626),
    surface = Color(0xFF182437),
    softCoral = Color(0xFF22344F),
    line = Color(0xFF33485F),
    speaking = Color(0xFF7EC8E3),
    surfaceVariant = Color(0xFF1C2A40),
    error = Color(0xFFE4867F),
    backdrop = listOf(Color(0xFF3C5A8C), Color(0xFF24395F), Color(0xFF101A2E)),
)

val LocalSunsetPalette = staticCompositionLocalOf { SunsetDayPalette }

/**
 * 取色入口。属性走 Composable getter，于是所有取色点写法不变，却能随
 * [LocalSunsetPalette] 一起在昼夜之间切换。
 *
 * 注意：`DrawScope` 里的绘制函数不是 Composable，取不到这些属性——那种地方
 * 请在外层组合里取好 [Current]（或单个颜色）再当参数传进去。
 */
object SunsetColors {
    val Current: SunsetPalette
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current
    val Coral: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.coral
    val CoralDark: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.coralDark
    val Orange: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.orange
    val Gold: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.gold
    val Sun: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.sun
    val OnSun: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.onSun
    val OnAccent: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.onAccent
    val Ink: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.ink
    val Muted: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.muted
    val Canvas: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.canvas
    val Surface: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.surface
    val SoftCoral: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.softCoral
    val Line: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.line
    val Speaking: Color
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.speaking
    val Backdrop: List<Color>
        @Composable @ReadOnlyComposable get() = LocalSunsetPalette.current.backdrop
}

private fun SunsetPalette.toColorScheme() = if (night) {
    darkColorScheme(
        primary = coral,
        onPrimary = onAccent,
        primaryContainer = softCoral,
        onPrimaryContainer = ink,
        secondary = gold,
        onSecondary = onSun,
        background = canvas,
        onBackground = ink,
        surface = surface,
        onSurface = ink,
        surfaceVariant = surfaceVariant,
        onSurfaceVariant = muted,
        outline = line,
        error = error,
    )
} else {
    lightColorScheme(
        primary = coral,
        onPrimary = onAccent,
        primaryContainer = softCoral,
        onPrimaryContainer = ink,
        secondary = gold,
        onSecondary = onSun,
        background = canvas,
        onBackground = ink,
        surface = surface,
        onSurface = ink,
        surfaceVariant = surfaceVariant,
        onSurfaceVariant = muted,
        outline = line,
        error = error,
    )
}

private val sunsetTypography = Typography(
    displaySmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 34.sp,
        lineHeight = 40.sp,
        letterSpacing = 0.sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 25.sp,
        lineHeight = 32.sp,
        letterSpacing = 0.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        lineHeight = 27.sp,
        letterSpacing = 0.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 16.sp,
        lineHeight = 23.sp,
        letterSpacing = 0.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 21.sp,
        letterSpacing = 0.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.sp,
    ),
)

@Composable
fun SunsetRippleTheme(
    night: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val palette = if (night) SunsetNightPalette else SunsetDayPalette
    CompositionLocalProvider(LocalSunsetPalette provides palette) {
        MaterialTheme(
            colorScheme = palette.toColorScheme(),
            typography = sunsetTypography,
            shapes = Shapes(
                extraSmall = RoundedCornerShape(3.dp),
                small = RoundedCornerShape(5.dp),
                medium = RoundedCornerShape(8.dp),
                large = RoundedCornerShape(8.dp),
                extraLarge = RoundedCornerShape(8.dp),
            ),
            content = content,
        )
    }
}
