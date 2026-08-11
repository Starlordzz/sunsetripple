package com.wt.intercom.transport.wifi

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
import com.wt.intercom.transport.TransportLog
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * WifiP2pManager 封装：建组（成为 GO）、发现、连接，以状态流暴露对端与连接信息。
 *
 * 权限（ACCESS_FINE_LOCATION / NEARBY_WIFI_DEVICES）由调用方在进入扫描/建房前申请，
 * 本类的 @SuppressLint("MissingPermission") 仅表示"此处不重复检查"。
 */
class WifiDirectManager(private val context: Context) {

    val peers = MutableStateFlow<List<WifiP2pDevice>>(emptyList())
    val connection = MutableStateFlow<WifiP2pInfo?>(null)
    val lastError = MutableStateFlow<String?>(null)

    private val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
    private val channel = manager.initialize(context, context.mainLooper, null)

    /** register/unregister 幂等：重复注册同一 receiver 会导致 unregister 后仍有回调残留。 */
    @Volatile private var registered = false

    @SuppressLint("MissingPermission")
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION ->
                    manager.requestPeers(channel) { list -> peers.value = list.deviceList.toList() }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION ->
                    manager.requestConnectionInfo(channel) { info -> connection.value = info }
            }
        }
    }

    fun register() {
        if (registered) return
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        }
        // P2P 广播是系统发出的受保护广播；Android 13+ 要求显式声明导出属性，否则注册被拒。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
        registered = true
    }

    fun unregister() {
        if (!registered) return
        registered = false
        runCatching { context.unregisterReceiver(receiver) }
            .onFailure { TransportLog.w("注销 WiFi Direct 广播失败: ${it.message}", it) }
    }

    private fun actionListener(what: String) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() = Unit
        override fun onFailure(reason: Int) {
            lastError.value = "$what 失败（code=$reason）"
            TransportLog.w("WiFi Direct $what 失败（code=$reason）")
        }
    }

    /** 建 WiFi Direct 组并成为组主。先清掉可能残留的旧组，成功与否都继续建组。 */
    @SuppressLint("MissingPermission")
    fun createGroup() {
        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = manager.createGroup(channel, actionListener("建房"))
            override fun onFailure(reason: Int) = manager.createGroup(channel, actionListener("建房"))
        })
    }

    @SuppressLint("MissingPermission")
    fun discoverPeers() {
        peers.value = emptyList()
        manager.discoverPeers(channel, actionListener("扫描"))
    }

    @SuppressLint("MissingPermission")
    fun connect(device: WifiP2pDevice) {
        val config = WifiP2pConfig().apply { deviceAddress = device.deviceAddress }
        manager.connect(channel, config, actionListener("连接"))
    }

    fun disconnect() {
        manager.removeGroup(channel, null)
        connection.value = null
        peers.value = emptyList()
    }
}
