package com.wt.intercom.ui

import android.Manifest

object NearbyPermissions {
    fun required(sdkInt: Int): List<String> = buildList {
        add(Manifest.permission.RECORD_AUDIO)
        when {
            sdkInt >= 33 -> {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
                add(Manifest.permission.NEARBY_WIFI_DEVICES)
            }
            sdkInt >= 31 -> {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
                add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
            else -> add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    fun blockingDenied(result: Map<String, Boolean>, sdkInt: Int): List<String> =
        required(sdkInt).filter { result[it] != true }

    fun deniedMessage(denied: List<String>): String {
        val names = denied.map { permission ->
            when (permission) {
                Manifest.permission.RECORD_AUDIO -> "麦克风"
                Manifest.permission.BLUETOOTH_SCAN -> "附近设备蓝牙扫描"
                Manifest.permission.BLUETOOTH_CONNECT -> "附近设备连接"
                Manifest.permission.NEARBY_WIFI_DEVICES -> "附近设备 WiFi 扫描"
                Manifest.permission.ACCESS_FINE_LOCATION -> "定位（用于附近设备扫描）"
                else -> permission
            }
        }
        return "需要授权：${names.joinToString("、")}"
    }
}
