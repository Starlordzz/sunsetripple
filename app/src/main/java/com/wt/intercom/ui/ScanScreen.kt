package com.wt.intercom.ui

import android.net.wifi.p2p.WifiP2pDevice
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun ScanScreen(
    peers: List<WifiP2pDevice>,
    status: String?,
    onPick: (WifiP2pDevice) -> Unit,
    onBack: () -> Unit,
) {
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text("选择要加入的设备（对方需已点「创建 WiFi 房」）")
        Spacer(Modifier.height(8.dp))
        if (status != null) {
            Text(status)
            Spacer(Modifier.height(8.dp))
        }
        LazyColumn(Modifier.weight(1f)) {
            items(peers, key = { it.deviceAddress }) { device ->
                Card(
                    Modifier.fillMaxWidth().padding(vertical = 4.dp).clickable { onPick(device) }
                ) {
                    Text(
                        device.deviceName.orEmpty().ifBlank { device.deviceAddress },
                        Modifier.padding(16.dp),
                    )
                }
            }
        }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("返回") }
    }
}
