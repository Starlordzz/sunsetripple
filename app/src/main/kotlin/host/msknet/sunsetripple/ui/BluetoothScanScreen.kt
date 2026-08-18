package host.msknet.sunsetripple.ui

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import host.msknet.sunsetripple.R

@SuppressLint("MissingPermission")
@Composable
fun BluetoothScanScreen(
    bondedDevices: List<BluetoothDevice>,
    discoveredDevices: List<BluetoothDevice>,
    discovering: Boolean,
    status: String?,
    onPick: (BluetoothDevice) -> Unit,
    onScanAgain: () -> Unit,
    onBack: () -> Unit,
) {
    val devices = (bondedDevices + discoveredDevices).distinctBy { it.address }
    Column(Modifier.fillMaxSize().background(SunsetColors.Canvas)) {
        SunsetBrandHeader(height = 170.dp) {
            Column(Modifier.align(Alignment.BottomStart).padding(20.dp)) {
                Text(
                    stringResource(R.string.scan_bluetooth_title),
                    style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
                    color = Color.White,
                )
                Text(
                    stringResource(R.string.scan_bluetooth_subtitle),
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.82f),
                )
            }
        }
        status?.let {
            Text(
                it,
                modifier = Modifier.fillMaxWidth().background(SunsetColors.SoftCoral).padding(14.dp, 11.dp),
                style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                color = SunsetColors.Ink,
            )
        }
        LazyColumn(Modifier.weight(1f).padding(horizontal = 20.dp)) {
            item {
                Text(
                    when {
                discovering -> stringResource(R.string.scanning_count, devices.size)
                devices.isEmpty() -> stringResource(R.string.no_devices)
                else -> stringResource(R.string.available_device_count, devices.size)
                    },
                    modifier = Modifier.padding(top = 22.dp, bottom = 10.dp),
                    style = androidx.compose.material3.MaterialTheme.typography.labelLarge,
                    color = SunsetColors.Muted,
                )
            }
            items(devices, key = { it.address }) { device ->
                val bonded = device.bondState == BluetoothDevice.BOND_BONDED
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onPick(device) }.padding(vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RippleStatusMark(active = bonded, Modifier.size(38.dp))
                    Column(Modifier.weight(1f).padding(start = 12.dp)) {
                        Text(
                            device.name.orEmpty().ifBlank { stringResource(R.string.unnamed_bluetooth_device) },
                            fontWeight = FontWeight.SemiBold,
                            color = SunsetColors.Ink,
                        )
                        Text(
                            stringResource(if (bonded) R.string.paired_device else R.string.pair_required, device.address),
                            style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                            color = SunsetColors.Muted,
                        )
                    }
                        Text(stringResource(if (bonded) R.string.join else R.string.pair), color = SunsetColors.Coral, fontWeight = FontWeight.SemiBold)
                }
                HorizontalDivider(color = SunsetColors.Line.copy(alpha = 0.65f))
            }
        }
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
