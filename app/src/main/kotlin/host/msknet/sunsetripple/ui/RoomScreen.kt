package host.msknet.sunsetripple.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import host.msknet.sunsetripple.session.MemberPresence
import host.msknet.sunsetripple.session.MemberUi
import host.msknet.sunsetripple.session.RoomUiState

@Composable
fun RoomScreen(
    modifier: Modifier = Modifier,
    state: RoomUiState,
    roomLabel: String,
    speakerOn: Boolean,
    onToggleMute: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onLeave: () -> Unit,
    onPttChanged: ((Boolean) -> Unit)? = null,
    entryProgress: State<Float>? = null,
    headerPhase: State<Float>? = null,
) {
    val roomSubtitle = when {
        state.audioFocusInterrupted -> "只听模式 · 麦克风暂不可用"
        state.connected -> "频道已连接"
        else -> "正在建立频道"
    }
    val speaking = state.members.any {
        it.speaking && it.presence == MemberPresence.CONNECTED
    }
    val pushToTalk = onPttChanged != null
    val toolbarItems = remember(pushToTalk, state.micMuted, speakerOn) {
        roomToolbarItems(
            pushToTalk = pushToTalk,
            micMuted = state.micMuted,
            speakerOn = speakerOn,
        )
    }

    Column(
        modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(SunsetColors.Backdrop)),
    ) {
        RoomHeader(
            roomLabel = roomLabel,
            roomSubtitle = roomSubtitle,
            entryProgress = entryProgress,
            headerPhase = headerPhase,
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            MemberChannelStrip(state)
            HorizontalDivider(color = Color.White.copy(alpha = 0.13f))

            Box(
                modifier = Modifier.fillMaxWidth().weight(1f),
                contentAlignment = Alignment.Center,
            ) {
                if (onPttChanged != null) {
                    PushToTalkCore(
                        audioFocusInterrupted = state.audioFocusInterrupted,
                        onPttChanged = onPttChanged,
                    )
                } else {
                    FullDuplexCore(
                        connected = state.connected,
                        micMuted = state.micMuted,
                        audioFocusInterrupted = state.audioFocusInterrupted,
                        speaking = speaking,
                    )
                }
            }

            RoomCommandBar(
                items = toolbarItems,
                onToggleMute = onToggleMute,
                onToggleSpeaker = onToggleSpeaker,
                onLeave = onLeave,
            )
        }
    }
}

@Composable
private fun RoomHeader(
    roomLabel: String,
    roomSubtitle: String,
    entryProgress: State<Float>?,
    headerPhase: State<Float>?,
) {
    val transitionFrame = SunsetMotion.roomTransitionFrame(entryProgress?.value ?: 1f)
    SunsetBrandHeader(
        height = transitionFrame.headerHeightDp.dp,
        showBackground = false,
        phase = headerPhase,
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(20.dp, 22.dp),
        ) {
            Column {
                Text(
                    roomLabel,
                    style = MaterialTheme.typography.headlineMedium,
                    color = Color.White,
                )
                Spacer(Modifier.height(4.dp))
                Crossfade(
                    targetState = roomSubtitle,
                    animationSpec = tween(240),
                    label = "room-subtitle",
                ) { subtitle ->
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.82f),
                    )
                }
            }
        }
    }
}

@Composable
private fun MemberChannelStrip(state: RoomUiState) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = 12.dp, bottom = 8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "频道成员",
                style = MaterialTheme.typography.labelLarge,
                color = Color.White.copy(alpha = 0.78f),
            )
            Spacer(Modifier.weight(1f))
            Text(
                "${state.members.size} 人在线",
                style = MaterialTheme.typography.bodyMedium,
                color = SunsetColors.Sun.copy(alpha = 0.84f),
            )
        }
        Spacer(Modifier.height(8.dp))
        if (state.members.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxWidth().height(54.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "等待频道信号",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.68f),
                )
            }
        } else {
            LazyRow(
                modifier = Modifier.fillMaxWidth().height(70.dp),
                contentPadding = PaddingValues(horizontal = 18.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(state.members, key = { it.id }) { member ->
                    MemberSignal(member, state)
                }
            }
        }
    }
}

@Composable
private fun MemberSignal(member: MemberUi, state: RoomUiState) {
    val active = member.speaking && member.presence == MemberPresence.CONNECTED
    val status = when {
        member.presence == MemberPresence.RECONNECTING -> "重连中"
        member.isSelf && state.audioFocusInterrupted -> "只听"
        member.isSelf && state.micMuted -> "静音"
        active -> "说话中"
        member.isSelf -> "我"
        else -> "在线"
    }
    val statusColor by animateColorAsState(
        targetValue = if (active) SunsetColors.Sun else Color.White.copy(alpha = 0.68f),
        animationSpec = tween(220),
        label = "member-signal-color",
    )

    Column(
        modifier = Modifier.width(66.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        RippleStatusMark(
            active = active,
            modifier = Modifier.size(30.dp),
            inactiveColor = Color.White.copy(alpha = 0.46f),
            activeColor = SunsetColors.Sun,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = member.nickname,
            style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp, lineHeight = 16.sp),
            fontWeight = FontWeight.SemiBold,
            color = if (member.presence == MemberPresence.RECONNECTING) {
                Color.White.copy(alpha = 0.58f)
            } else {
                Color.White
            },
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = status,
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 11.sp, lineHeight = 14.sp),
            color = statusColor,
            maxLines = 1,
        )
    }
}

@Composable
private fun FullDuplexCore(
    connected: Boolean,
    micMuted: Boolean,
    audioFocusInterrupted: Boolean,
    speaking: Boolean,
) {
    val centerColor by animateColorAsState(
        targetValue = when {
            audioFocusInterrupted -> Color.White.copy(alpha = 0.08f)
            micMuted -> SunsetColors.SoftCoral
            else -> Color.White.copy(alpha = 0.065f)
        },
        animationSpec = tween(240),
        label = "full-duplex-core-color",
    )
    val foreground = if (micMuted) SunsetColors.Ink else Color.White

    ChannelCoreField(
        active = speaking && !audioFocusInterrupted,
        accentColor = if (audioFocusInterrupted) SunsetColors.Line else SunsetColors.Gold,
        centerColor = centerColor,
        foreground = foreground,
        title = when {
            audioFocusInterrupted -> "只听"
            micMuted -> "已静音"
            connected -> "全双工"
            else -> "连接中"
        },
        subtitle = if (speaking) "频道有声音" else "频道保持在线",
        modifier = Modifier.size(206.dp),
    )
}

@Composable
private fun PushToTalkCore(
    audioFocusInterrupted: Boolean,
    onPttChanged: (Boolean) -> Unit,
) {
    var pressed by remember { mutableStateOf(false) }
    DisposableEffect(onPttChanged) {
        onDispose { onPttChanged(false) }
    }
    LaunchedEffect(audioFocusInterrupted) {
        if (audioFocusInterrupted && pressed) {
            pressed = false
            onPttChanged(false)
        }
    }
    val centerColor by animateColorAsState(
        targetValue = when {
            audioFocusInterrupted -> Color.White.copy(alpha = 0.08f)
            pressed -> SunsetColors.Coral
            else -> Color.White.copy(alpha = 0.065f)
        },
        animationSpec = tween(160),
        label = "ptt-core-color",
    )

    Box(
        modifier = Modifier
            .size(206.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = if (audioFocusInterrupted) "只听模式" else "按住说话"
                role = Role.Button
            }
            .pointerInput(onPttChanged, audioFocusInterrupted) {
                if (!audioFocusInterrupted) {
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false)
                        pressed = true
                        onPttChanged(true)
                        try {
                            var heldInside: Boolean
                            do {
                                val event = awaitPointerEvent()
                                heldInside = event.changes.any { change ->
                                    change.pressed &&
                                        change.position.x in 0f..size.width.toFloat() &&
                                        change.position.y in 0f..size.height.toFloat()
                                }
                            } while (heldInside)
                        } finally {
                            pressed = false
                            onPttChanged(false)
                        }
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        ChannelCoreField(
            active = pressed,
            accentColor = if (audioFocusInterrupted) SunsetColors.Line else SunsetColors.Gold,
            centerColor = centerColor,
            foreground = Color.White,
            title = when {
                audioFocusInterrupted -> "只听"
                pressed -> "正在发射"
                else -> "按住说话"
            },
            subtitle = if (pressed) "松开结束" else "PTT",
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun ChannelCoreField(
    active: Boolean,
    accentColor: Color,
    centerColor: Color,
    foreground: Color,
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
) {
    val outerScale by animateFloatAsState(
        targetValue = if (active) 1f else 0.94f,
        animationSpec = tween(260),
        label = "channel-core-ring-scale",
    )

    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val radius = size.minDimension / 2f
            drawCircle(
                color = Color.White.copy(alpha = 0.025f),
                radius = radius * 0.96f,
            )
            drawCircle(
                color = accentColor.copy(alpha = if (active) 0.68f else 0.30f),
                radius = radius * 0.91f * outerScale,
                style = Stroke(width = 1.4.dp.toPx()),
            )
            drawCircle(
                color = Color.White.copy(alpha = 0.12f),
                radius = radius * 0.73f,
                style = Stroke(width = 1.dp.toPx()),
            )
            drawCircle(
                color = centerColor,
                radius = radius * 0.56f,
            )
            drawCircle(
                color = Color.White.copy(alpha = 0.15f),
                radius = radius * 0.56f,
                style = Stroke(width = 1.dp.toPx()),
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            RippleStatusMark(
                active = active,
                modifier = Modifier.size(46.dp),
                inactiveColor = foreground.copy(alpha = 0.48f),
                activeColor = accentColor,
            )
            Spacer(Modifier.height(5.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                color = foreground,
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.sp, lineHeight = 16.sp),
                color = foreground.copy(alpha = 0.68f),
            )
        }
    }
}

@Composable
private fun RoomCommandBar(
    items: List<RoomToolbarItem>,
    onToggleMute: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onLeave: () -> Unit,
) {
    val secondaryItems = remember(items) { items.filterNot { it.destructive } }
    val leaveItem = remember(items) { items.first { it.destructive } }

    Column {
        HorizontalDivider(color = Color.White.copy(alpha = 0.10f))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color.Black.copy(alpha = 0.10f))
                .padding(horizontal = 24.dp, vertical = 14.dp),
        ) {
            Row(
                modifier = Modifier.align(Alignment.Center),
                horizontalArrangement = Arrangement.spacedBy(18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                secondaryItems.forEach { item ->
                    RoomToolbarButton(
                        item = item,
                        onClick = when (item.action) {
                            RoomAction.MUTE -> onToggleMute
                            RoomAction.SPEAKER -> onToggleSpeaker
                            RoomAction.LEAVE -> onLeave
                        },
                    )
                }
            }
            RoomToolbarButton(
                item = leaveItem,
                onClick = onLeave,
                modifier = Modifier.align(Alignment.CenterEnd),
            )
        }
    }
}

@Composable
private fun RoomToolbarButton(
    item: RoomToolbarItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = SunsetMotion.controlScale(pressed, enabled = true),
        animationSpec = tween(120),
        label = "room-toolbar-button-scale",
    )
    val contentColor = when {
        item.destructive -> SunsetColors.SoftCoral
        // 选中态的底色就是 Sun，前景得用配套的压色，不能跟着正文走。
        item.selected -> SunsetColors.OnSun
        else -> Color.White.copy(alpha = 0.88f)
    }
    val labelColor = when {
        item.destructive -> SunsetColors.SoftCoral.copy(alpha = 0.82f)
        item.selected -> SunsetColors.Sun.copy(alpha = 0.92f)
        else -> Color.White.copy(alpha = 0.70f)
    }
    val containerColor = when {
        item.destructive -> Color.White.copy(alpha = 0.055f)
        item.selected -> SunsetColors.Sun
        else -> Color.White.copy(alpha = 0.07f)
    }
    val borderColor = when {
        item.destructive -> SunsetColors.SoftCoral.copy(alpha = 0.46f)
        item.selected -> SunsetColors.Sun.copy(alpha = 0.62f)
        else -> Color.White.copy(alpha = 0.16f)
    }

    Column(
        modifier = modifier.width(64.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(50.dp)
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                }
                .background(containerColor, CircleShape)
                .border(1.dp, borderColor, CircleShape)
                .semantics {
                    contentDescription = item.label
                    role = Role.Button
                }
                .clickable(
                    interactionSource = interactionSource,
                    indication = null,
                    role = Role.Button,
                    onClick = onClick,
                ),
            contentAlignment = Alignment.Center,
        ) {
            RoomActionGlyph(
                action = item.action,
                selected = item.selected,
                color = contentColor,
                modifier = Modifier.size(22.dp),
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = item.label,
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.sp, lineHeight = 14.sp),
            color = labelColor,
            maxLines = 1,
        )
    }
}

@Composable
private fun RoomActionGlyph(
    action: RoomAction,
    selected: Boolean,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier) {
        val stroke = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round)
        when (action) {
            RoomAction.MUTE -> {
                val capsuleWidth = size.width * 0.34f
                drawRoundRect(
                    color = color,
                    topLeft = Offset((size.width - capsuleWidth) / 2f, size.height * 0.10f),
                    size = Size(capsuleWidth, size.height * 0.48f),
                    cornerRadius = CornerRadius(capsuleWidth / 2f),
                    style = stroke,
                )
                drawArc(
                    color = color,
                    startAngle = 0f,
                    sweepAngle = 180f,
                    useCenter = false,
                    topLeft = Offset(size.width * 0.24f, size.height * 0.34f),
                    size = Size(size.width * 0.52f, size.height * 0.42f),
                    style = stroke,
                )
                drawLine(
                    color = color,
                    start = Offset(size.width * 0.5f, size.height * 0.76f),
                    end = Offset(size.width * 0.5f, size.height * 0.88f),
                    strokeWidth = stroke.width,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = color,
                    start = Offset(size.width * 0.35f, size.height * 0.88f),
                    end = Offset(size.width * 0.65f, size.height * 0.88f),
                    strokeWidth = stroke.width,
                    cap = StrokeCap.Round,
                )
                if (selected) {
                    drawLine(
                        color = color,
                        start = Offset(size.width * 0.16f, size.height * 0.14f),
                        end = Offset(size.width * 0.84f, size.height * 0.86f),
                        strokeWidth = stroke.width,
                        cap = StrokeCap.Round,
                    )
                }
            }

            RoomAction.SPEAKER -> {
                val speaker = Path().apply {
                    moveTo(size.width * 0.16f, size.height * 0.42f)
                    lineTo(size.width * 0.36f, size.height * 0.42f)
                    lineTo(size.width * 0.57f, size.height * 0.24f)
                    lineTo(size.width * 0.57f, size.height * 0.76f)
                    lineTo(size.width * 0.36f, size.height * 0.58f)
                    lineTo(size.width * 0.16f, size.height * 0.58f)
                    close()
                }
                drawPath(speaker, color = color)
                drawArc(
                    color = color,
                    startAngle = -52f,
                    sweepAngle = 104f,
                    useCenter = false,
                    topLeft = Offset(size.width * 0.45f, size.height * 0.30f),
                    size = Size(size.width * 0.30f, size.height * 0.40f),
                    style = stroke,
                )
                if (selected) {
                    drawArc(
                        color = color,
                        startAngle = -50f,
                        sweepAngle = 100f,
                        useCenter = false,
                        topLeft = Offset(size.width * 0.42f, size.height * 0.18f),
                        size = Size(size.width * 0.50f, size.height * 0.64f),
                        style = stroke,
                    )
                }
            }

            RoomAction.LEAVE -> {
                drawRoundRect(
                    color = color,
                    topLeft = Offset(size.width * 0.12f, size.height * 0.16f),
                    size = Size(size.width * 0.43f, size.height * 0.68f),
                    cornerRadius = CornerRadius(2.dp.toPx()),
                    style = stroke,
                )
                drawLine(
                    color = color,
                    start = Offset(size.width * 0.38f, size.height * 0.5f),
                    end = Offset(size.width * 0.88f, size.height * 0.5f),
                    strokeWidth = stroke.width,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = color,
                    start = Offset(size.width * 0.70f, size.height * 0.34f),
                    end = Offset(size.width * 0.88f, size.height * 0.5f),
                    strokeWidth = stroke.width,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = color,
                    start = Offset(size.width * 0.70f, size.height * 0.66f),
                    end = Offset(size.width * 0.88f, size.height * 0.5f),
                    strokeWidth = stroke.width,
                    cap = StrokeCap.Round,
                )
            }
        }
    }
}
