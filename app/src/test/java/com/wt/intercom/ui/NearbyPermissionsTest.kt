package com.wt.intercom.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NearbyPermissionsTest {

    private val record = "android.permission.RECORD_AUDIO"
    private val fineLocation = "android.permission.ACCESS_FINE_LOCATION"
    private val scan = "android.permission.BLUETOOTH_SCAN"
    private val connect = "android.permission.BLUETOOTH_CONNECT"
    private val nearbyWifi = "android.permission.NEARBY_WIFI_DEVICES"

    @Test
    fun `Nearby 权限按 Android 版本分三段`() {
        assertEquals(listOf(record, fineLocation), NearbyPermissions.required(26))
        assertEquals(
            listOf(record, scan, connect, fineLocation),
            NearbyPermissions.required(31),
        )
        assertEquals(
            listOf(record, scan, connect, nearbyWifi),
            NearbyPermissions.required(33),
        )
    }

    @Test
    fun `权限拒绝文案点名麦克风附近设备和定位扫描`() {
        val denied = NearbyPermissions.blockingDenied(emptyMap(), 31)
        val message = NearbyPermissions.deniedMessage(denied)

        assertTrue(message.contains("麦克风"))
        assertTrue(message.contains("附近设备"))
        assertTrue(message.contains("定位"))
        assertTrue(message.contains("扫描"))
    }
}
