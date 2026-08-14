package com.wt.intercom.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun SunsetBrandHeader(
    modifier: Modifier = Modifier,
    height: Dp = 214.dp,
    content: @Composable BoxScope.() -> Unit,
) {
    val motion = rememberInfiniteTransition(label = "sunset-header-motion")
    val phase by motion.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(6_400, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "sunset-header-phase",
    )
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .clipToBounds()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFFFF8A3D), Color(0xFFFF7138), Color(0xFFB92F3B))
                )
            )
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val center = Offset(
                size.width * (0.72f + SunsetMotion.headerSunOffset(phase)),
                size.height * (0.53f + (phase - 0.5f) * 0.012f),
            )
            val radius = size.minDimension * 0.28f
            drawCircle(
                brush = Brush.verticalGradient(listOf(Color(0xFFFFE59A), Color(0xFFFFD06B))),
                radius = radius,
                center = center,
            )
            drawRect(
                color = Color(0xFFFFB05B).copy(alpha = 0.45f),
                topLeft = Offset(0f, center.y),
                size = Size(size.width, 2.dp.toPx()),
            )
            val waveColor = Color(0xFFFFE09A).copy(alpha = 0.68f)
            repeat(3) { index ->
                val inset = size.width * (0.13f - index * 0.035f)
                val top = center.y + 15.dp.toPx() + index * 22.dp.toPx()
                val waveHeight = 58.dp.toPx() + index * 19.dp.toPx()
                drawArc(
                    color = waveColor.copy(alpha = 0.70f - index * 0.13f),
                    startAngle = 12f,
                    sweepAngle = 156f,
                    useCenter = false,
                    topLeft = Offset(inset, top - waveHeight),
                    size = Size(size.width - inset * 2, waveHeight * 2),
                    style = Stroke(width = (5 - index).dp.toPx(), cap = StrokeCap.Round),
                )
            }
        }
        content()
    }
}

@Composable
fun RippleStatusMark(
    active: Boolean,
    modifier: Modifier = Modifier,
    inactiveColor: Color = SunsetColors.Line,
    activeColor: Color = SunsetColors.Speaking,
) {
    val motion = rememberInfiniteTransition(label = "ripple-status-motion")
    val phase by motion.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1_350, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "ripple-status-phase",
    )
    val activation by animateFloatAsState(
        targetValue = if (active) 1f else 0f,
        animationSpec = tween(220),
        label = "ripple-status-activation",
    )
    Canvas(modifier) {
        val center = Offset(size.width / 2f, size.height / 2f)
        val pulse = SunsetMotion.rippleFrame(active = true, phase = phase)
        val pulseScale = 1f + (pulse.scale - 1f) * activation
        val pulseAlpha = 0.55f + (pulse.alpha - 0.55f) * activation
        val color = lerp(inactiveColor, activeColor, activation)
        drawCircle(
            color = color,
            radius = size.minDimension * (0.16f + 0.025f * activation),
            center = center,
        )
        repeat(2) { index ->
            val baseWidth = size.width * (0.68f + index * 0.20f)
            val baseHeight = size.height * (0.68f + index * 0.20f)
            val waveWidth = baseWidth * pulseScale
            val waveHeight = baseHeight * pulseScale
            drawArc(
                color = color.copy(alpha = pulseAlpha * (1f - index * 0.14f)),
                startAngle = 205f,
                sweepAngle = 130f,
                useCenter = false,
                topLeft = Offset((size.width - waveWidth) / 2f, (size.height - waveHeight) / 2f),
                size = Size(waveWidth, waveHeight),
                style = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round),
            )
        }
    }
}
