package host.msknet.sunsetripple

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 蓝牙房的 BLE L2CAP CoC（面向连接通道）实现。
 *
 * 为什么不是经典蓝牙 RFCOMM：L2CAP CoC 在 iOS 侧有 CBL2CAPChannel 对应物、
 * 不需要 MFi，鸿蒙 NEXT 也有原生支持，是三端能共用同一套协议的唯一选择。
 *
 * 关键约束：**PSM 由系统动态分配，不能写死**。房主用
 * `listenUsingInsecureL2capChannel()` 拿到真实 PSM 后，把它放进 BLE 广播的
 * 厂商自定义数据里；客户端扫描时读出来，再用它建立 L2CAP 通道。
 *
 * 广播预算（各 31 字节）：
 *   主包    flags(3) + 128 位服务 UUID(18) = 21
 *   扫描响应 厂商数据 = 1+1+2(公司ID) + 2(PSM) + 1(人数) + 房名 UTF-8(≤24)
 *
 * L2CAP CoC 需要 API 29（Android 10）；低于此版本的设备开不了蓝牙房。
 */
class BleL2capPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "SunsetBle"

        private const val METHOD_CHANNEL = "host.msknet.sunsetripple/ble_l2cap"
        private const val DATA_CHANNEL = "host.msknet.sunsetripple/ble_l2cap_data"
        private const val SCAN_CHANNEL = "host.msknet.sunsetripple/ble_l2cap_scan"

        /** 蓝牙房的服务标识，客户端按它过滤扫描结果。 */
        private val SERVICE_UUID: UUID =
            UUID.fromString("7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004")

        /** 0xFFFF 是蓝牙 SIG 保留给内部/测试用的公司标识。 */
        private const val MANUFACTURER_ID = 0xFFFF

        private const val FRAME_HEADER_SIZE = 6
        private const val MAX_PAYLOAD = 1024

        /** 房主 1 台 + 客户端 5 台。 */
        private const val MAX_PEERS = 5

        /** 扫描响应里留给房名的字节数。 */
        private const val ROOM_NAME_BUDGET = 24
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val dataChannel = EventChannel(messenger, DATA_CHANNEL)
    private val scanChannel = EventChannel(messenger, SCAN_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var dataSink: EventChannel.EventSink? = null
    private var scanSink: EventChannel.EventSink? = null

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    // 房主侧
    private var serverSocket: BluetoothServerSocket? = null
    private var acceptThread: Thread? = null
    private val accepting = AtomicBoolean(false)
    private var advertiseCallback: AdvertiseCallback? = null
    private var advertisedRoomName: String = ""
    private var advertisedPsm: Int = 0
    private var advertisedMemberCount: Int = 1

    // 客户端侧
    private var hostLink: PeerLink? = null

    /** address -> 链路。房主侧是全部客户端，客户端侧只有房主一条。 */
    private val peers = ConcurrentHashMap<String, PeerLink>()

    private var isHost = false
    private var scanning = false

    init {
        methodChannel.setMethodCallHandler(this)
        dataChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                dataSink = events
            }

            override fun onCancel(arguments: Any?) {
                dataSink = null
            }
        })
        scanChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                scanSink = events
            }

            override fun onCancel(arguments: Any?) {
                scanSink = null
            }
        })
    }

    fun dispose() {
        stopEverything()
        methodChannel.setMethodCallHandler(null)
        dataChannel.setStreamHandler(null)
        scanChannel.setStreamHandler(null)
    }

    // --------------------------------------------------------- MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(supportError() == null)

            "startAdvertising" -> {
                val error = supportError()
                if (error != null) {
                    result.error("UNSUPPORTED", error, null)
                    return
                }
                val roomName = call.argument<String>("roomName") ?: "蓝牙房"
                val memberCount = call.argument<Int>("memberCount") ?: 1
                startAdvertising(roomName, memberCount, result)
            }

            "updateMemberCount" -> {
                val count = call.argument<Int>("memberCount") ?: 1
                if (isHost && count != advertisedMemberCount) {
                    advertisedMemberCount = count
                    restartAdvertisingData()
                }
                result.success(true)
            }

            "startScan" -> {
                val error = supportError()
                if (error != null) {
                    result.error("UNSUPPORTED", error, null)
                    return
                }
                result.success(startScan())
            }

            "stopScan" -> {
                stopScan()
                result.success(true)
            }

            "connectL2cap" -> {
                val error = supportError()
                if (error != null) {
                    result.error("UNSUPPORTED", error, null)
                    return
                }
                val address = call.argument<String>("address")
                val psm = call.argument<Int>("psm") ?: 0
                if (address.isNullOrBlank() || psm <= 0) {
                    result.error("BAD_ARGS", "connectL2cap 需要 address 与有效的 psm", null)
                    return
                }
                connectL2cap(address, psm, result)
            }

            "sendL2capData" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null) {
                    result.error("BAD_ARGS", "sendL2capData 缺少 data", null)
                    return
                }
                result.success(sendData(data, excludeAddress = null))
            }

            "stop" -> {
                stopEverything()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    /** 返回 null 表示可用，否则是给用户看的原因。 */
    private fun supportError(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return "蓝牙房需要 Android 10 及以上（L2CAP 通道）"
        }
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            return "本机不支持低功耗蓝牙"
        }
        val a = adapter ?: return "本机没有蓝牙适配器"
        if (!a.isEnabled) return "蓝牙未开启"
        if (!hasBlePermissions()) return "缺少蓝牙权限"
        return null
    }

    private fun hasBlePermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return listOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_ADVERTISE,
        ).all {
            context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    // ------------------------------------------------------------ 房主：广播

    private fun startAdvertising(
        roomName: String,
        memberCount: Int,
        result: MethodChannel.Result,
    ) {
        stopEverything()
        isHost = true
        advertisedRoomName = roomName
        advertisedMemberCount = memberCount

        val a = adapter ?: run {
            result.error("UNSUPPORTED", "没有蓝牙适配器", null)
            return
        }

        val server = try {
            @Suppress("MissingPermission")
            a.listenUsingInsecureL2capChannel()
        } catch (e: Exception) {
            Log.e(TAG, "打开 L2CAP 监听失败", e)
            result.error("L2CAP_LISTEN_FAILED", "无法开启蓝牙通道：${e.message}", null)
            return
        }

        serverSocket = server
        advertisedPsm = server.psm
        Log.i(TAG, "L2CAP 监听已开启，系统分配的 PSM = $advertisedPsm")

        accepting.set(true)
        acceptThread = Thread({ acceptLoop(server) }, "sunset-ble-accept").apply { start() }

        val advertiser = a.bluetoothLeAdvertiser
        if (advertiser == null) {
            stopEverything()
            result.error("UNSUPPORTED", "本机不支持 BLE 广播，无法作为蓝牙房主", null)
            return
        }

        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                Log.i(TAG, "BLE 广播已开启：$advertisedRoomName (PSM=$advertisedPsm)")
                mainHandler.post { result.success(true) }
            }

            override fun onStartFailure(errorCode: Int) {
                Log.e(TAG, "BLE 广播失败，errorCode=$errorCode")
                mainHandler.post {
                    result.error(
                        "ADVERTISE_FAILED",
                        "蓝牙广播开启失败（错误码 $errorCode）",
                        null,
                    )
                }
                stopEverything()
            }
        }
        advertiseCallback = callback

        try {
            @Suppress("MissingPermission")
            advertiser.startAdvertising(
                buildAdvertiseSettings(),
                buildAdvertiseData(),
                buildScanResponse(),
                callback,
            )
        } catch (e: Exception) {
            Log.e(TAG, "startAdvertising 抛异常", e)
            stopEverything()
            result.error("ADVERTISE_FAILED", "蓝牙广播开启失败：${e.message}", null)
        }
    }

    private fun restartAdvertisingData() {
        val advertiser = adapter?.bluetoothLeAdvertiser ?: return
        val callback = advertiseCallback ?: return
        try {
            @Suppress("MissingPermission")
            advertiser.stopAdvertising(callback)
            @Suppress("MissingPermission")
            advertiser.startAdvertising(
                buildAdvertiseSettings(),
                buildAdvertiseData(),
                buildScanResponse(),
                callback,
            )
        } catch (e: Exception) {
            Log.w(TAG, "更新广播内容失败（人数显示可能不准）", e)
        }
    }

    private fun buildAdvertiseSettings(): AdvertiseSettings =
        AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true) // L2CAP 需要先建立 ACL 连接
            .setTimeout(0)
            .build()

    private fun buildAdvertiseData(): AdvertiseData =
        AdvertiseData.Builder()
            .setIncludeDeviceName(false) // 设备名会挤爆 31 字节预算
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

    private fun buildScanResponse(): AdvertiseData {
        val nameBytes = truncateUtf8(advertisedRoomName, ROOM_NAME_BUDGET)
        val payload = ByteArray(3 + nameBytes.size)
        payload[0] = (advertisedPsm ushr 8).toByte()
        payload[1] = advertisedPsm.toByte()
        payload[2] = advertisedMemberCount.toByte()
        nameBytes.copyInto(payload, 3)

        return AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addManufacturerData(MANUFACTURER_ID, payload)
            .build()
    }

    /** 按 UTF-8 字节数截断，且不切断多字节字符（中文房名会踩到）。 */
    private fun truncateUtf8(text: String, maxBytes: Int): ByteArray {
        var candidate = text
        while (candidate.isNotEmpty()) {
            val bytes = candidate.toByteArray(Charsets.UTF_8)
            if (bytes.size <= maxBytes) return bytes
            candidate = candidate.substring(0, candidate.length - 1)
        }
        return ByteArray(0)
    }

    private fun acceptLoop(server: BluetoothServerSocket) {
        while (accepting.get()) {
            val socket = try {
                server.accept()
            } catch (e: IOException) {
                if (accepting.get()) Log.w(TAG, "accept 中断", e)
                break
            }

            if (peers.size >= MAX_PEERS) {
                Log.w(TAG, "蓝牙房已满，拒绝 ${socket.remoteDevice?.address}")
                try {
                    socket.close()
                } catch (_: IOException) {
                }
                continue
            }

            registerPeer(socket)
        }
    }

    // ---------------------------------------------------------- 客户端：扫描

    private fun startScan(): Boolean {
        val scanner = adapter?.bluetoothLeScanner ?: run {
            Log.e(TAG, "拿不到 BLE 扫描器")
            return false
        }
        if (scanning) return true

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        return try {
            @Suppress("MissingPermission")
            scanner.startScan(listOf(filter), settings, scanCallback)
            scanning = true
            Log.i(TAG, "开始扫描蓝牙房")
            true
        } catch (e: Exception) {
            Log.e(TAG, "启动扫描失败", e)
            false
        }
    }

    private fun stopScan() {
        if (!scanning) return
        scanning = false
        try {
            @Suppress("MissingPermission")
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: Exception) {
            Log.w(TAG, "停止扫描失败", e)
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            val record = result?.scanRecord ?: return
            val payload = record.getManufacturerSpecificData(MANUFACTURER_ID) ?: return
            if (payload.size < 3) return

            val psm = ((payload[0].toInt() and 0xFF) shl 8) or (payload[1].toInt() and 0xFF)
            if (psm <= 0) return
            val memberCount = payload[2].toInt() and 0xFF
            val roomName = if (payload.size > 3) {
                String(payload, 3, payload.size - 3, Charsets.UTF_8)
            } else {
                "蓝牙房"
            }

            val device = result.device ?: return
            val info = mapOf(
                "address" to device.address,
                "roomName" to roomName,
                "psm" to psm,
                "memberCount" to memberCount,
                "rssi" to result.rssi,
            )
            mainHandler.post { scanSink?.success(info) }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE 扫描失败，errorCode=$errorCode")
            mainHandler.post {
                scanSink?.error("SCAN_FAILED", "蓝牙扫描失败（错误码 $errorCode）", null)
            }
            scanning = false
        }
    }

    private fun connectL2cap(address: String, psm: Int, result: MethodChannel.Result) {
        val a = adapter ?: run {
            result.error("UNSUPPORTED", "没有蓝牙适配器", null)
            return
        }
        isHost = false
        stopScan()

        // connect() 是阻塞调用，绝不能放在主线程。
        Thread({
            val socket: BluetoothSocket? = try {
                val device = a.getRemoteDevice(address)
                @Suppress("MissingPermission")
                device.createInsecureL2capChannel(psm).apply { connect() }
            } catch (e: Exception) {
                Log.e(TAG, "连接 L2CAP 通道失败（$address PSM=$psm）", e)
                null
            }

            if (socket == null) {
                mainHandler.post {
                    result.error("CONNECT_FAILED", "连接蓝牙房主失败，请靠近后重试", null)
                }
                return@Thread
            }

            hostLink = registerPeer(socket)
            mainHandler.post { result.success(true) }
        }, "sunset-ble-connect").start()
    }

    // ------------------------------------------------------------ 链路与收发

    private inner class PeerLink(val socket: BluetoothSocket, val address: String) {
        val alive = AtomicBoolean(true)
        private val writeLock = Any()

        fun write(data: ByteArray) {
            synchronized(writeLock) {
                if (!alive.get()) return
                socket.outputStream.write(data)
                socket.outputStream.flush()
            }
        }

        fun close() {
            alive.set(false)
            try {
                socket.close()
            } catch (e: IOException) {
                Log.d(TAG, "关闭 $address 时被忽略的异常：$e")
            }
        }
    }

    private fun registerPeer(socket: BluetoothSocket): PeerLink {
        val address = socket.remoteDevice?.address ?: "unknown"
        val link = PeerLink(socket, address)
        peers[address] = link
        Log.i(TAG, "蓝牙链路建立：$address")

        Thread({ readLoop(link) }, "sunset-ble-read-$address").start()
        return link
    }

    /**
     * L2CAP CoC 是流式的，一次 read 可能只拿到半个帧。
     * 这里按 6 字节帧头里的长度字段补齐成整帧再上抛，Dart 侧就只需 Frame.decode。
     */
    private fun readLoop(link: PeerLink) {
        val input = try {
            link.socket.inputStream
        } catch (e: IOException) {
            Log.e(TAG, "拿不到 ${link.address} 的输入流", e)
            removePeer(link)
            return
        }

        val header = ByteArray(FRAME_HEADER_SIZE)

        while (link.alive.get()) {
            if (!readFully(input, header, FRAME_HEADER_SIZE)) break

            val payloadLength =
                ((header[4].toInt() and 0xFF) shl 8) or (header[5].toInt() and 0xFF)
            if (payloadLength > MAX_PAYLOAD) {
                Log.e(TAG, "${link.address} 帧长度 $payloadLength 越界，判定为流错位并断开")
                break
            }

            val full = ByteArray(FRAME_HEADER_SIZE + payloadLength)
            header.copyInto(full, 0)
            if (payloadLength > 0) {
                val payload = ByteArray(payloadLength)
                if (!readFully(input, payload, payloadLength)) break
                payload.copyInto(full, FRAME_HEADER_SIZE)
            }

            // 房主负责把一个成员的帧转给其他成员（星型拓扑，与 WiFi 房一致）。
            if (isHost) sendData(full, excludeAddress = link.address)

            val event = mapOf<String, Any>(
                "data" to full,
                "peerAddress" to link.address,
            )
            mainHandler.post { dataSink?.success(event) }
        }

        Log.i(TAG, "蓝牙链路断开：${link.address}")
        removePeer(link)
    }

    private fun readFully(input: java.io.InputStream, dst: ByteArray, length: Int): Boolean {
        var offset = 0
        while (offset < length) {
            val read = try {
                input.read(dst, offset, length - offset)
            } catch (e: IOException) {
                return false
            }
            if (read < 0) return false
            offset += read
        }
        return true
    }

    private fun sendData(data: ByteArray, excludeAddress: String?): Boolean {
        if (peers.isEmpty()) return false
        var anySent = false

        for ((address, link) in peers) {
            if (address == excludeAddress) continue
            if (!link.alive.get()) continue
            try {
                link.write(data)
                anySent = true
            } catch (e: IOException) {
                Log.w(TAG, "向 $address 发送失败，断开该链路", e)
                removePeer(link)
            }
        }
        return anySent
    }

    private fun removePeer(link: PeerLink) {
        peers.remove(link.address)
        link.close()
        if (hostLink === link) hostLink = null
    }

    // ---------------------------------------------------------------- 收尾

    private fun stopEverything() {
        stopScan()

        accepting.set(false)
        advertiseCallback?.let { callback ->
            try {
                @Suppress("MissingPermission")
                adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
            } catch (e: Exception) {
                Log.d(TAG, "停止广播时被忽略的异常：$e")
            }
        }
        advertiseCallback = null

        try {
            serverSocket?.close()
        } catch (e: IOException) {
            Log.d(TAG, "关闭 L2CAP 监听时被忽略的异常：$e")
        }
        serverSocket = null
        acceptThread = null

        for (link in peers.values) link.close()
        peers.clear()
        hostLink = null

        isHost = false
        advertisedPsm = 0
    }
}
