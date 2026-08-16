package host.msknet.sunsetripple.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

private const val HINT_VISIBLE_MILLIS = 1_400L

/**
 * 头图角落的昼夜开关：点一下走一档（跟随系统 → 浅色 → 深色 → 跟随系统），
 * 图标本身就是当前档位。三档光看图标容易记混，所以点完短暂浮出一行文字说明。
 *
 * 控件永远压在头图渐变上，因此配色固定用白，不随调色板走。
 */
@Composable
fun ThemeModeToggle(
    mode: ThemeMode,
    onCycle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // 只有用户点过才浮字；开屏不打扰。
    var hintToken by remember { mutableIntStateOf(0) }
    var hintVisible by remember { mutableStateOf(false) }
    LaunchedEffect(hintToken) {
        if (hintToken == 0) return@LaunchedEffect
        hintVisible = true
        delay(HINT_VISIBLE_MILLIS)
        hintVisible = false
    }
    val hintAlpha by animateFloatAsState(
        targetValue = if (hintVisible) 1f else 0f,
        animationSpec = tween(if (hintVisible) 140 else 380),
        label = "theme-mode-hint-alpha",
    )
    val interactionSource = remember { MutableInteractionSource() }

    Column(modifier = modifier.width(72.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(Color.White.copy(alpha = 0.14f), CircleShape)
                .border(1.dp, Color.White.copy(alpha = 0.30f), CircleShape)
                .semantics {
                    contentDescription = "配色：${ThemeModeResolver.label(mode)}，点击切换"
                    role = Role.Button
                }
                .clickable(
                    interactionSource = interactionSource,
                    indication = null,
                ) {
                    hintToken++
                    onCycle()
                },
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.size(21.dp)) {
                drawThemeModeGlyph(mode, Color.White.copy(alpha = 0.94f))
            }
        }
        // 高度写死，让浮字的进出不推动头图里的其他内容。
        Box(Modifier.height(18.dp), contentAlignment = Alignment.Center) {
            Text(
                text = ThemeModeResolver.label(mode),
                modifier = Modifier.alpha(hintAlpha),
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 11.sp, lineHeight = 14.sp),
                color = Color.White.copy(alpha = 0.88f),
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
        }
    }
}

private fun DrawScope.drawThemeModeGlyph(mode: ThemeMode, color: Color) {
    val radius = size.minDimension / 2f
    when (mode) {
        ThemeMode.FOLLOW_SYSTEM -> drawHalfLitDisc(color, radius)
        ThemeMode.LIGHT -> drawSunGlyph(color, radius)
        ThemeMode.DARK -> drawMoonGlyph(color, radius)
    }
}

/** 半明半暗的圆：一半留白一半填实，表示由系统定夺。 */
private fun DrawScope.drawHalfLitDisc(color: Color, radius: Float) {
    val discRadius = radius * 0.82f
    drawCircle(color = color, radius = discRadius, style = Stroke(width = 1.6.dp.toPx()))
    drawArc(
        color = color,
        startAngle = 90f,
        sweepAngle = 180f,
        useCenter = true,
        topLeft = Offset(center.x - discRadius, center.y - discRadius),
        size = Size(discRadius * 2f, discRadius * 2f),
    )
}

private fun DrawScope.drawSunGlyph(color: Color, radius: Float) {
    drawCircle(color = color, radius = radius * 0.44f)
    val rayStroke = 1.6.dp.toPx()
    repeat(8) { index ->
        val angle = (PI / 4.0 * index).toFloat()
        val direction = Offset(cos(angle), sin(angle))
        drawLine(
            color = color,
            start = center + direction * (radius * 0.66f),
            end = center + direction * (radius * 0.96f),
            strokeWidth = rayStroke,
            cap = StrokeCap.Round,
        )
    }
}

/** 月牙＝一个圆减去偏移的另一个圆，和头图里那轮月亮同源。 */
private fun DrawScope.drawMoonGlyph(color: Color, radius: Float) {
    val disc = Path().apply { addOval(Rect(center = center, radius = radius * 0.90f)) }
    val bite = Path().apply {
        addOval(
            Rect(
                center = center + Offset(radius * 0.56f, -radius * 0.34f),
                radius = radius * 0.84f,
            ),
        )
    }
    drawPath(Path().apply { op(disc, bite, PathOperation.Difference) }, color)
}
