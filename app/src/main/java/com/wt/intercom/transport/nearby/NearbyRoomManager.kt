package com.wt.intercom.transport.nearby

import android.content.Context
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class NearbyRoomManager internal constructor(
    private val port: NearbyConnectionsPort,
    private val gmsAvailable: () -> Boolean,
) : NearbyConnectionsListener {

    constructor(context: Context) : this(
        PlayServicesNearbyConnectionsPort(context),
        {
            GoogleApiAvailability.getInstance()
                .isGooglePlayServicesAvailable(context.applicationContext) == ConnectionResult.SUCCESS
        },
    )

    private val endpointMap = linkedMapOf<String, NearbyEndpoint>()
    private val lock = Any()
    private val closed = AtomicBoolean(false)

    private val _endpoints = MutableStateFlow<List<NearbyEndpoint>>(emptyList())
    val endpoints: StateFlow<List<NearbyEndpoint>> = _endpoints.asStateFlow()

    private val _discovering = MutableStateFlow(false)
    val discovering: StateFlow<Boolean> = _discovering.asStateFlow()

    private val _advertising = MutableStateFlow(false)
    val advertising: StateFlow<Boolean> = _advertising.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    init {
        port.setListener(this)
    }

    fun startAdvertising(localName: String) {
        if (!ensureAvailable()) return
        _advertising.value = true
        port.startAdvertising(localName)
    }

    fun startDiscovery() {
        if (!ensureAvailable()) return
        _discovering.value = true
        port.startDiscovery()
    }

    fun requestConnection(localName: String, endpointId: String) {
        if (!ensureAvailable()) return
        updateEndpoint(endpointId) { it.copy(state = NearbyEndpointState.CONNECTING) }
        port.requestConnection(localName, endpointId)
    }

    fun ensureAvailable(): Boolean {
        if (!checkAvailable()) return false
        _lastError.value = null
        return true
    }

    override fun onEndpointFound(endpoint: NearbyEndpoint) {
        if (closed.get()) return
        synchronized(lock) {
            val current = endpointMap[endpoint.id]
            endpointMap[endpoint.id] = endpoint.copy(state = current?.state ?: endpoint.state)
            publishEndpointsLocked()
        }
    }

    override fun onEndpointLost(endpointId: String) {
        if (closed.get()) return
        removeEndpoint(endpointId)
    }

    override fun onConnectionResult(endpointId: String, accepted: Boolean) {
        if (closed.get()) return
        if (accepted) {
            updateEndpoint(endpointId) { it.copy(state = NearbyEndpointState.CONNECTED) }
        } else {
            removeEndpoint(endpointId)
        }
    }

    override fun onDisconnected(endpointId: String) {
        if (closed.get()) return
        removeEndpoint(endpointId)
    }

    override fun onOperationFailed(operation: String, error: Throwable) {
        if (closed.get()) return
        _discovering.value = false
        _advertising.value = false
        _lastError.value = "$operation 失败：${error.message ?: "未知错误"}"
    }

    fun handoffPort(): NearbyConnectionsPort {
        check(closed.compareAndSet(false, true)) { "NearbyRoomManager 已关闭或端口已交接" }
        port.stopAll()
        port.setListener(null)
        clearActiveState()
        return port
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        port.stopAll()
        port.setListener(null)
        clearActiveState()
    }

    private fun clearActiveState() {
        synchronized(lock) {
            endpointMap.clear()
            publishEndpointsLocked()
        }
        _discovering.value = false
        _advertising.value = false
    }

    private fun checkAvailable(): Boolean {
        if (closed.get()) return false
        if (gmsAvailable()) return true
        _discovering.value = false
        _advertising.value = false
        _lastError.value = NO_GMS_MESSAGE
        return false
    }

    private fun updateEndpoint(endpointId: String, transform: (NearbyEndpoint) -> NearbyEndpoint) {
        synchronized(lock) {
            val current = endpointMap[endpointId] ?: return
            endpointMap[endpointId] = transform(current)
            publishEndpointsLocked()
        }
    }

    private fun removeEndpoint(endpointId: String) {
        synchronized(lock) {
            if (endpointMap.remove(endpointId) != null) publishEndpointsLocked()
        }
    }

    private fun publishEndpointsLocked() {
        _endpoints.value = endpointMap.values.toList()
    }

    private companion object {
        const val NO_GMS_MESSAGE = "此设备缺少 Google Play 服务"
    }
}
