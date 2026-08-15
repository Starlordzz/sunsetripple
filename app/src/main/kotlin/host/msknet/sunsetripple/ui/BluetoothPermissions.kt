package host.msknet.sunsetripple.ui

import android.Manifest

enum class BluetoothRoomRole { HOST, GUEST }

object BluetoothPermissions {
    fun required(sdkInt: Int, role: BluetoothRoomRole): List<String> = buildList {
        add(Manifest.permission.RECORD_AUDIO)
        if (sdkInt >= 31) {
            add(Manifest.permission.BLUETOOTH_CONNECT)
            add(
                if (role == BluetoothRoomRole.HOST) Manifest.permission.BLUETOOTH_ADVERTISE
                else Manifest.permission.BLUETOOTH_SCAN,
            )
        } else {
            add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (sdkInt >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
    }

    fun blockingDenied(
        result: Map<String, Boolean>,
        sdkInt: Int,
        role: BluetoothRoomRole,
    ): List<String> = required(sdkInt, role).filter { result[it] != true }

    fun deniedMessage(denied: List<String>): String {
        val names = denied.map { permission ->
            when (permission) {
                Manifest.permission.RECORD_AUDIO -> "麦克风"
                Manifest.permission.BLUETOOTH_CONNECT -> "附近设备"
                Manifest.permission.BLUETOOTH_SCAN -> "蓝牙扫描"
                Manifest.permission.BLUETOOTH_ADVERTISE -> "蓝牙可发现"
                Manifest.permission.ACCESS_FINE_LOCATION -> "定位（用于蓝牙扫描）"
                Manifest.permission.POST_NOTIFICATIONS -> "通知（用于锁屏对讲控制）"
                else -> permission
            }
        }
        return "需要授权：${names.joinToString("、")}"
    }
}
