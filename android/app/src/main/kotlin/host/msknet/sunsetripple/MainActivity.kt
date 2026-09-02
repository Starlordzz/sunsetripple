package host.msknet.sunsetripple

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "SunsetMain"
        private const val REQUEST_CODE_RUNTIME_PERMISSIONS = 4801
    }

    private var audioPlugin: PlatformAudioPlugin? = null
    private var blePlugin: BleL2capPlugin? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioPlugin = PlatformAudioPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        blePlugin = BleL2capPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestRuntimePermissions()
        acquireMulticastLock()
    }

    private fun acquireMulticastLock() {
        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifiManager?.createMulticastLock("SunsetRippleMulticastLock")?.apply {
                setReferenceCounted(true)
                acquire()
            }
            Log.i(TAG, "已成功获取 WiFi MulticastLock 组播锁")
        } catch (e: Exception) {
            Log.w(TAG, "获取 WiFi MulticastLock 失败", e)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        audioPlugin?.dispose()
        audioPlugin = null
        blePlugin?.dispose()
        blePlugin = null
        try {
            multicastLock?.let {
                if (it.isHeld) it.release()
            }
            multicastLock = null
        } catch (e: Exception) {
            Log.w(TAG, "释放 WiFi MulticastLock 失败", e)
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * 麦克风、蓝牙、近场 WiFi 都是运行时权限，缺任何一个对应房型就用不了。
     * 这里一次性申请，具体拒绝后的提示由 Dart 侧收到通道错误后弹出。
     */
    private fun requestRuntimePermissions() {
        val wanted = mutableListOf(Manifest.permission.RECORD_AUDIO)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            wanted += Manifest.permission.BLUETOOTH_CONNECT
            wanted += Manifest.permission.BLUETOOTH_SCAN
            wanted += Manifest.permission.BLUETOOTH_ADVERTISE
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            wanted += Manifest.permission.NEARBY_WIFI_DEVICES
            // 没有通知权限，前台服务的常驻通知不显示，服务本身也更容易被回收。
            wanted += Manifest.permission.POST_NOTIFICATIONS
        } else {
            // Android 12 及以下，扫描 WiFi/蓝牙设备必须有精确位置权限。
            wanted += Manifest.permission.ACCESS_FINE_LOCATION
        }

        val missing = wanted.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isEmpty()) return

        Log.i(TAG, "申请运行时权限：${missing.joinToString()}")
        requestPermissions(missing.toTypedArray(), REQUEST_CODE_RUNTIME_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CODE_RUNTIME_PERMISSIONS) return

        permissions.forEachIndexed { index, permission ->
            val granted = grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                Log.w(TAG, "权限被拒绝：$permission")
            }
        }
    }
}
