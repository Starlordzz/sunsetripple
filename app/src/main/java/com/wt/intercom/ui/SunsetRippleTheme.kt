package com.wt.intercom.ui

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
    val Coral = Color(0xFFD94A3D)
    val CoralDark = Color(0xFF9F2F35)
    val Orange = Color(0xFFF07B43)
    val Gold = Color(0xFFF4B85C)
    val Sun = Color(0xFFFFD878)
    val Ink = Color(0xFF332B2A)
    val Muted = Color(0xFF7D6B67)
    val Canvas = Color(0xFFFFF8F0)
    val Surface = Color(0xFFFFFDFC)
    val SoftCoral = Color(0xFFF8E4DC)
    val Line = Color(0xFFE9CFC4)
    val Speaking = Color(0xFFE97045)
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
    surfaceVariant = Color(0xFFF7EAE2),
    onSurfaceVariant = SunsetColors.Muted,
    outline = SunsetColors.Line,
    error = Color(0xFFB3261E),
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
