package com.wt.intercom.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
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
) {
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text(roomLabel)
        Spacer(Modifier.height(4.dp))
        Text("成员 ${state.members.size} 人")
        Spacer(Modifier.height(12.dp))
        LazyColumn(Modifier.weight(1f)) {
            items(state.members, key = { it.id }) { m ->
                Card(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Row(
                        Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            Modifier
                                .size(12.dp)
                                .clip(CircleShape)
                                .background(if (m.speaking) Color(0xFF43A047) else Color.LightGray)
                        )
                        Text(
                            (if (m.isSelf) "${m.nickname}（我）" else m.nickname) +
                                if (m.isSelf && state.micMuted) "（已静音）" else "",
                            Modifier.padding(start = 12.dp),
                        )
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            OutlinedButton(onClick = onToggleMute, modifier = Modifier.weight(1f)) {
                Text(if (state.micMuted) "取消静音" else "静音")
            }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = onToggleSpeaker, modifier = Modifier.weight(1f)) {
                Text(if (speakerOn) "听筒" else "扬声器")
            }
        }
        Spacer(Modifier.height(8.dp))
        Button(onClick = onLeave, modifier = Modifier.fillMaxWidth()) { Text("离开房间") }
    }
}
