package host.msknet.sunsetripple.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun HomeScreen(
    nickname: String,
    onNicknameChange: (String) -> Unit,
    onCreateWifiRoom: (Offset) -> Unit,
    onJoinWifiRoom: (Offset) -> Unit,
    onCreateBluetoothRoom: (Offset) -> Unit,
    onJoinBluetoothRoom: (Offset) -> Unit,
    onCreateNearbyRoom: () -> Unit,
    onJoinNearbyRoom: () -> Unit,
    onLoopbackTest: () -> Unit,
    status: String?,
    headerPhase: State<Float>? = null,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(SunsetColors.Canvas)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            SunsetBrandHeader(phase = headerPhase) {
            SunsetReveal(
                delayMillis = 40,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 24.dp, end = 24.dp, bottom = 28.dp),
            ) {
                Column {
                    Text(
                        text = "落日后残波",
                        style = androidx.compose.material3.MaterialTheme.typography.displaySmall,
                        color = Color.White,
                    )
                    Spacer(Modifier.height(5.dp))
                    Text(
                        text = "近场语音房",
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.82f),
                    )
                }
            }
            }

            Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 24.dp, bottom = 32.dp)) {
            SunsetReveal(delayMillis = 100) {
                Column {
                    Text(
                        text = "你的称呼",
                        style = androidx.compose.material3.MaterialTheme.typography.labelLarge,
                        color = SunsetColors.Muted,
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = nickname,
                        onValueChange = onNicknameChange,
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("输入昵称") },
                        singleLine = true,
                    )
                }
            }

            Spacer(Modifier.height(26.dp))
            SunsetReveal(delayMillis = 170) {
                Column {
                    RoomModeHeading(
                        title = "WiFi 直连",
                        description = "无需路由器，适合多人同时通话",
                        accent = SunsetColors.Coral,
                    )
                    Spacer(Modifier.height(16.dp))
                    RoomActionRow(
                        createSupportingText = "发起频道",
                        joinSupportingText = "搜索频道",
                        createColor = SunsetColors.Coral,
                        onCreate = onCreateWifiRoom,
                        onJoin = onJoinWifiRoom,
                    )
                }
            }

            Spacer(Modifier.height(28.dp))
            SunsetReveal(delayMillis = 240) {
                Column {
                    RoomModeHeading(
                        title = "蓝牙房",
                        description = "按住说话，适合无网络的近距离协作",
                        accent = SunsetColors.Gold,
                    )
                    Spacer(Modifier.height(16.dp))
                    RoomActionRow(
                        createSupportingText = "发起频道",
                        joinSupportingText = "搜索频道",
                        createColor = SunsetColors.CoralDark,
                        onCreate = onCreateBluetoothRoom,
                        onJoin = onJoinBluetoothRoom,
                    )
                }
            }

            if (HomeRoomAvailability.isVisible(RoomKind.NEARBY)) {
                Spacer(Modifier.height(28.dp))
                Text(
                    text = "Nearby 房",
                    style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
                    color = SunsetColors.Ink,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    text = "全双工语音，需要 Google Play 服务",
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                    color = SunsetColors.Muted,
                )
                Spacer(Modifier.height(16.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SunsetButton(
                        onClick = onCreateNearbyRoom,
                        modifier = Modifier.weight(1f).height(54.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = SunsetColors.Orange),
                    ) {
                        Text("创建 Nearby 房")
                    }
                    SunsetOutlinedButton(
                        onClick = onJoinNearbyRoom,
                        modifier = Modifier.weight(1f).height(54.dp),
                    ) {
                        Text("加入 Nearby 房")
                    }
                }
            }

            SunsetReveal(delayMillis = 310) {
                Column {
                    Spacer(Modifier.height(26.dp))
                    HorizontalDivider(color = SunsetColors.Line)
                    Spacer(Modifier.height(18.dp))
                    SunsetOutlinedButton(
                        onClick = onLoopbackTest,
                        modifier = Modifier.fillMaxWidth().height(50.dp),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = SunsetColors.CoralDark),
                    ) {
                        RippleStatusMark(active = true, modifier = Modifier.width(28.dp).height(28.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("检查麦克风与耳机")
                    }

                    AnimatedVisibility(
                        visible = status != null,
                        enter = fadeIn() + expandVertically(),
                        exit = fadeOut() + shrinkVertically(),
                    ) {
                        status?.let { message ->
                            Column {
                                Spacer(Modifier.height(18.dp))
                                Text(
                                    text = message,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(
                                            SunsetColors.SoftCoral,
                                            androidx.compose.foundation.shape.RoundedCornerShape(6.dp),
                                        )
                                        .padding(14.dp),
                                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium.copy(
                                        fontWeight = FontWeight.Medium,
                                    ),
                                    color = SunsetColors.CoralDark,
                                )
                            }
                        }
                    }
                }
            }
        }
        }

    }
}

@Composable
private fun RoomActionRow(
    createSupportingText: String,
    joinSupportingText: String,
    createColor: Color,
    onCreate: (Offset) -> Unit,
    onJoin: (Offset) -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val gap = 14.dp
        val orbSize = minOf(136.dp, (maxWidth - gap) / 2)
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(gap, Alignment.CenterHorizontally),
        ) {
            SunsetActionOrb(
                label = "建房",
                supportingText = createSupportingText,
                onClick = onCreate,
                modifier = Modifier.size(orbSize),
                containerColor = createColor,
            )
            SunsetActionOrb(
                label = "进房",
                supportingText = joinSupportingText,
                onClick = onJoin,
                modifier = Modifier.size(orbSize),
                outlined = true,
            )
        }
    }
}

@Composable
private fun RoomModeHeading(title: String, description: String, accent: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .width(4.dp)
                .height(46.dp)
                .background(accent, RoundedCornerShape(2.dp)),
        )
        Spacer(Modifier.width(12.dp))
        Column {
            Text(
                text = title,
                style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
                color = SunsetColors.Ink,
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text = description,
                style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                color = SunsetColors.Muted,
            )
        }
    }
}
