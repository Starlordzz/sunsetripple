package host.msknet.sunsetripple.ui

import android.net.wifi.p2p.WifiP2pDevice
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import host.msknet.sunsetripple.R

@Composable
fun ScanScreen(
    peers: List<WifiP2pDevice>,
    discovering: Boolean,
    status: String?,
    onPick: (WifiP2pDevice) -> Unit,
    onScanAgain: () -> Unit,
    onBack: () -> Unit,
) {
    Column(Modifier.fillMaxSize().background(SunsetColors.Canvas)) {
        SunsetBrandHeader(height = 170.dp) {
            Column(Modifier.align(Alignment.BottomStart).padding(20.dp)) {
                Text(
                    stringResource(R.string.scan_wifi_title),
                    style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
                    color = androidx.compose.ui.graphics.Color.White,
                )
                Text(
                    stringResource(R.string.scan_wifi_subtitle),
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                    color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.82f),
                )
            }
        }
        if (status != null) {
            Text(
                status,
                modifier = Modifier.fillMaxWidth().background(SunsetColors.SoftCoral).padding(14.dp, 11.dp),
                style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                color = SunsetColors.Ink,
            )
        }
        LazyColumn(Modifier.weight(1f).padding(horizontal = 20.dp)) {
            item {
                Text(
                    when {
                        discovering && peers.isEmpty() -> stringResource(R.string.scan_waiting)
                        discovering -> stringResource(R.string.scanning_count, peers.size)
                        peers.isEmpty() -> stringResource(R.string.scan_stopped)
                        else -> stringResource(R.string.nearby_device_count, peers.size)
                    },
                    modifier = Modifier.padding(top = 22.dp, bottom = 10.dp),
                    style = androidx.compose.material3.MaterialTheme.typography.labelLarge,
                    color = SunsetColors.Muted,
                )
            }
            items(peers, key = { it.deviceAddress }) { device ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onPick(device) }.padding(vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RippleStatusMark(active = true, Modifier.size(38.dp))
                    Column(Modifier.weight(1f).padding(start = 12.dp)) {
                        Text(
                            device.deviceName.orEmpty().ifBlank { stringResource(R.string.unnamed_device) },
                            fontWeight = FontWeight.SemiBold,
                            color = SunsetColors.Ink,
                        )
                        Text(
                            device.deviceAddress,
                            style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                            color = SunsetColors.Muted,
                        )
                    }
                        Text(stringResource(R.string.join), color = SunsetColors.Coral, fontWeight = FontWeight.SemiBold)
                }
                HorizontalDivider(color = SunsetColors.Line.copy(alpha = 0.65f))
            }
        }
        Spacer(Modifier.height(8.dp))
        OutlinedButton(
            onClick = onScanAgain,
            enabled = !discovering,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).height(50.dp),
            shape = RoundedCornerShape(8.dp),
        ) { Text(stringResource(if (discovering) R.string.scanning else R.string.scan_again)) }
        Spacer(Modifier.height(10.dp))
        OutlinedButton(
            onClick = onBack,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).height(50.dp),
            shape = RoundedCornerShape(8.dp),
        ) { Text(stringResource(R.string.back_home)) }
        Spacer(Modifier.height(20.dp))
    }
}
