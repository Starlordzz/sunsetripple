package com.wt.intercom.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("落日后残波")
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value = nickname,
            onValueChange = onNicknameChange,
            label = { Text("昵称") },
            singleLine = true,
        )
        Spacer(Modifier.height(24.dp))
        Button(onClick = onCreateWifiRoom, modifier = Modifier.fillMaxWidth()) {
            Text("创建 WiFi 房（全双工会议）")
        }
        Spacer(Modifier.height(12.dp))
        Button(onClick = onJoinWifiRoom, modifier = Modifier.fillMaxWidth()) {
            Text("加入 WiFi 房")
        }
        Spacer(Modifier.height(12.dp))
        OutlinedButton(onClick = onLoopbackTest, modifier = Modifier.fillMaxWidth()) {
            Text("音频回环自测")
        }
        if (status != null) {
            Spacer(Modifier.height(16.dp))
            Text(status)
        }
    }
}
