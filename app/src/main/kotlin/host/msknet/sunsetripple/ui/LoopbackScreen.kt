package host.msknet.sunsetripple.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun LoopbackScreen(onStop: () -> Unit) {
    Column(Modifier.fillMaxSize().background(SunsetColors.Canvas)) {
        SunsetBrandHeader(height = 230.dp) {
            Column(Modifier.align(Alignment.BottomStart).padding(22.dp, 28.dp)) {
                Text(
                    "声音回环",
                    style = androidx.compose.material3.MaterialTheme.typography.displaySmall,
                    color = androidx.compose.ui.graphics.Color.White,
                )
                Text(
                    "测试麦克风、编码与播放链路",
                    color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.82f),
                )
            }
        }
        Column(
            modifier = Modifier.fillMaxWidth().weight(1f).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(34.dp))
            RippleStatusMark(active = true, Modifier.size(104.dp))
            Spacer(Modifier.height(24.dp))
            Text(
                "正在聆听",
                style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
                color = SunsetColors.Ink,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "对麦克风说话，片刻后会听到自己的声音。使用耳机可避免啸叫。",
                style = androidx.compose.material3.MaterialTheme.typography.bodyLarge,
                color = SunsetColors.Muted,
            )
            Spacer(Modifier.weight(1f))
            Button(
                onClick = onStop,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = SunsetColors.CoralDark),
            ) {
                Text("结束测试", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
