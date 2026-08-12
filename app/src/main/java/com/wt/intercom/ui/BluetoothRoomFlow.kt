package com.wt.intercom.ui

enum class RoomKind { WIFI, BLUETOOTH }

enum class BluetoothRoomStart { Idle, AwaitingDiscoverable, Host, Scan }

enum class RoomCleanup { NONE, WIFI, BLUETOOTH }

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
        null -> RoomCleanup.NONE
    }
}
