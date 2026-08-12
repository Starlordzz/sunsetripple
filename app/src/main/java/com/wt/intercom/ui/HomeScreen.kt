package com.wt.intercom.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun HomeScreen(
    nickname: String,
    onNicknameChange: (String) -> Unit,
    onCreateWifiRoom: () -> Unit,
    onJoinWifiRoom: () -> Unit,
    onLoopbackTest: () -> Unit,
    status: String?,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SunsetColors.Canvas)
            .verticalScroll(rememberScrollState()),
    ) {
        SunsetBrandHeader {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 24.dp, end = 24.dp, bottom = 28.dp),
            ) {
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

        Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 24.dp, bottom = 32.dp)) {
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

            Spacer(Modifier.height(26.dp))
            Text(
                text = "WiFi 直连",
                style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
                color = SunsetColors.Ink,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "无需路由器，适合多人同时通话",
                style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                color = SunsetColors.Muted,
            )
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = onCreateWifiRoom,
                    modifier = Modifier.weight(1f).height(54.dp),
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = SunsetColors.Coral),
                ) {
                    Text("创建房间")
                }
                OutlinedButton(
                    onClick = onJoinWifiRoom,
                    modifier = Modifier.weight(1f).height(54.dp),
                    shape = RoundedCornerShape(8.dp),
                ) {
                    Text("加入房间")
                }
            }

            Spacer(Modifier.height(26.dp))
            HorizontalDivider(color = SunsetColors.Line)
            Spacer(Modifier.height(18.dp))
            OutlinedButton(
                onClick = onLoopbackTest,
                modifier = Modifier.fillMaxWidth().height(50.dp),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = SunsetColors.CoralDark),
            ) {
                RippleStatusMark(active = true, modifier = Modifier.width(28.dp).height(28.dp))
                Spacer(Modifier.width(8.dp))
                Text("检查麦克风与耳机")
            }

            if (status != null) {
                Spacer(Modifier.height(18.dp))
                Text(
                    text = status,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(SunsetColors.SoftCoral, androidx.compose.foundation.shape.RoundedCornerShape(6.dp))
                        .padding(14.dp),
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium.copy(
                        fontWeight = FontWeight.Medium
                    ),
                    color = SunsetColors.CoralDark,
                )
            }
        }
    }
}
