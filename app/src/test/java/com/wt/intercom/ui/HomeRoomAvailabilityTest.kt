package com.wt.intercom.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class HomeRoomAvailabilityTest {

    @Test
    fun `首页只展示 WiFi 与蓝牙房`() {
        assertEquals(
            setOf(RoomKind.WIFI, RoomKind.BLUETOOTH),
            HomeRoomAvailability.visibleRoomKinds,
        )
    }
}
