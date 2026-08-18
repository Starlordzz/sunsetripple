package host.msknet.sunsetripple.ui

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
import host.msknet.sunsetripple.transport.nearby.NearbyEndpoint
import host.msknet.sunsetripple.transport.nearby.NearbyEndpointState

@Composable
fun NearbyScanScreen(
    endpoints: List<NearbyEndpoint>,
    discovering: Boolean,
    status: String?,
    onPick: (NearbyEndpoint) -> Unit,
    onScanAgain: () -> Unit,
    onBack: () -> Unit,
) {
    Column(Modifier.fillMaxSize().background(SunsetColors.Canvas)) {
        SunsetBrandHeader(height = 170.dp) {
            Column(Modifier.align(Alignment.BottomStart).padding(20.dp)) {
                Text(
                    stringResource(R.string.scan_nearby_title),
                    style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
                    color = Color.White,
                )
                Text(
                    stringResource(R.string.scan_nearby_subtitle),
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
                discovering -> stringResource(R.string.discovering_count, endpoints.size)
                endpoints.isEmpty() -> stringResource(R.string.no_rooms)
                else -> stringResource(R.string.joinable_room_count, endpoints.size)
                    },
                    modifier = Modifier.padding(top = 22.dp, bottom = 10.dp),
                    style = androidx.compose.material3.MaterialTheme.typography.labelLarge,
                    color = SunsetColors.Muted,
                )
            }
            items(endpoints, key = { it.id }) { endpoint ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(enabled = endpoint.state == NearbyEndpointState.DISCOVERED) { onPick(endpoint) }
                        .padding(vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RippleStatusMark(
                        active = endpoint.state == NearbyEndpointState.CONNECTED,
                        modifier = Modifier.size(38.dp),
                    )
                    Column(Modifier.weight(1f).padding(start = 12.dp)) {
                        Text(endpoint.name.ifBlank { stringResource(R.string.unnamed_nearby_room) }, fontWeight = FontWeight.SemiBold)
                        Text(
                            when (endpoint.state) {
                            NearbyEndpointState.DISCOVERED -> stringResource(R.string.can_join)
                            NearbyEndpointState.CONNECTING -> stringResource(R.string.connecting)
                            NearbyEndpointState.CONNECTED -> stringResource(R.string.connected)
                            },
                            style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                            color = SunsetColors.Muted,
                        )
                    }
                        Text(stringResource(R.string.join), color = SunsetColors.Coral, fontWeight = FontWeight.SemiBold)
                }
                HorizontalDivider(color = SunsetColors.Line.copy(alpha = 0.65f))
            }
        }
        OutlinedButton(
            onClick = onScanAgain,
            enabled = !discovering,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).height(50.dp),
            shape = RoundedCornerShape(8.dp),
            ) { Text(stringResource(if (discovering) R.string.discovering else R.string.discover_again)) }
        Spacer(Modifier.height(10.dp))
        OutlinedButton(
            onClick = onBack,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).height(50.dp),
            shape = RoundedCornerShape(8.dp),
        ) { Text(stringResource(R.string.back_home)) }
        Spacer(Modifier.height(20.dp))
    }
}
