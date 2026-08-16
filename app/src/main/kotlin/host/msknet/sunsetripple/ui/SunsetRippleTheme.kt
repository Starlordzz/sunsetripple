package host.msknet.sunsetripple.ui

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object SunsetColors {
    val Coral = Color(0xFF9B4A52)
    val CoralDark = Color(0xFF392832)
    val Orange = Color(0xFFC97C66)
    val Gold = Color(0xFFD0AC72)
    val Sun = Color(0xFFF3DCAA)
    val Ink = Color(0xFF29252A)
    val Muted = Color(0xFF746B6B)
    val Canvas = Color(0xFFF4F1EC)
    val Surface = Color(0xFFFCFAF7)
    val SoftCoral = Color(0xFFE6D4CE)
    val Line = Color(0xFFD8CCC7)
    val Speaking = Color(0xFFBC655B)
    val Backdrop = listOf(Orange, Coral, CoralDark)
}

private val sunsetScheme = lightColorScheme(
    primary = SunsetColors.Coral,
    onPrimary = Color.White,
    primaryContainer = SunsetColors.SoftCoral,
    onPrimaryContainer = SunsetColors.CoralDark,
    secondary = SunsetColors.Gold,
    onSecondary = SunsetColors.Ink,
    background = SunsetColors.Canvas,
    onBackground = SunsetColors.Ink,
    surface = SunsetColors.Surface,
    onSurface = SunsetColors.Ink,
    surfaceVariant = Color(0xFFEEE6E1),
    onSurfaceVariant = SunsetColors.Muted,
    outline = SunsetColors.Line,
    error = Color(0xFFA63F3C),
)

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
fun SunsetRippleTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = sunsetScheme,
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
