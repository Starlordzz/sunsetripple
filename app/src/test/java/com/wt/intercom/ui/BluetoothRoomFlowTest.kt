package com.wt.intercom.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class BluetoothRoomFlowTest {

    @Test
    fun `蓝牙建房等待可发现授权成功后才启动主机`() {
        assertEquals(
            BluetoothRoomStart.AwaitingDiscoverable,
            BluetoothRoomFlow.hostStart(discoverableAccepted = null),
        )
        assertEquals(
            BluetoothRoomStart.Host,
            BluetoothRoomFlow.hostStart(discoverableAccepted = true),
        )
        assertEquals(
            BluetoothRoomStart.Idle,
            BluetoothRoomFlow.hostStart(discoverableAccepted = false),
        )
    }

    @Test
    fun `蓝牙加入进入设备扫描`() {
        assertEquals(BluetoothRoomStart.Scan, BluetoothRoomFlow.guestStart())
    }

    @Test
    fun `离房只释放当前房型的资源`() {
        assertEquals(RoomCleanup.WIFI, BluetoothRoomFlow.cleanupFor(RoomKind.WIFI))
        assertEquals(RoomCleanup.BLUETOOTH, BluetoothRoomFlow.cleanupFor(RoomKind.BLUETOOTH))
        assertEquals(RoomCleanup.NONE, BluetoothRoomFlow.cleanupFor(null))
    }
}
