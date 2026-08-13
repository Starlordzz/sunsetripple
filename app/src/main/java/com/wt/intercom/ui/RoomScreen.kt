package com.wt.intercom.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.wt.intercom.session.RoomUiState

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
    Column(Modifier.fillMaxSize().background(SunsetColors.Canvas)) {
        SunsetBrandHeader(height = 188.dp) {
            Column(Modifier.align(Alignment.BottomStart).padding(20.dp, 22.dp)) {
                Text(
                    roomLabel,
                    style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
                    color = Color.White,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    when {
                        state.audioFocusInterrupted -> "只听模式 · 暂时无法使用麦克风"
                        state.connected -> "声音正在房间里流动"
                        else -> "正在建立声音连接"
                    },
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.82f),
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "成员",
                style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                color = SunsetColors.Ink,
            )
            Spacer(Modifier.weight(1f))
            Text(
                "${state.members.size} 人",
                style = androidx.compose.material3.MaterialTheme.typography.labelLarge,
                color = SunsetColors.Coral,
            )
        }

        LazyColumn(Modifier.weight(1f).padding(horizontal = 20.dp)) {
            items(state.members, key = { it.id }) { member ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 15.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RippleStatusMark(active = member.speaking, modifier = Modifier.size(42.dp))
                    Column(Modifier.weight(1f).padding(start = 13.dp)) {
                        Text(
                            if (member.isSelf) "${member.nickname} · 我" else member.nickname,
                            fontWeight = FontWeight.SemiBold,
                            color = SunsetColors.Ink,
                        )
                        Text(
                            when {
                                member.isSelf && state.audioFocusInterrupted -> "只听模式"
                                member.isSelf && state.micMuted -> "麦克风已静音"
                                member.speaking -> "正在说话"
                                else -> "安静"
                            },
                            style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                            color = if (member.speaking) SunsetColors.Coral else SunsetColors.Muted,
                        )
                    }
                }
                HorizontalDivider(color = SunsetColors.Line.copy(alpha = 0.65f))
            }
        }

        Column(
            modifier = Modifier.fillMaxWidth().background(SunsetColors.Surface).padding(20.dp, 16.dp, 20.dp, 20.dp)
        ) {
            if (onPttChanged != null) {
                var pressed by remember { mutableStateOf(false) }
                DisposableEffect(onPttChanged) {
                    onDispose { onPttChanged(false) }
                }
                Button(
                    onClick = {},
                    enabled = !state.audioFocusInterrupted,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(68.dp)
                        .pointerInput(onPttChanged, state.audioFocusInterrupted) {
                            if (!state.audioFocusInterrupted) {
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
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (pressed) SunsetColors.CoralDark else SunsetColors.Coral,
                    ),
                ) {
                    RippleStatusMark(active = pressed, modifier = Modifier.size(34.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(
                        when {
                            state.audioFocusInterrupted -> "只听模式"
                            pressed -> "正在说话"
                            else -> "按住说话"
                        },
                    )
                }
                Spacer(Modifier.height(10.dp))
            }
            Row(Modifier.fillMaxWidth()) {
                if (onPttChanged == null) {
                    OutlinedButton(
                        onClick = onToggleMute,
                        modifier = Modifier.weight(1f).height(50.dp),
                        shape = RoundedCornerShape(8.dp),
                    ) {
                        Text(if (state.micMuted) "打开麦克风" else "静音")
                    }
                    Spacer(Modifier.width(10.dp))
                }
                OutlinedButton(
                    onClick = onToggleSpeaker,
                    modifier = Modifier.weight(1f).height(50.dp),
                    shape = RoundedCornerShape(8.dp),
                ) {
                    Text(if (speakerOn) "切到听筒" else "打开扬声器")
                }
            }
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = onLeave,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = SunsetColors.CoralDark),
            ) {
                Text("离开房间")
            }
        }
    }
}
