package host.msknet.sunsetripple.transport.wifi

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import host.msknet.sunsetripple.transport.TransportLog
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * WifiP2pManager 封装：建组（成为 GO）、发现、连接，以状态流暴露对端与连接信息。
 *
 * 权限（ACCESS_FINE_LOCATION / NEARBY_WIFI_DEVICES）由调用方在进入扫描/建房前申请，
 * 本类的 @SuppressLint("MissingPermission") 仅表示"此处不重复检查"。
 */
class WifiDirectManager(context: Context) {

    /** 只留 applicationContext：本类活到进程级（广播注册横跨 Activity 重建），持 Activity 会泄漏。 */
    private val appContext = context.applicationContext

    val peers = MutableStateFlow<List<WifiP2pDevice>>(emptyList())
    val connection = MutableStateFlow<WifiP2pInfo?>(null)
    val thisDevice = MutableStateFlow<WifiP2pDevice?>(null)
    val lastError = MutableStateFlow<String?>(null)

    /**
     * 系统的 P2P 发现是否正在进行。
     *
     * 必须以系统广播为准而不是"调用过 discoverPeers 就算在扫"：框架的发现窗口有限，
     * 到点自行停止且不通知调用方，搜房页据此才能把按钮从"正在扫描"放回"重新扫描"。
     */
    val discovering = MutableStateFlow(false)

    /**
     * 框架侧 P2P channel 已断开（WiFi 被关、系统 P2P 服务重启等）。
     *
     * 这是组主侧仅有的两个房间死亡信号之一（另一个是组解散的连接广播）：主机的传输层
     * 没有任何 onDisconnected 路径，不靠它驱动停机，房主会对着一个已不存在的房间继续说话。
     */
    val channelLost = MutableStateFlow(false)

    private val manager = appContext.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager

    /** channel 断开后必须重开一条才能继续用，故为 var。 */
    @Volatile private var channel: WifiP2pManager.Channel = openChannel()

    private fun openChannel(): WifiP2pManager.Channel =
        manager.initialize(appContext, appContext.mainLooper) {
            TransportLog.w("WiFi P2P channel 已断开")
            channelLost.value = true
            connection.value = null
            peers.value = emptyList()
            discovering.value = false
        }

    /**
     * channel 断过就重开一条并清标志，没断过是空操作。
     * 建房/扫描前都会调用——断开后的旧 channel 上所有请求都会静默失败。
     */
    fun ensureChannel() {
        if (!channelLost.value) return
        channel = openChannel()
        channelLost.value = false
        TransportLog.w("WiFi P2P channel 已重建")
    }

    /** register/unregister 幂等：重复注册同一 receiver 会导致 unregister 后仍有回调残留。 */
    @Volatile private var registered = false

    private fun p2pReasonText(reason: Int): String = when (reason) {
        WifiP2pManager.ERROR -> "系统错误 (ERROR=0)"
        WifiP2pManager.P2P_UNSUPPORTED -> "设备不支持 WiFi Direct (P2P_UNSUPPORTED=1)"
        WifiP2pManager.BUSY -> "系统繁忙 (BUSY=2)"
        WifiP2pManager.NO_SERVICE_REQUESTS -> "无可用服务请求 (NO_SERVICE_REQUESTS=3)"
        else -> "code=$reason"
    }

    @SuppressLint("MissingPermission")
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION ->
                    manager.requestPeers(channel) { list ->
                        val peerList = list.deviceList.toList()
                        peers.value = peerList
                        TransportLog.w("WiFi Direct 对端列表变更: 发现 ${peerList.size} 台设备 [${peerList.joinToString { "${it.deviceName}(${it.deviceAddress}, status=${it.status})" }}]")
                    }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION ->
                    manager.requestConnectionInfo(channel) { info ->
                        connection.value = info
                        TransportLog.w("WiFi Direct 连接状态变更: groupFormed=${info?.groupFormed}, isGroupOwner=${info?.isGroupOwner}, hostIp=${info?.groupOwnerAddress?.hostAddress}")
                    }
                WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION ->
                    discovering.value = intent.getIntExtra(
                        WifiP2pManager.EXTRA_DISCOVERY_STATE,
                        WifiP2pManager.WIFI_P2P_DISCOVERY_STOPPED,
                    ) == WifiP2pManager.WIFI_P2P_DISCOVERY_STARTED
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    thisDevice.value = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(
                            WifiP2pManager.EXTRA_WIFI_P2P_DEVICE,
                            WifiP2pDevice::class.java,
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                    }
                }
            }
        }
    }

    fun register() {
        if (registered) return
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        // P2P 广播是系统发出的受保护广播；Android 13+ 要求显式声明导出属性，否则注册被拒。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            appContext.registerReceiver(receiver, filter)
        }
        registered = true
    }

    fun unregister() {
        if (!registered) return
        registered = false
        // 广播一停就再也收不到发现结束的通知，留着 true 会让搜房页永远卡在"正在扫描"。
        discovering.value = false
        runCatching { appContext.unregisterReceiver(receiver) }
            .onFailure { TransportLog.w("注销 WiFi Direct 广播失败: ${it.message}", it) }
    }

    private fun actionListener(what: String) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() = Unit
        override fun onFailure(reason: Int) {
            val reasonText = p2pReasonText(reason)
            lastError.value = "$what 失败（$reasonText）"
            TransportLog.w("WiFi Direct $what 失败（$reasonText）")
        }
    }

    /** 建 WiFi Direct 组并成为组主。建组成功后启动对等发现，使组主在社交信道上对其他扫描设备保持可见。 */
    @SuppressLint("MissingPermission")
    fun createGroup() {
        ensureChannel()
        removeGroupThen {
            manager.createGroup(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    TransportLog.w("WiFi Direct 建房成功（已成为 Group Owner）")
                    startHostDiscovery()
                }

                override fun onFailure(reason: Int) {
                    val reasonText = p2pReasonText(reason)
                    lastError.value = "建房 失败（$reasonText）"
                    TransportLog.w("WiFi Direct 建房失败（$reasonText）")
                }
            })
        }
    }

    /**
     * 房主启动对等发现以保持可被搜索。
     *
     * 部分设备（如华为/鸿蒙与定制 ROM）要求组主（GO）必须同时处于 discoverPeers 发现态，
     * 射频芯片才会持续监听社交信道（1/6/11）并应答扫描端的 Probe Request。
     */
    @SuppressLint("MissingPermission")
    fun startHostDiscovery() {
        ensureChannel()
        manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                TransportLog.w("WiFi Direct 房主发现广播已启动（保持可被对端搜寻）")
            }

            override fun onFailure(reason: Int) {
                TransportLog.w("WiFi Direct 房主启动发现失败（${p2pReasonText(reason)}，非致命）")
            }
        })
    }

    @SuppressLint("MissingPermission")
    fun discoverPeers() {
        ensureChannel()
        peers.value = emptyList()
        lastError.value = null
        // 乐观置位：发现广播要晚一拍才到，中间这段空窗不能让按钮看起来没反应。
        // 真实状态随后由 WIFI_P2P_DISCOVERY_CHANGED_ACTION 纠正，失败则立刻回落。
        discovering.value = true
        manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = Unit
            override fun onFailure(reason: Int) {
                discovering.value = false
                val reasonText = p2pReasonText(reason)
                lastError.value = "扫描 失败（$reasonText）"
                TransportLog.w("WiFi Direct 扫描失败（$reasonText）")
            }
        })
    }

    @SuppressLint("MissingPermission")
    fun connect(device: WifiP2pDevice) {
        connect(device.deviceAddress)
    }

    @SuppressLint("MissingPermission")
    fun connect(deviceAddress: String) {
        ensureChannel()
        val config = WifiP2pConfig().apply { this.deviceAddress = deviceAddress }
        manager.connect(channel, config, actionListener("连接"))
    }

    /**
     * 解散/退出当前组。失败只记日志不写 [lastError]：本来就没有组时 removeGroup 必然失败（BUSY/ERROR），
     * 把它当错误显示的话，每次正常离房首页都会挂一条红字。顺手清掉上一轮的错误提示。
     */
    fun disconnect() {
        removeGroupThen()
    }

    /** 房主交接的普通成员：旧组真正移除后才开始扫描，避免并发 P2P 操作返回 BUSY。 */
    fun disconnectAndDiscoverPeers() {
        removeGroupThen(::discoverPeers)
    }

    private fun removeGroupThen(after: () -> Unit = {}) {
        connection.value = null
        peers.value = emptyList()
        lastError.value = null
        runCatching {
            manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    TransportLog.w("WiFi Direct 组已解散")
                    after()
                }

                override fun onFailure(reason: Int) {
                    TransportLog.w("WiFi Direct 解散组失败（code=$reason，无组时属正常）")
                    after()
                }
            })
        }.onFailure {
            // ChannelListener 可能刚把旧 channel 标成失效；状态清理仍须完成，不能让离房崩溃。
            TransportLog.w("WiFi Direct 解散组调用失败（可能是 channel 已断开）: ${it.message}", it)
            after()
        }
    }
}
