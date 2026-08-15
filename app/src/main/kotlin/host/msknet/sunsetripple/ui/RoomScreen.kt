package host.msknet.sunsetripple.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import host.msknet.sunsetripple.session.MemberPresence
import host.msknet.sunsetripple.session.MemberUi
import host.msknet.sunsetripple.session.RoomUiState

@Composable
fun RoomScreen(
    state: RoomUiState,
    roomLabel: String,
    speakerOn: Boolean,
    onToggleMute: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onLeave: () -> Unit,
    onPttChanged: ((Boolean) -> Unit)? = null,
) {
    val roomSubtitle = when {
        state.audioFocusInterrupted -> "只听模式 · 麦克风暂不可用"
        state.connected -> "频道已连接"
        else -> "正在建立频道"
    }
    val speaking = state.members.any {
        it.speaking && it.presence == MemberPresence.CONNECTED
    }

    Column(Modifier.fillMaxSize().background(SunsetColors.Canvas)) {
        SunsetBrandHeader(height = 166.dp) {
            SunsetReveal(
                delayMillis = 30,
                modifier = Modifier.align(Alignment.BottomStart).padding(20.dp, 22.dp),
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

        SunsetReveal(delayMillis = 90, modifier = Modifier.fillMaxWidth()) {
            MemberChannelStrip(state)
        }
        HorizontalDivider(color = SunsetColors.Line.copy(alpha = 0.72f))

        Box(
            modifier = Modifier.fillMaxWidth().weight(1f),
            contentAlignment = Alignment.Center,
        ) {
            SunsetReveal(delayMillis = 150) {
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
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 22.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onPttChanged == null) {
                RoomRoundControl(
                    label = if (state.micMuted) "静音" else "开麦",
                    active = !state.micMuted,
                    onClick = onToggleMute,
                )
            }
            RoomRoundControl(
                label = if (speakerOn) "扬声" else "听筒",
                active = speakerOn,
                onClick = onToggleSpeaker,
            )
            RoomRoundControl(
                label = "离开",
                active = true,
                destructive = true,
                onClick = onLeave,
            )
        }
    }
}

@Composable
private fun MemberChannelStrip(state: RoomUiState) {
    Column(Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "频道成员",
                style = MaterialTheme.typography.titleMedium,
                color = SunsetColors.Ink,
            )
            Spacer(Modifier.weight(1f))
            Text(
                "${state.members.size} 人在线",
                style = MaterialTheme.typography.labelLarge,
                color = SunsetColors.Coral,
            )
        }
        Spacer(Modifier.height(10.dp))
        if (state.members.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxWidth().height(76.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "等待频道信号",
                    style = MaterialTheme.typography.bodyMedium,
                    color = SunsetColors.Muted,
                )
            }
        } else {
            LazyRow(
                modifier = Modifier.fillMaxWidth().height(82.dp),
                contentPadding = PaddingValues(horizontal = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
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
        targetValue = if (active) SunsetColors.Coral else SunsetColors.Muted,
        animationSpec = tween(220),
        label = "member-signal-color",
    )

    Column(
        modifier = Modifier.width(78.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        RippleStatusMark(active = active, modifier = Modifier.size(42.dp))
        Spacer(Modifier.height(4.dp))
        Text(
            text = member.nickname,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = if (member.presence == MemberPresence.RECONNECTING) SunsetColors.Muted else SunsetColors.Ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = status,
            style = MaterialTheme.typography.bodyMedium,
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
    val coreColor by animateColorAsState(
        targetValue = when {
            audioFocusInterrupted -> SunsetColors.Line
            micMuted -> SunsetColors.SoftCoral
            else -> SunsetColors.Coral
        },
        animationSpec = tween(240),
        label = "full-duplex-core-color",
    )
    val foreground = if (audioFocusInterrupted || micMuted) SunsetColors.Ink else Color.White

    Box(
        modifier = Modifier
            .size(178.dp)
            .background(coreColor, CircleShape)
            .border(2.dp, SunsetColors.Gold.copy(alpha = 0.72f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            RippleStatusMark(
                active = speaking && !audioFocusInterrupted,
                modifier = Modifier.size(66.dp),
                inactiveColor = foreground.copy(alpha = 0.52f),
                activeColor = SunsetColors.Gold,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = when {
                    audioFocusInterrupted -> "只听"
                    micMuted -> "已静音"
                    connected -> "全双工"
                    else -> "连接中"
                },
                style = MaterialTheme.typography.titleLarge,
                color = foreground,
            )
            Text(
                text = if (speaking) "频道有声音" else "频道保持在线",
                style = MaterialTheme.typography.bodyMedium,
                color = foreground.copy(alpha = 0.74f),
            )
        }
    }
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
    val pttColor by animateColorAsState(
        targetValue = when {
            audioFocusInterrupted -> SunsetColors.Line
            pressed -> SunsetColors.CoralDark
            else -> SunsetColors.Coral
        },
        animationSpec = tween(160),
        label = "ptt-core-color",
    )

    SunsetButton(
        onClick = {},
        enabled = !audioFocusInterrupted,
        modifier = Modifier
            .size(178.dp)
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
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = pttColor),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            RippleStatusMark(
                active = pressed,
                modifier = Modifier.size(66.dp),
                inactiveColor = Color.White.copy(alpha = 0.52f),
                activeColor = SunsetColors.Gold,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = when {
                    audioFocusInterrupted -> "只听"
                    pressed -> "正在发射"
                    else -> "按住说话"
                },
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                text = if (pressed) "松开结束" else "PTT",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.74f),
            )
        }
    }
}

@Composable
private fun RoomRoundControl(
    label: String,
    active: Boolean,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    if (destructive) {
        SunsetButton(
            onClick = onClick,
            modifier = Modifier.size(68.dp),
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = SunsetColors.CoralDark),
        ) {
            Text(label, style = MaterialTheme.typography.labelLarge)
        }
    } else {
        SunsetOutlinedButton(
            onClick = onClick,
            modifier = Modifier.size(68.dp),
            shape = CircleShape,
            colors = ButtonDefaults.outlinedButtonColors(
                containerColor = if (active) SunsetColors.SoftCoral else SunsetColors.Surface,
                contentColor = SunsetColors.CoralDark,
            ),
        ) {
            Text(label, style = MaterialTheme.typography.labelLarge)
        }
    }
}
