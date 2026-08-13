package com.wt.intercom.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class NearbyRoomFlowTest {

    @Test
    fun `Nearby 建房直接广告而加入进入扫描`() {
        assertEquals(NearbyRoomStart.Host, NearbyRoomFlow.hostStart())
        assertEquals(NearbyRoomStart.Scan, NearbyRoomFlow.guestStart())
    }

    @Test
    fun `Nearby 离房只释放 Nearby 资源且既有房型不变`() {
        assertEquals(RoomCleanup.NEARBY, BluetoothRoomFlow.cleanupFor(RoomKind.NEARBY))
        assertEquals(RoomCleanup.WIFI, BluetoothRoomFlow.cleanupFor(RoomKind.WIFI))
        assertEquals(RoomCleanup.BLUETOOTH, BluetoothRoomFlow.cleanupFor(RoomKind.BLUETOOTH))
    }
}
