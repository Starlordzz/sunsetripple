package host.msknet.sunsetripple.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.core.content.ContextCompat

class PermissionLaunchers internal constructor(
    val withRoomPreconditions: (() -> Unit) -> Unit,
    val withMicPermission: (() -> Unit) -> Unit,
    val withBluetoothPermissions: (BluetoothRoomRole, () -> Unit) -> Unit,
    val withNearbyPermissions: (() -> Unit) -> Unit,
)

@Composable
fun rememberDiscoverableLauncher(
    onCanceled: () -> Unit,
    onAllowed: () -> Unit,
): (Intent) -> Unit {
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode == Activity.RESULT_CANCELED) onCanceled()
        else onAllowed()
    }
    return launcher::launch
}

@Composable
fun rememberPermissionLaunchers(
    context: Context,
    sdkInt: Int,
    runWhenLocationReady: (() -> Unit) -> Unit,
    onDenied: (String) -> Unit,
): PermissionLaunchers {
    val roomActions = remember { PendingActionQueue<() -> Unit>() }
    val micActions = remember { PendingActionQueue<() -> Unit>() }
    val bluetoothActions = remember { PendingActionQueue<Pair<BluetoothRoomRole, () -> Unit>>() }
    val nearbyActions = remember { PendingActionQueue<() -> Unit>() }

    val roomLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { result ->
        val action = roomActions.take()
        val denied = RoomPermissions.blockingDenied(result, sdkInt)
        if (denied.isEmpty()) action?.let(runWhenLocationReady)
        else onDenied(RoomPermissions.deniedMessage(denied))
    }
    val micLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val action = micActions.take()
        if (granted) action?.invoke()
        else onDenied("缺少麦克风权限，无法录音")
    }
    val bluetoothLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { result ->
        val (role, action) = bluetoothActions.take() ?: return@rememberLauncherForActivityResult
        val denied = BluetoothPermissions.blockingDenied(result, sdkInt, role)
        if (denied.isEmpty()) action()
        else onDenied(BluetoothPermissions.deniedMessage(denied))
    }
    val nearbyLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { result ->
        val action = nearbyActions.take()
        val denied = NearbyPermissions.blockingDenied(result, sdkInt)
        if (denied.isEmpty()) action?.invoke()
        else onDenied(NearbyPermissions.deniedMessage(denied))
    }

    return PermissionLaunchers(
        withRoomPreconditions = { action ->
            val required = RoomPermissions.required(sdkInt)
            val missing = required.any {
                ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing) {
                roomActions.replace(action)
                roomLauncher.launch(RoomPermissions.requested(sdkInt).toTypedArray())
            } else {
                runWhenLocationReady(action)
            }
        },
        withMicPermission = { action ->
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
            if (granted) action()
            else {
                micActions.replace(action)
                micLauncher.launch(Manifest.permission.RECORD_AUDIO)
            }
        },
        withBluetoothPermissions = { role, action ->
            val required = BluetoothPermissions.required(sdkInt, role)
            val missing = required.any {
                ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing) {
                bluetoothActions.replace(role to action)
                bluetoothLauncher.launch(required.toTypedArray())
            } else {
                action()
            }
        },
        withNearbyPermissions = { action ->
            val required = NearbyPermissions.required(sdkInt)
            val missing = required.any {
                ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing) {
                nearbyActions.replace(action)
                nearbyLauncher.launch(required.toTypedArray())
            } else {
                action()
            }
        },
    )
}
