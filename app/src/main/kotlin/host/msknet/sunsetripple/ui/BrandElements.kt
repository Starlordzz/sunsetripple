package host.msknet.sunsetripple.ui

import androidx.compose.animation.core.FastOutSlowInEasing
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
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.hypot

@Composable
fun SunsetBrandHeader(
    modifier: Modifier = Modifier,
    height: Dp = 214.dp,
    showBackground: Boolean = true,
    phase: State<Float>? = null,
    sceneAlpha: Float = 1f,
    content: @Composable BoxScope.() -> Unit,
) {
    val internalPhase = if (phase == null) {
        val motion = rememberInfiniteTransition(label = "sunset-header-motion")
        motion.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(7_200, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "sunset-header-phase",
        )
    } else {
        null
    }
    val scenePhase = phase ?: checkNotNull(internalPhase)
    // DrawScope 不是 Composable，取不到 SunsetColors，只能在这里取好再传进去。
    val palette = SunsetColors.Current
    val headerModifier = modifier
        .fillMaxWidth()
        .height(height)
        .clipToBounds()
        .let { base ->
            if (showBackground) base.background(Brush.verticalGradient(palette.backdrop)) else base
        }
    Box(modifier = headerModifier) {
        Canvas(Modifier.fillMaxSize()) {
            drawSunsetHeaderScene(scenePhase.value, palette, alpha = sceneAlpha)
        }
        content()
    }
}

/**
 * 天体加三道波纹。几何与昼夜无关：白天这轮是落日，夜里同一笔就是月亮，
 * 底下的波纹也从被日光染暖变成被月光洗白。
 */
private fun DrawScope.drawSunsetHeaderScene(
    phase: Float,
    palette: SunsetPalette,
    sceneSize: Size = size,
    alpha: Float = 1f,
) {
    if (alpha <= 0f || sceneSize.minDimension <= 0f) return
    val center = Offset(
        sceneSize.width * (0.72f + SunsetMotion.headerSunOffset(phase)),
        sceneSize.height * (0.48f + (phase - 0.5f) * 0.008f),
    )
    val radius = sceneSize.minDimension * 0.29f
    drawCircle(
        color = palette.sun.copy(alpha = 0.13f * alpha),
        radius = radius * 1.28f,
        center = center,
    )
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(
                palette.sunCore.copy(alpha = alpha),
                palette.sun.copy(alpha = alpha),
                palette.gold.copy(alpha = alpha),
            ),
            center = center - Offset(radius * 0.24f, radius * 0.28f),
            radius = radius * 1.34f,
        ),
        radius = radius,
        center = center,
    )
    drawLine(
        brush = Brush.horizontalGradient(
            colors = listOf(
                Color.Transparent,
                palette.sun.copy(alpha = 0.42f * alpha),
                Color.Transparent,
            ),
        ),
        start = Offset(0f, center.y),
        end = Offset(sceneSize.width, center.y),
        strokeWidth = 1.4.dp.toPx(),
    )
    val waveShift = (phase - 0.5f) * radius * 0.08f
    repeat(3) { index ->
        val waveWidth = sceneSize.width * (0.58f + index * 0.13f)
        val waveHeight = radius * (0.52f + index * 0.14f)
        val waveCenter = Offset(
            sceneSize.width * 0.56f - waveShift * (index + 1),
            center.y + radius * (0.28f + index * 0.31f),
        )
        drawArc(
            brush = Brush.horizontalGradient(
                colors = listOf(
                    Color.Transparent,
                    palette.sun.copy(alpha = (0.76f - index * 0.14f) * alpha),
                    Color.Transparent,
                ),
                startX = waveCenter.x - waveWidth / 2f,
                endX = waveCenter.x + waveWidth / 2f,
            ),
            startAngle = 18f,
            sweepAngle = 144f,
            useCenter = false,
            topLeft = Offset(waveCenter.x - waveWidth / 2f, waveCenter.y - waveHeight),
            size = Size(waveWidth, waveHeight * 2f),
            style = Stroke(width = (2.8f - index * 0.45f).dp.toPx(), cap = StrokeCap.Round),
        )
    }
}

@Composable
fun RippleStatusMark(
    active: Boolean,
    modifier: Modifier = Modifier,
    inactiveColor: Color = SunsetColors.Line,
    activeColor: Color = SunsetColors.Speaking,
) {
    val phase = if (active) {
        val motion = rememberInfiniteTransition(label = "ripple-status-motion")
        motion.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(1_350, easing = LinearEasing),
                repeatMode = RepeatMode.Restart,
            ),
            label = "ripple-status-phase",
        )
    } else {
        null
    }
    val activation = animateFloatAsState(
        targetValue = if (active) 1f else 0f,
        animationSpec = tween(220),
        label = "ripple-status-activation",
    )
    Canvas(modifier) {
        val activationValue = activation.value
        val pulse = SunsetMotion.rippleFrame(active = true, phase = phase?.value ?: 0f)
        val pulseScale = 1f + (pulse.scale - 1f) * activationValue
        val pulseAlpha = 0.55f + (pulse.alpha - 0.55f) * activationValue
        val color = lerp(inactiveColor, activeColor, activationValue)
        val sunCenter = Offset(size.width / 2f, size.height * 0.31f)
        drawCircle(
            color = color,
            radius = size.minDimension * (0.13f + 0.02f * activationValue),
            center = sunCenter,
        )
        repeat(3) { index ->
            val baseWidth = size.width * (0.48f + index * 0.19f)
            val baseHeight = size.height * (0.24f + index * 0.07f)
            val waveWidth = baseWidth * pulseScale
            val waveHeight = baseHeight * pulseScale
            val waveCenterY = size.height * (0.49f + index * 0.13f)
            drawArc(
                color = color.copy(alpha = pulseAlpha * (1f - index * 0.14f)),
                startAngle = 18f,
                sweepAngle = 144f,
                useCenter = false,
                topLeft = Offset((size.width - waveWidth) / 2f, waveCenterY - waveHeight),
                size = Size(waveWidth, waveHeight),
                style = Stroke(width = (1.7f - index * 0.18f).dp.toPx(), cap = StrokeCap.Round),
            )
        }
    }
}

/**
 * @param edgeColor 扩散圆的描边色。这里同样是非 Composable 作用域，颜色得由调用方
 *   在组合里取好传进来（用 [SunsetColors.Sun]，白天是落日边、夜里是月光边）。
 */
fun Modifier.sunsetCircularReveal(
    progress: State<Float>,
    origin: Offset,
    edgeColor: Color,
): Modifier = drawWithCache {
    val fullRadius = maxOf(
        hypot(origin.x, origin.y),
        hypot(size.width - origin.x, origin.y),
        hypot(origin.x, size.height - origin.y),
        hypot(size.width - origin.x, size.height - origin.y),
    )
    val revealPath = Path()
    val edgeStroke = Stroke(width = 1.4.dp.toPx())
    onDrawWithContent {
        val revealProgress = progress.value.coerceIn(0f, 1f)
        val frame = SunsetMotion.entryRippleFrame(revealProgress)
        if (frame.scale >= 1f) {
            drawContent()
            return@onDrawWithContent
        }
        if (frame.scale <= 0f) return@onDrawWithContent

        val radius = fullRadius * frame.scale
        revealPath.reset()
        revealPath.addOval(
            Rect(
                left = origin.x - radius,
                top = origin.y - radius,
                right = origin.x + radius,
                bottom = origin.y + radius,
            ),
        )
        clipPath(revealPath) {
            this@onDrawWithContent.drawContent()
        }

        val edgeAlpha = (1f - revealProgress) * 0.18f
        if (edgeAlpha > 0f) {
            drawCircle(
                color = edgeColor.copy(alpha = edgeAlpha),
                radius = radius,
                center = origin,
                style = edgeStroke,
            )
        }
    }
}
