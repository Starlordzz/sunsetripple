package com.wt.intercom.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun SunsetBrandHeader(
    modifier: Modifier = Modifier,
    height: Dp = 214.dp,
    content: @Composable BoxScope.() -> Unit,
) {
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
            val center = Offset(size.width * 0.72f, size.height * 0.53f)
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
fun RippleStatusMark(active: Boolean, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val center = Offset(size.width / 2f, size.height / 2f)
        val color = if (active) SunsetColors.Speaking else SunsetColors.Line
        drawCircle(color = color, radius = size.minDimension * 0.16f, center = center)
        repeat(2) { index ->
            drawArc(
                color = color.copy(alpha = if (active) 0.72f else 0.55f),
                startAngle = 205f,
                sweepAngle = 130f,
                useCenter = false,
                topLeft = Offset(size.width * (0.16f - index * 0.10f), size.height * (0.16f - index * 0.10f)),
                size = Size(size.width * (0.68f + index * 0.20f), size.height * (0.68f + index * 0.20f)),
                style = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round),
            )
        }
    }
}
