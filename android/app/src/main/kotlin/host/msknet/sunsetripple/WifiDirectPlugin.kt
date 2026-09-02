package host.msknet.sunsetripple

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android Wi-Fi Direct (Wi-Fi P2P) 原生插件。
 *
 * 支撑无路由器、无外部热点情况下的近场 P2P 局域网建立。
 * Group Owner (GO) 默认拥有 IP 192.168.49.1，
 * 建立链路后上层直接复用 LanTransport (TCP 8988 + UDP 8989)。
 */
class WifiDirectPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "SunsetWifiP2p"
        private const val METHOD_CHANNEL = "host.msknet.sunsetripple/wifi_direct"
        private const val EVENT_CHANNEL = "host.msknet.sunsetripple/wifi_direct_events"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null

    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private var isP2pEnabled = false

    private val peers = mutableListOf<WifiP2pDevice>()
    private var currentConnectionInfo: WifiP2pInfo? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        initWifiP2p()
    }

    private fun initWifiP2p() {
        try {
            manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            Log.i(TAG, "获取 WifiP2pManager: $manager")
            if (manager == null) {
                Log.e(TAG, "系统不支持 WIFI_P2P_SERVICE")
                return
            }
            channel = manager?.initialize(context, Looper.getMainLooper()) {
                Log.w(TAG, "Wi-Fi Direct Channel 已断开，尝试重新初始化")
                channel = manager?.initialize(context, Looper.getMainLooper(), null)
            }
            Log.i(TAG, "初始化 Channel 结果: $channel")
            registerReceiver()
            Log.i(TAG, "Wi-Fi Direct 初始化成功")
        } catch (e: Exception) {
            Log.e(TAG, "Wi-Fi Direct 初始化失败", e)
        }
    }

    private fun registerReceiver() {
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                when (intent?.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                        isP2pEnabled = (state == WifiP2pManager.WIFI_P2P_STATE_ENABLED)
                        Log.i(TAG, "P2P 状态改变: isEnabled=$isP2pEnabled")
                    }

                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                        Log.i(TAG, "收到系统 WIFI_P2P_PEERS_CHANGED_ACTION 广播，开始请求对端列表")
                        manager?.requestPeers(channel) { peerList: WifiP2pDeviceList? ->
                            peers.clear()
                            peerList?.deviceList?.let { peers.addAll(it) }
                            Log.i(TAG, "已发现 ${peers.size} 个 Wi-Fi Direct 对端设备")
                            for (p in peers) {
                                Log.i(TAG, "  -> 对端: ${p.deviceName} (${p.deviceAddress}), status=${p.status}, isGO=${p.isGroupOwner}")
                            }
                            sendPeersEvent()
                        }
                    }

                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        manager?.requestConnectionInfo(channel) { info ->
                            currentConnectionInfo = info
                            val isConnected = info != null && info.groupFormed
                            Log.i(TAG, "Wi-Fi Direct 连接状态变更: groupFormed=${info?.groupFormed}, isGO=${info?.isGroupOwner}, hostIp=${info?.groupOwnerAddress?.hostAddress}")
                            sendConnectionEvent(isConnected = isConnected, info = info)
                        }
                    }

                    WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                        val thisDevice = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE, WifiP2pDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                        }
                        Log.i(TAG, "本机 P2P 设备信息: ${thisDevice?.deviceName} (${thisDevice?.deviceAddress}), status=${thisDevice?.status}")
                    }

                    WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION -> {
                        val discoveryState = intent.getIntExtra(WifiP2pManager.EXTRA_DISCOVERY_STATE, -1)
                        val isStarted = (discoveryState == WifiP2pManager.WIFI_P2P_DISCOVERY_STARTED)
                        Log.i(TAG, "Wi-Fi Direct 发现模式改变: started=$isStarted")
                    }
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            context.registerReceiver(receiver, intentFilter, Context.RECEIVER_EXPORTED)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, intentFilter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, intentFilter)
        }
    }

    private fun sendPeersEvent() {
        val peerData = peers.map { device ->
            mapOf(
                "name" to (device.deviceName ?: "未知设备"),
                "address" to (device.deviceAddress ?: ""),
                "status" to device.status,
                "isGroupOwner" to device.isGroupOwner,
            )
        }
        eventSink?.success(
            mapOf(
                "type" to "peers",
                "peers" to peerData,
            )
        )
    }

    private fun sendConnectionEvent(isConnected: Boolean, info: WifiP2pInfo?) {
        val data = mapOf(
            "type" to "connection",
            "isConnected" to isConnected,
            "isGroupOwner" to (info?.isGroupOwner ?: false),
            "groupFormed" to (info?.groupFormed ?: false),
            "groupOwnerAddress" to (info?.groupOwnerAddress?.hostAddress ?: ""),
        )
        eventSink?.success(data)
    }

    private fun createGroupInternal(result: MethodChannel.Result) {
        manager?.createGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.i(TAG, "创建 Wi-Fi Direct 群组成功 (Group Owner)")
                manager?.discoverPeers(channel, null)
                result.success(true)
            }

            override fun onFailure(reason: Int) {
                Log.w(TAG, "创建 Wi-Fi Direct 群组失败: $reason")
                if (reason == WifiP2pManager.BUSY) {
                    android.os.Handler(Looper.getMainLooper()).postDelayed({
                        manager?.createGroup(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.i(TAG, "重试创建 Wi-Fi Direct 群组成功")
                                manager?.discoverPeers(channel, null)
                            }
                            override fun onFailure(r: Int) {
                                Log.w(TAG, "重试创建群组失败: $r")
                            }
                        })
                    }, 300)
                }
                result.success(false)
            }
        }) ?: result.success(false)
    }

    // MARK: - MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                result.success(manager != null && channel != null)
            }

            "isEnabled" -> {
                result.success(isP2pEnabled)
            }

            "createGroup" -> {
                Log.i(TAG, "收到 Flutter createGroup 请求, manager=$manager, channel=$channel")
                manager?.removeGroup(channel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        createGroupInternal(result)
                    }

                    override fun onFailure(reason: Int) {
                        createGroupInternal(result)
                    }
                }) ?: createGroupInternal(result)
            }

            "removeGroup" -> {
                Log.i(TAG, "收到 Flutter removeGroup 请求")
                manager?.removeGroup(channel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.i(TAG, "解散 Wi-Fi Direct 群组成功")
                        result.success(true)
                    }

                    override fun onFailure(reason: Int) {
                        Log.w(TAG, "解散 Wi-Fi Direct 群组失败: $reason")
                        result.success(false)
                    }
                }) ?: result.success(false)
            }

            "discoverPeers" -> {
                Log.i(TAG, "收到 Flutter discoverPeers 请求, manager=$manager, channel=$channel")
                manager?.discoverPeers(channel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.i(TAG, "开始搜索 Wi-Fi Direct 对端成功")
                        result.success(true)
                    }

                    override fun onFailure(reason: Int) {
                        Log.w(TAG, "搜索 Wi-Fi Direct 对端失败: $reason")
                        if (reason == WifiP2pManager.BUSY) {
                            manager?.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
                                override fun onSuccess() {
                                    manager?.discoverPeers(channel, null)
                                }
                                override fun onFailure(r: Int) {}
                            })
                        }
                        result.success(false)
                    }
                }) ?: run {
                    Log.e(TAG, "discoverPeers 失败：manager 或 channel 为空")
                    result.success(false)
                }
            }

            "connect" -> {
                val address = call.argument<String>("deviceAddress")
                if (address == null) {
                    result.error("INVALID_ARGS", "缺少 deviceAddress 参数", null)
                    return
                }

                val config = WifiP2pConfig().apply {
                    deviceAddress = address
                    groupOwnerIntent = 0
                }

                manager?.connect(channel, config, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.i(TAG, "发起到 $address 的 Wi-Fi Direct 连接请求")
                        result.success(true)
                    }

                    override fun onFailure(reason: Int) {
                        Log.w(TAG, "发起到 $address 的 Wi-Fi Direct 连接失败: $reason")
                        result.success(false)
                    }
                }) ?: result.success(false)
            }

            "disconnect" -> {
                manager?.cancelConnect(channel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        result.success(true)
                    }

                    override fun onFailure(reason: Int) {
                        result.success(false)
                    }
                }) ?: result.success(false)
            }

            "getConnectionInfo" -> {
                val info = currentConnectionInfo
                result.success(
                    mapOf(
                        "isConnected" to (info != null && info.groupFormed),
                        "isGroupOwner" to (info?.isGroupOwner ?: false),
                        "groupOwnerAddress" to (info?.groupOwnerAddress?.hostAddress ?: ""),
                    )
                )
            }

            else -> result.notImplemented()
        }
    }

    // MARK: - EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    fun dispose() {
        try {
            receiver?.let { context.unregisterReceiver(it) }
            receiver = null
            methodChannel.setMethodCallHandler(null)
            eventChannel.setStreamHandler(null)
        } catch (e: Exception) {
            Log.w(TAG, "释放 Wi-Fi Direct 插件失败", e)
        }
    }
}
