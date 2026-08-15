package host.msknet.sunsetripple.ui

enum class RoomKind { WIFI, BLUETOOTH, NEARBY }

enum class BluetoothRoomStart { Idle, AwaitingDiscoverable, Host, Scan }

enum class RoomCleanup { NONE, WIFI, BLUETOOTH, NEARBY }

enum class NearbyRoomStart { Host, Scan }

object NearbyRoomFlow {
    fun hostStart(): NearbyRoomStart = NearbyRoomStart.Host
    fun guestStart(): NearbyRoomStart = NearbyRoomStart.Scan
}

object BluetoothRoomFlow {
    fun hostStart(discoverableAccepted: Boolean?): BluetoothRoomStart = when (discoverableAccepted) {
        null -> BluetoothRoomStart.AwaitingDiscoverable
        true -> BluetoothRoomStart.Host
        false -> BluetoothRoomStart.Idle
    }

    fun guestStart(): BluetoothRoomStart = BluetoothRoomStart.Scan

    fun cleanupFor(kind: RoomKind?): RoomCleanup = when (kind) {
        RoomKind.WIFI -> RoomCleanup.WIFI
        RoomKind.BLUETOOTH -> RoomCleanup.BLUETOOTH
        RoomKind.NEARBY -> RoomCleanup.NEARBY
        null -> RoomCleanup.NONE
    }
}
