package com.wt.intercom.ui

import android.Manifest

/**
 * 进房前置条件：运行时权限集合与系统定位服务开关。
 *
 * 全部按 sdkInt 入参而不是直接读 `Build.VERSION.SDK_INT`——后者在 JVM 单测里恒为 0，
 * 各版本分支就没法验证了。
 */
object RoomPermissions {

    /** 定位服务（系统开关，非权限）关闭时的提示。WiFi Direct 扫描会静默返回空列表。 */
    const val LOCATION_SERVICE_OFF_HINT =
        "需要开启定位服务：系统定位开关关闭时 WiFi 直连扫不到任何设备，请在下拉栏或系统设置里打开「位置」后重试"

    /** 缺这些权限就进不了房。 */
    fun required(sdkInt: Int): List<String> = buildList {
        add(Manifest.permission.RECORD_AUDIO)
        // 33 起用 NEARBY_WIFI_DEVICES（neverForLocation），旧版本只能靠精确定位权限。
        if (sdkInt >= 33) add(Manifest.permission.NEARBY_WIFI_DEVICES)
        else add(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    /**
     * 一次弹窗里申请的全部权限 = [required] + 两个不阻塞进房的附加项。
     *
     * - 粗略定位：Android 12 起单独申请 FINE 会被系统直接忽略（连弹窗都不弹），必须成对申请；
     *   但只有 FINE 满足得了 WiFi Direct 扫描，所以它不进 [required]。
     * - 通知权限：只影响前台服务通知能不能显示，拒了照样能对讲。
     */
    fun requested(sdkInt: Int): List<String> = buildList {
        addAll(required(sdkInt))
        if (sdkInt < 33) add(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (sdkInt >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
    }

    /**
     * 从系统回传结果里挑出"被拒且会挡住进房"的权限。
     * 结果里查不到的键按被拒处理——宁可多提示一次，也不要在没权限的情况下往下走。
     */
    fun blockingDenied(result: Map<String, Boolean>, sdkInt: Int): List<String> =
        required(sdkInt).filter { result[it] != true }

    /** 被拒权限 → 用户看得懂的中文原因。 */
    fun deniedMessage(denied: List<String>): String {
        val names = denied.map {
            when (it) {
                Manifest.permission.RECORD_AUDIO -> "麦克风"
                Manifest.permission.ACCESS_FINE_LOCATION -> "定位（用于 WiFi 直连扫描）"
                Manifest.permission.NEARBY_WIFI_DEVICES -> "附近的设备"
                else -> it
            }
        }
        return "缺少权限：${names.joinToString("、")}，无法进入房间"
    }

    /**
     * 该版本是否还依赖系统定位服务开关。
     *
     * 取 28..32 而不是移交单写的"Android 10~12"：Android 9 起 WiFi 扫描（含 P2P 发现）
     * 就被定位开关卡住了，少判一档的代价是用户对着空列表干等；13 起改用
     * NEARBY_WIFI_DEVICES（neverForLocation），与定位开关脱钩。
     */
    fun needsLocationService(sdkInt: Int): Boolean = sdkInt in 28..32
}
