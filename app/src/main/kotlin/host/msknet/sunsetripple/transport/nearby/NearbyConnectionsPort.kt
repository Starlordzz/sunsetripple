package host.msknet.sunsetripple.transport.nearby

import android.content.Context
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy

interface NearbyConnectionsListener {
    fun onEndpointFound(endpoint: NearbyEndpoint) = Unit
    fun onEndpointLost(endpointId: String) = Unit
    fun onConnectionInitiated(endpoint: NearbyEndpoint) = Unit
    fun onConnectionResult(endpointId: String, result: NearbyConnectionResult) = Unit
    fun onConnectionRequestFailed(endpointId: String, error: Throwable) = Unit
    fun onDisconnected(endpointId: String) = Unit
    fun onBytesReceived(endpointId: String, bytes: ByteArray) = Unit
    fun onOperationFailed(operation: String, error: Throwable) = Unit
}

data class NearbyConnectionResult(
    val accepted: Boolean,
    val statusCode: Int? = null,
    val statusMessage: String? = null,
) {
    fun failureReason(): String {
        if (accepted) return ""
        return when {
            statusCode != null && !statusMessage.isNullOrBlank() ->
                "Nearby 连接失败（$statusCode）：$statusMessage"
            statusCode != null -> "Nearby 连接失败（$statusCode）"
            !statusMessage.isNullOrBlank() -> "Nearby 连接失败：$statusMessage"
            else -> "Nearby 连接失败"
        }
    }

    companion object {
        val ACCEPTED = NearbyConnectionResult(accepted = true)

        fun rejected(statusCode: Int?, statusMessage: String?): NearbyConnectionResult =
            NearbyConnectionResult(false, statusCode, statusMessage)
    }
}

interface NearbyConnectionsPort {
    fun setListener(listener: NearbyConnectionsListener?)
    fun startAdvertising(localName: String)
    fun startDiscovery()
    fun requestConnection(localName: String, endpointId: String)
    fun acceptConnection(endpointId: String)
    fun rejectConnection(endpointId: String)
    fun sendBytes(endpointIds: List<String>, bytes: ByteArray)
    fun disconnect(endpointId: String)
    fun stopAll()
}

class PlayServicesNearbyConnectionsPort(context: Context) : NearbyConnectionsPort {
    private val client = Nearby.getConnectionsClient(context.applicationContext)
    @Volatile private var listener: NearbyConnectionsListener? = null

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            if (payload.type == Payload.Type.BYTES) {
                payload.asBytes()?.let { listener?.onBytesReceived(endpointId, it) }
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) = Unit
    }

    private val connectionCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            listener?.onConnectionInitiated(NearbyEndpoint(endpointId, info.endpointName))
        }

        override fun onConnectionResult(endpointId: String, resolution: ConnectionResolution) {
            val status = resolution.status
            listener?.onConnectionResult(
                endpointId,
                if (status.isSuccess) {
                    NearbyConnectionResult.ACCEPTED
                } else {
                    NearbyConnectionResult.rejected(status.statusCode, status.statusMessage)
                },
            )
        }

        override fun onDisconnected(endpointId: String) {
            listener?.onDisconnected(endpointId)
        }
    }

    private val discoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            listener?.onEndpointFound(NearbyEndpoint(endpointId, info.endpointName))
        }

        override fun onEndpointLost(endpointId: String) {
            listener?.onEndpointLost(endpointId)
        }
    }

    override fun setListener(listener: NearbyConnectionsListener?) {
        this.listener = listener
    }

    override fun startAdvertising(localName: String) {
        val operationListener = listener
        client.startAdvertising(localName, SERVICE_ID, connectionCallback, ADVERTISING_OPTIONS)
            .addOnFailureListener { operationListener?.onOperationFailed("Nearby 建房", it) }
    }

    override fun startDiscovery() {
        val operationListener = listener
        client.startDiscovery(SERVICE_ID, discoveryCallback, DISCOVERY_OPTIONS)
            .addOnFailureListener { operationListener?.onOperationFailed("Nearby 扫描", it) }
    }

    override fun requestConnection(localName: String, endpointId: String) {
        val operationListener = listener
        client.requestConnection(localName, endpointId, connectionCallback)
            .addOnFailureListener { operationListener?.onConnectionRequestFailed(endpointId, it) }
    }

    override fun acceptConnection(endpointId: String) {
        val operationListener = listener
        client.acceptConnection(endpointId, payloadCallback)
            .addOnFailureListener { operationListener?.onOperationFailed("Nearby 接受连接", it) }
    }

    override fun rejectConnection(endpointId: String) {
        val operationListener = listener
        client.rejectConnection(endpointId)
            .addOnFailureListener { operationListener?.onOperationFailed("Nearby 拒绝连接", it) }
    }

    override fun sendBytes(endpointIds: List<String>, bytes: ByteArray) {
        if (endpointIds.isEmpty()) return
        val operationListener = listener
        client.sendPayload(endpointIds, Payload.fromBytes(bytes))
            .addOnFailureListener { operationListener?.onOperationFailed("Nearby 发送", it) }
    }

    override fun disconnect(endpointId: String) = client.disconnectFromEndpoint(endpointId)

    override fun stopAll() {
        client.stopAdvertising()
        client.stopDiscovery()
        client.stopAllEndpoints()
        listener = null
    }

    companion object {
        const val SERVICE_ID = "host.msknet.sunsetripple"
        private val ADVERTISING_OPTIONS = AdvertisingOptions.Builder()
            .setStrategy(Strategy.P2P_CLUSTER)
            .build()
        private val DISCOVERY_OPTIONS = DiscoveryOptions.Builder()
            .setStrategy(Strategy.P2P_CLUSTER)
            .build()
    }
}
