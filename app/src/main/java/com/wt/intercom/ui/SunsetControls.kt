package com.wt.intercom.ui

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SunsetButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: ButtonColors = ButtonDefaults.buttonColors(),
    shape: Shape = RoundedCornerShape(8.dp),
    content: @Composable RowScope.() -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = SunsetMotion.controlScale(pressed, enabled),
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "sunset-button-scale",
    )
    Button(
        onClick = onClick,
        modifier = modifier.graphicsLayer {
            scaleX = scale
            scaleY = scale
        },
        enabled = enabled,
        shape = shape,
        colors = colors,
        interactionSource = interactionSource,
        content = content,
    )
}

@Composable
fun SunsetOutlinedButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: ButtonColors = ButtonDefaults.outlinedButtonColors(),
    shape: Shape = RoundedCornerShape(8.dp),
    content: @Composable RowScope.() -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = SunsetMotion.controlScale(pressed, enabled),
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "sunset-outlined-button-scale",
    )
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.graphicsLayer {
            scaleX = scale
            scaleY = scale
        },
        enabled = enabled,
        shape = shape,
        colors = colors,
        interactionSource = interactionSource,
        content = content,
    )
}

@Composable
fun SunsetActionOrb(
    label: String,
    supportingText: String,
    onClick: (Offset) -> Unit,
    modifier: Modifier = Modifier,
    containerColor: Color = SunsetColors.Coral,
    contentColor: Color = Color.White,
    outlined: Boolean = false,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = SunsetMotion.controlScale(pressed, enabled = true),
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "sunset-action-orb-scale",
    )
    var centerInRoot by remember { mutableStateOf(Offset.Zero) }
    val surfaceModifier = if (outlined) {
        Modifier
            .background(SunsetColors.Surface, CircleShape)
            .border(1.5.dp, SunsetColors.Coral.copy(alpha = 0.48f), CircleShape)
    } else {
        Modifier
            .background(containerColor, CircleShape)
            .border(1.dp, Color.White.copy(alpha = 0.20f), CircleShape)
    }

    Box(
        modifier = modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                shadowElevation = if (pressed) 3.dp.toPx() else 8.dp.toPx()
                shape = CircleShape
            }
            .onGloballyPositioned { coordinates ->
                val topLeft = coordinates.positionInRoot()
                centerInRoot = topLeft + Offset(
                    coordinates.size.width / 2f,
                    coordinates.size.height / 2f,
                )
            }
            .then(surfaceModifier)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = { onClick(centerInRoot) },
            )
            .padding(14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            RippleStatusMark(
                active = pressed,
                modifier = Modifier.size(30.dp),
                inactiveColor = if (outlined) SunsetColors.Line else Color.White.copy(alpha = 0.55f),
                activeColor = if (outlined) SunsetColors.Speaking else SunsetColors.Gold,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.titleMedium.copy(
                    fontSize = 18.sp,
                    lineHeight = 22.sp,
                ),
                fontWeight = FontWeight.SemiBold,
                color = if (outlined) SunsetColors.Ink else contentColor,
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = supportingText,
                style = MaterialTheme.typography.labelMedium.copy(
                    fontSize = 11.sp,
                    lineHeight = 14.sp,
                ),
                color = if (outlined) SunsetColors.Muted else contentColor.copy(alpha = 0.78f),
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
        }
    }
}

@Composable
fun SunsetReveal(
    delayMillis: Int,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    var revealed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { revealed = true }
    val progress by animateFloatAsState(
        targetValue = if (revealed) 1f else 0f,
        animationSpec = tween(
            durationMillis = 460,
            delayMillis = delayMillis,
            easing = FastOutSlowInEasing,
        ),
        label = "sunset-content-reveal",
    )
    Box(
        modifier = modifier.graphicsLayer {
            alpha = progress
            translationY = (1f - progress) * 12.dp.toPx()
        },
    ) {
        content()
    }
}
