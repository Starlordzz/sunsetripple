package com.wt.intercom.transport.bluetooth

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.annotation.RequiresPermission
import com.wt.intercom.transport.TransportLog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Android Bluetooth Classic 设备发现与可发现状态适配器。 */
class BluetoothRoomManager(context: Context) {

    private val appContext = context.applicationContext
    private val adapter =
        (appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private val _bondedDevices = MutableStateFlow<List<BluetoothDevice>>(emptyList())
    val bondedDevices: StateFlow<List<BluetoothDevice>> = _bondedDevices.asStateFlow()

    private val _discoveredDevices = MutableStateFlow<List<BluetoothDevice>>(emptyList())
    val discoveredDevices: StateFlow<List<BluetoothDevice>> = _discoveredDevices.asStateFlow()

    private val _discovering = MutableStateFlow(false)
    val discovering: StateFlow<Boolean> = _discovering.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    @Volatile private var registered = false

    @SuppressLint("MissingPermission")
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> deviceFrom(intent)?.let(::addDiscoveredDevice)
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> deviceFrom(intent)?.let { device ->
                    addDiscoveredDevice(device)
                    refreshBondedDevices()
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> _discovering.value = false
                BluetoothAdapter.ACTION_STATE_CHANGED -> when (
                    intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                ) {
                    BluetoothAdapter.STATE_ON -> {
                        _lastError.value = null
                        refreshBondedDevices()
                    }
                    BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> {
                        _discovering.value = false
                        _bondedDevices.value = emptyList()
                        _discoveredDevices.value = emptyList()
                        _lastError.value = BLUETOOTH_OFF_MESSAGE
                    }
                }
            }
        }
    }

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    @Synchronized
    fun register() {
        if (registered) return
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            appContext.registerReceiver(receiver, filter)
        }
        registered = true
        refreshBondedDevices()
    }

    @SuppressLint("MissingPermission")
    fun discoverDevices() {
        val bluetooth = enabledAdapter() ?: return
        runCatching {
            if (bluetooth.isDiscovering) bluetooth.cancelDiscovery()
            _discoveredDevices.value = emptyList()
            _discovering.value = bluetooth.startDiscovery()
            if (!_discovering.value) _lastError.value = "蓝牙扫描启动失败，请稍后重试"
        }.onFailure(::publishFailure)
    }

    @RequiresPermission(
        allOf = [Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE],
    )
    fun requestDiscoverableIntent(durationSeconds: Int = DISCOVERABLE_SECONDS): Intent? {
        if (enabledAdapter() == null) return null
        require(durationSeconds in 1..DISCOVERABLE_SECONDS) { "可发现时长必须在 1..300 秒" }
        return Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).putExtra(
            BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION,
            durationSeconds,
        )
    }

    @SuppressLint("MissingPermission")
    @Synchronized
    fun close() {
        runCatching { adapter?.takeIf { it.isDiscovering }?.cancelDiscovery() }
            .onFailure { TransportLog.w("取消蓝牙扫描失败: ${it.message}", it) }
        _discovering.value = false
        if (!registered) return
        registered = false
        runCatching { appContext.unregisterReceiver(receiver) }
            .onFailure { TransportLog.w("注销蓝牙广播失败: ${it.message}", it) }
    }

    @SuppressLint("MissingPermission")
    private fun refreshBondedDevices() {
        val bluetooth = enabledAdapter() ?: return
        runCatching {
            _bondedDevices.value = bluetooth.bondedDevices.sortedWith(
                compareBy({ it.name.orEmpty() }, { it.address }),
            )
        }.onFailure(::publishFailure)
    }

    @SuppressLint("MissingPermission")
    private fun enabledAdapter(): BluetoothAdapter? {
        val bluetooth = adapter
        if (bluetooth == null) {
            _lastError.value = "此设备不支持蓝牙"
            return null
        }
        return runCatching { bluetooth.takeIf { it.isEnabled } }
            .onFailure(::publishFailure)
            .getOrNull()
            .also { if (it == null && _lastError.value == null) _lastError.value = BLUETOOTH_OFF_MESSAGE }
    }

    private fun addDiscoveredDevice(device: BluetoothDevice) {
        _discoveredDevices.value = (_discoveredDevices.value + device)
            .distinctBy { it.address }
    }

    private fun publishFailure(error: Throwable) {
        _discovering.value = false
        _lastError.value = when (error) {
            is SecurityException -> "缺少附近设备或蓝牙扫描权限"
            else -> "蓝牙操作失败：${error.message ?: "未知错误"}"
        }
        TransportLog.w(_lastError.value.orEmpty(), error)
    }

    @Suppress("DEPRECATION")
    private fun deviceFrom(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    private companion object {
        const val DISCOVERABLE_SECONDS = 300
        const val BLUETOOTH_OFF_MESSAGE = "蓝牙已关闭，请先开启蓝牙"
    }
}
