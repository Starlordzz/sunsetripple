package com.wt.intercom.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BluetoothPermissionsTest {

    private val record = "android.permission.RECORD_AUDIO"
    private val connect = "android.permission.BLUETOOTH_CONNECT"
    private val scan = "android.permission.BLUETOOTH_SCAN"
    private val advertise = "android.permission.BLUETOOTH_ADVERTISE"
    private val fineLocation = "android.permission.ACCESS_FINE_LOCATION"

    @Test
    fun `SDK31 起建房与加入申请各自所需的附近设备权限`() {
        assertEquals(
            listOf(record, connect, advertise),
            BluetoothPermissions.required(31, BluetoothRoomRole.HOST),
        )
        assertEquals(
            listOf(record, connect, scan),
            BluetoothPermissions.required(35, BluetoothRoomRole.GUEST),
        )
    }

    @Test
    fun `SDK26 到 30 运行时只申请录音与精确定位`() {
        val expected = listOf(record, fineLocation)

        assertEquals(expected, BluetoothPermissions.required(26, BluetoothRoomRole.HOST))
        assertEquals(expected, BluetoothPermissions.required(30, BluetoothRoomRole.GUEST))
    }

    @Test
    fun `缺失权限按角色拦截并给出可操作的中文原因`() {
        val denied = BluetoothPermissions.blockingDenied(
            result = mapOf(record to false, connect to false, scan to false),
            sdkInt = 35,
            role = BluetoothRoomRole.GUEST,
        )

        assertEquals(listOf(record, connect, scan), denied)
        val message = BluetoothPermissions.deniedMessage(denied)
        assertTrue(message.contains("麦克风"))
        assertTrue(message.contains("附近设备"))
        assertTrue(message.contains("蓝牙扫描"))
    }
}
