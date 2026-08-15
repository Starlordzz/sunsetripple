package host.msknet.sunsetripple.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 进房前置条件（权限集合 + 定位服务开关）的纯逻辑。
 * 断言用权限字符串字面量而不是 Manifest 常量，免得测试跟着实现一起写错。
 */
class RoomPermissionsTest {

    private val record = "android.permission.RECORD_AUDIO"
    private val fineLocation = "android.permission.ACCESS_FINE_LOCATION"
    private val coarseLocation = "android.permission.ACCESS_COARSE_LOCATION"
    private val nearbyWifi = "android.permission.NEARBY_WIFI_DEVICES"
    private val postNotifications = "android.permission.POST_NOTIFICATIONS"

    @Test
    fun `SDK32 及以下要录音与精确定位`() {
        assertEquals(listOf(record, fineLocation), RoomPermissions.required(32))
        assertEquals(listOf(record, fineLocation), RoomPermissions.required(26))
    }

    @Test
    fun `SDK33 起改用附近设备权限`() {
        assertEquals(listOf(record, nearbyWifi, postNotifications), RoomPermissions.required(33))
        assertEquals(listOf(record, nearbyWifi, postNotifications), RoomPermissions.required(35))
    }

    @Test
    fun `SDK33 起通知权限是锁屏控制的进房前提`() {
        assertTrue(RoomPermissions.requested(33).contains(postNotifications))
        assertTrue(RoomPermissions.required(33).contains(postNotifications))
        assertFalse(RoomPermissions.requested(32).contains(postNotifications))
    }

    @Test
    fun `申请精确定位时必须同时申请粗略定位`() {
        // Android 12 起单独申请 FINE 会被系统直接忽略（弹窗都不弹），必须成对申请。
        assertTrue(RoomPermissions.requested(31).contains(coarseLocation))
        assertTrue(RoomPermissions.requested(32).containsAll(listOf(fineLocation, coarseLocation)))
        // 但只有 FINE 能满足 WiFi Direct 扫描，所以粗略定位不进"必须"集合。
        assertFalse(RoomPermissions.required(32).contains(coarseLocation))
        assertFalse(RoomPermissions.requested(33).contains(coarseLocation))
    }

    @Test
    fun `只给了粗略定位仍然拦截进房`() {
        val denied = RoomPermissions.blockingDenied(
            mapOf(record to true, fineLocation to false, coarseLocation to true),
            30,
        )
        assertEquals(listOf(fineLocation), denied)
    }

    @Test
    fun `通知权限被拒会拦截进房`() {
        val result = mapOf(record to true, nearbyWifi to true, postNotifications to false)
        assertEquals(listOf(postNotifications), RoomPermissions.blockingDenied(result, 33))
    }

    @Test
    fun `录音被拒时拦截并给出中文原因`() {
        val denied = RoomPermissions.blockingDenied(
            mapOf(record to false, nearbyWifi to true, postNotifications to true),
            33,
        )
        assertEquals(listOf(record), denied)
        assertTrue(RoomPermissions.deniedMessage(denied).contains("麦克风"))
    }

    @Test
    fun `定位被拒时提示定位权限`() {
        val denied = RoomPermissions.blockingDenied(mapOf(record to true, fineLocation to false), 30)
        assertEquals(listOf(fineLocation), denied)
        assertTrue(RoomPermissions.deniedMessage(denied).contains("定位"))
    }

    @Test
    fun `结果里没回传的权限一律按被拒处理`() {
        assertEquals(
            listOf(record, nearbyWifi, postNotifications),
            RoomPermissions.blockingDenied(emptyMap(), 33),
        )
    }

    @Test
    fun `Android 9 到 12 依赖系统定位服务开关`() {
        assertTrue(RoomPermissions.needsLocationService(28))
        assertTrue(RoomPermissions.needsLocationService(29))
        assertTrue(RoomPermissions.needsLocationService(31))
        assertTrue(RoomPermissions.needsLocationService(32))
    }

    @Test
    fun `Android 13 起不再依赖定位服务开关`() {
        assertFalse(RoomPermissions.needsLocationService(33))
        assertFalse(RoomPermissions.needsLocationService(35))
    }

    @Test
    fun `Android 8 不受定位服务开关限制`() {
        assertFalse(RoomPermissions.needsLocationService(26))
        assertFalse(RoomPermissions.needsLocationService(27))
    }

    @Test
    fun `定位服务关闭的提示必须明说要开定位服务`() {
        assertTrue(RoomPermissions.LOCATION_SERVICE_OFF_HINT.contains("定位服务"))
    }
}
