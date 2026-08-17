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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import host.msknet.sunsetripple.update.UpdateState

@Composable
fun AboutUpdateScreen(
    versionName: String,
    updateState: UpdateState,
    onCheckUpdate: () -> Unit,
    onOpenGithub: () -> Unit,
    onClose: () -> Unit,
) {
    var contentState by remember { mutableStateOf(AboutContentState()) }
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
        AboutSectionButton(
            title = "CHANGELOG",
            body = "Alpha 5 开发中：新增关于与更新入口和可测试的更新状态模型。签名更新、下载与安装尚未接入。",
            expanded = contentState.expandedSection == AboutSection.CHANGELOG,
            onClick = { contentState = contentState.toggle(AboutSection.CHANGELOG) },
        )
        AboutSectionButton(
            title = "许可证",
            body = "本项目采用 Apache License 2.0。",
            expanded = contentState.expandedSection == AboutSection.LICENSE,
            onClick = { contentState = contentState.toggle(AboutSection.LICENSE) },
        )
        AboutSectionButton(
            title = "隐私说明",
            body = "不要求账号。语音只在近场设备之间传输；手动检查更新时会访问 GitHub，但不会影响当前通话。",
            expanded = contentState.expandedSection == AboutSection.PRIVACY,
            onClick = { contentState = contentState.toggle(AboutSection.PRIVACY) },
        )
        SunsetOutlinedButton(onClick = onClose, modifier = Modifier.fillMaxWidth().height(50.dp)) {
            Text("返回首页")
        }
    }
}

@Composable
private fun AboutSectionButton(
    title: String,
    body: String,
    expanded: Boolean,
    onClick: () -> Unit,
) {
    SunsetOutlinedButton(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .semantics { stateDescription = if (expanded) "已展开" else "已收起" },
    ) {
        Text(if (expanded) "$title  收起" else "$title  查看")
    }
    if (expanded) {
        Text(body, color = SunsetColors.Muted)
    }
}

private fun updateMessage(state: UpdateState): String = when (state) {
    UpdateState.Idle -> "尚未检查更新"
    UpdateState.Checking -> "正在检查更新……"
    UpdateState.UpToDate -> "当前已是最新版本"
    is UpdateState.Available -> "发现版本 ${state.versionName}"
    is UpdateState.Failed -> "检查更新失败：${state.message}"
}
