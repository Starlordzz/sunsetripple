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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import host.msknet.sunsetripple.update.UpdateState
import host.msknet.sunsetripple.R

@Composable
fun AboutUpdateScreen(
    versionName: String,
    updateState: UpdateState,
    onCheckUpdate: () -> Unit,
    onDownloadUpdate: () -> Unit,
    onInstallUpdate: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onReportIssue: () -> Unit,
    onOpenGithub: () -> Unit,
    onClose: () -> Unit,
) {
    var contentState by remember { mutableStateOf(AboutContentState()) }
    BackHandler(onBack = onClose)
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(stringResource(R.string.about_title), style = androidx.compose.material3.MaterialTheme.typography.headlineMedium, color = SunsetColors.Ink)
        Text(stringResource(R.string.about_product), color = SunsetColors.Muted)
        Text(stringResource(R.string.current_version, versionName), color = SunsetColors.Ink)
        Text(stringResource(R.string.update_network_note), color = SunsetColors.Muted)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SunsetButton(onClick = onCheckUpdate, modifier = Modifier.weight(1f).height(50.dp)) {
                Text(stringResource(R.string.check_update))
            }
            SunsetOutlinedButton(onClick = onOpenGithub, modifier = Modifier.weight(1f).height(50.dp)) {
                Text(stringResource(R.string.github_project))
            }
        }
        Text(updateMessage(updateState), color = SunsetColors.Muted)
        when (updateState) {
            is UpdateState.Available -> SunsetButton(
                onClick = onDownloadUpdate,
                modifier = Modifier.fillMaxWidth().height(50.dp),
            ) { Text(stringResource(R.string.download_update)) }
            is UpdateState.ReadyToInstall, UpdateState.InstallPermissionRequired -> SunsetButton(
                onClick = onInstallUpdate,
                modifier = Modifier.fillMaxWidth().height(50.dp),
            ) {
                Text(stringResource(if (updateState == UpdateState.InstallPermissionRequired) R.string.continue_install_permission else R.string.install_with_system))
            }
            else -> Unit
        }
        AboutSectionButton(
            title = stringResource(R.string.changelog_title),
            body = stringResource(R.string.changelog_body),
            expanded = contentState.expandedSection == AboutSection.CHANGELOG,
            onClick = { contentState = contentState.toggle(AboutSection.CHANGELOG) },
        )
        AboutSectionButton(
            title = stringResource(R.string.license_title),
            body = stringResource(R.string.license_body),
            expanded = contentState.expandedSection == AboutSection.LICENSE,
            onClick = { contentState = contentState.toggle(AboutSection.LICENSE) },
        )
        AboutSectionButton(
            title = stringResource(R.string.privacy_title),
            body = stringResource(R.string.privacy_body),
            expanded = contentState.expandedSection == AboutSection.PRIVACY,
            onClick = { contentState = contentState.toggle(AboutSection.PRIVACY) },
        )
        SunsetOutlinedButton(onClick = onExportDiagnostics, modifier = Modifier.fillMaxWidth().height(50.dp)) {
            Text(stringResource(R.string.export_diagnostics))
        }
        SunsetOutlinedButton(onClick = onReportIssue, modifier = Modifier.fillMaxWidth().height(50.dp)) {
            Text(stringResource(R.string.report_github_issue))
        }
        SunsetOutlinedButton(onClick = onClose, modifier = Modifier.fillMaxWidth().height(50.dp)) {
            Text(stringResource(R.string.back_home))
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
    val sectionStateDescription = stringResource(if (expanded) R.string.expanded else R.string.collapsed)
    val buttonText = stringResource(if (expanded) R.string.collapse_section else R.string.view_section, title)
    SunsetOutlinedButton(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .semantics { stateDescription = sectionStateDescription },
    ) {
        Text(buttonText)
    }
    if (expanded) {
        Text(body, color = SunsetColors.Muted)
    }
}

@Composable
private fun updateMessage(state: UpdateState): String = when (state) {
    UpdateState.Idle -> stringResource(R.string.update_idle)
    UpdateState.Checking -> stringResource(R.string.update_checking)
    UpdateState.UpToDate -> stringResource(R.string.update_current)
    is UpdateState.Available -> stringResource(R.string.update_available, state.versionName)
    is UpdateState.Downloading -> stringResource(R.string.update_downloading, state.versionName)
    is UpdateState.ReadyToInstall -> stringResource(R.string.update_ready, state.versionName)
    UpdateState.InstallPermissionRequired -> stringResource(R.string.update_permission_required)
    UpdateState.InstallConfirmationOpened -> stringResource(R.string.update_confirmation_opened)
    UpdateState.InstallCancelled -> stringResource(R.string.update_cancelled)
    is UpdateState.Failed -> stringResource(R.string.update_failed, state.message)
}
