package host.msknet.sunsetripple.session

import host.msknet.sunsetripple.transport.TransportLog
import host.msknet.sunsetripple.transport.nearby.NearbyRoomManager
import host.msknet.sunsetripple.ui.RoomKind
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class RoomLifecycleCoordinator(
    private val disconnectWifi: () -> Unit,
    private val closeBluetooth: () -> Unit,
    private val stopCallRuntime: () -> Unit,
) {
    private val _session = MutableStateFlow<RoomSession?>(null)
    val session: StateFlow<RoomSession?> = _session.asStateFlow()

    private val _bluetoothSession = MutableStateFlow<BluetoothRoomSession?>(null)
    val bluetoothSession: StateFlow<BluetoothRoomSession?> = _bluetoothSession.asStateFlow()

    private val _nearbyManager = MutableStateFlow<NearbyRoomManager?>(null)
    val nearbyManager: StateFlow<NearbyRoomManager?> = _nearbyManager.asStateFlow()

    private val _roomKind = MutableStateFlow<RoomKind?>(null)
    val roomKind: StateFlow<RoomKind?> = _roomKind.asStateFlow()

    fun publishSession(session: RoomSession, kind: RoomKind) {
        require(kind != RoomKind.BLUETOOTH)
        _session.value = session
        _roomKind.value = kind
    }

    fun publishBluetoothSession(session: BluetoothRoomSession) {
        _bluetoothSession.value = session
        _roomKind.value = RoomKind.BLUETOOTH
    }

    fun publishNearbyManager(manager: NearbyRoomManager?) {
        _nearbyManager.value = manager
    }

    fun takeNearbyManager(): NearbyRoomManager? = _nearbyManager.value.also {
        _nearbyManager.value = null
    }

    fun setRoomKind(kind: RoomKind?) {
        _roomKind.value = kind
    }

    fun clearRoomKind() {
        _roomKind.value = null
    }

    fun isCurrent(session: RoomSession): Boolean = _session.value === session

    fun isCurrent(session: BluetoothRoomSession): Boolean = _bluetoothSession.value === session

    fun release(keepWifiGroup: Boolean = false) {
        when (_roomKind.value) {
            RoomKind.WIFI -> {
                val current = _session.value
                _session.value = null
                current?.let { runCatching { it.leave() }.onFailure { logLeaveFailure("WiFi", it) } }
                if (!keepWifiGroup) disconnectWifi()
            }
            RoomKind.BLUETOOTH -> {
                val current = _bluetoothSession.value
                _bluetoothSession.value = null
                current?.let { runCatching { it.leave() }.onFailure { logLeaveFailure("蓝牙", it) } }
                closeBluetooth()
            }
            RoomKind.NEARBY -> {
                val current = _session.value
                _session.value = null
                current?.let { runCatching { it.leave() }.onFailure { logLeaveFailure("Nearby", it) } }
                _nearbyManager.value?.close()
                _nearbyManager.value = null
            }
            null -> Unit
        }
        _roomKind.value = null
        stopCallRuntime()
    }

    private fun logLeaveFailure(label: String, error: Throwable) {
        TransportLog.w("$label 离房异常: ${error.message}", error)
    }
}
