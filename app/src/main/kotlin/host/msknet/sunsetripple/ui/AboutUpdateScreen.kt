package host.msknet.sunsetripple.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import host.msknet.sunsetripple.update.UpdateState

@Composable
fun AboutUpdateScreen(
    versionName: String,
    updateState: UpdateState,
    onCheckUpdate: () -> Unit,
    onOpenGithub: () -> Unit,
    onClose: () -> Unit,
) {
    BackHandler(onBack = onClose)
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("关于与更新", style = androidx.compose.material3.MaterialTheme.typography.headlineMedium, color = SunsetColors.Ink)
        Text("SunsetRipple · 近场语音房", color = SunsetColors.Muted)
        Text("当前版本  $versionName", color = SunsetColors.Ink)
        Text("语音链路不依赖互联网；版本检查会访问 GitHub。", color = SunsetColors.Muted)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SunsetButton(onClick = onCheckUpdate, modifier = Modifier.weight(1f).height(50.dp)) {
                Text("检查更新")
            }
            SunsetOutlinedButton(onClick = onOpenGithub, modifier = Modifier.weight(1f).height(50.dp)) {
                Text("GitHub 项目")
            }
        }
        Text(updateMessage(updateState), color = SunsetColors.Muted)
        Text("CHANGELOG\n当前 alpha5 开发分支聚焦关于页与更新状态接线。", color = SunsetColors.Ink)
        Text("许可证\nApache-2.0", color = SunsetColors.Ink)
        Text("隐私说明\n不要求账号，语音只在近场设备之间传输。", color = SunsetColors.Ink)
        SunsetOutlinedButton(onClick = onClose, modifier = Modifier.fillMaxWidth().height(50.dp)) {
            Text("返回首页")
        }
    }
}

private fun updateMessage(state: UpdateState): String = when (state) {
    UpdateState.Idle -> "尚未检查更新"
    UpdateState.Checking -> "正在检查更新……"
    UpdateState.UpToDate -> "当前已是最新版本"
    is UpdateState.Available -> "发现版本 ${state.versionName}"
    is UpdateState.Failed -> "检查更新失败：${state.message}"
}
