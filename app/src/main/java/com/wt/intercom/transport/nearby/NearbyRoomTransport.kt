package com.wt.intercom.transport.nearby

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.MemberInfo
import com.wt.intercom.session.Roster
import com.wt.intercom.session.RosterCodec
import com.wt.intercom.transport.RosterFrames
import com.wt.intercom.transport.Transport
import com.wt.intercom.transport.TransportListener
import java.util.concurrent.atomic.AtomicBoolean

class NearbyRoomTransport private constructor(
    private val nickname: String,
    private val transportListener: TransportListener,
    private val port: NearbyConnectionsPort,
    private val isHost: Boolean,
    private val hostEndpointId: String? = null,
) : Transport, NearbyConnectionsListener {

    private data class Peer(val endpointId: String, val member: MemberInfo)

    private val lock = Any()
    private val peers = linkedMapOf<String, Peer>()
    private val connectedEndpoints = linkedSetOf<String>()
    private val discoveredEndpoints = linkedMapOf<String, NearbyEndpoint>()
    private val pendingConnections = linkedSetOf<String>()
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val hostDisconnected = AtomicBoolean(false)
    @Volatile private var selfId = -1

    fun start() {
        check(started.compareAndSet(false, true)) { "NearbyRoomTransport 已启动" }
        check(!closed.get()) { "NearbyRoomTransport 已关闭" }
        port.setListener(this)
        if (isHost) {
            transportListener.onRoster(Roster(HOST_ID, membersSnapshot()))
            port.startAdvertising(nickname)
        } else {
            port.startAdvertising(nickname)
            port.startDiscovery()
            port.requestConnection(nickname, hostEndpointId!!)
        }
    }

    override fun onEndpointFound(endpoint: NearbyEndpoint) {
        synchronized(lock) { discoveredEndpoints[endpoint.id] = endpoint }
        connectMissingPeers()
    }

    override fun onEndpointLost(endpointId: String) {
        synchronized(lock) { discoveredEndpoints.remove(endpointId) }
    }

    override fun onConnectionInitiated(endpoint: NearbyEndpoint) {
        if (closed.get()) return
        if (isHost && synchronized(lock) { peers.size + 1 >= MAX_MEMBERS }) {
            port.rejectConnection(endpoint.id)
            return
        }
        port.acceptConnection(endpoint.id)
    }

    override fun onConnectionResult(endpointId: String, accepted: Boolean) {
        if (closed.get()) {
            if (accepted) port.disconnect(endpointId)
            return
        }
        synchronized(lock) {
            pendingConnections -= endpointId
            if (accepted) connectedEndpoints += endpointId else connectedEndpoints -= endpointId
        }
        if (accepted && !isHost && endpointId == hostEndpointId) {
            port.sendBytes(
                listOf(endpointId),
                Frame(FrameType.JOIN, 0, 0, nickname.toByteArray(Charsets.UTF_8)).encode(),
            )
        }
    }

    override fun onBytesReceived(endpointId: String, bytes: ByteArray) {
        val frame = runCatching {
            require(bytes.size >= Frame.HEADER_SIZE) { "不足一个帧头" }
            val payloadSize =
                ((bytes[4].toInt() and 0xFF) shl 8) or (bytes[5].toInt() and 0xFF)
            require(bytes.size == Frame.HEADER_SIZE + payloadSize) { "Nearby payload 必须恰好包含一帧" }
            Frame.decode(bytes)
        }.getOrNull() ?: run {
            port.disconnect(endpointId)
            return
        }
        if (isHost && frame.type == FrameType.JOIN) {
            admit(endpointId, String(frame.payload, Charsets.UTF_8))
        } else if (!isHost && frame.type == FrameType.ROSTER && endpointId == hostEndpointId) {
            val roster = runCatching { RosterCodec.decode(frame.payload) }.getOrNull() ?: return
            synchronized(lock) {
                selfId = roster.yourId
                val aliveEndpoints = roster.members
                    .filter { it.id != roster.yourId }
                    .mapTo(linkedSetOf()) { member ->
                        if (member.id == HOST_ID) hostEndpointId!! else member.ip
                    }
                val removedEndpoints = peers.keys - aliveEndpoints
                peers.keys.retainAll(aliveEndpoints)
                connectedEndpoints.removeAll(removedEndpoints)
                roster.members.filter { it.id != roster.yourId }.forEach { member ->
                    val endpointId = if (member.id == HOST_ID) hostEndpointId!! else member.ip
                    peers[endpointId] = Peer(endpointId, member)
                }
            }
            transportListener.onRoster(roster)
            connectMissingPeers()
        } else if (frame.type != FrameType.ROSTER && frame.type != FrameType.JOIN) {
            val peer = synchronized(lock) { peers[endpointId] } ?: return
            transportListener.onFrame(Frame(frame.type, peer.member.id, frame.seq, frame.payload))
        }
    }

    private fun connectMissingPeers() {
        if (isHost) return
        val toConnect = synchronized(lock) {
            val id = selfId.takeIf { it >= 0 } ?: return
            peers.values
                .filter { peer ->
                    peer.member.id > id &&
                        peer.endpointId != hostEndpointId &&
                        peer.endpointId in discoveredEndpoints &&
                        peer.endpointId !in connectedEndpoints &&
                        peer.endpointId !in pendingConnections
                }
                .map { it.endpointId }
                .also { pendingConnections.addAll(it) }
        }
        toConnect.forEach { port.requestConnection(nickname, it) }
    }

    private fun admit(endpointId: String, requestedNickname: String) {
        val peer = synchronized(lock) {
            if (endpointId !in connectedEndpoints) return
            peers[endpointId]?.let { return }
            if (peers.size + 1 >= MAX_MEMBERS) {
                port.disconnect(endpointId)
                connectedEndpoints -= endpointId
                return
            }
            val id = (1..255).first { candidate -> peers.values.none { it.member.id == candidate } }
            val member = MemberInfo(id, RosterCodec.truncateNickname(requestedNickname), endpointId)
            Peer(endpointId, member).also { peers[endpointId] = it }
        }
        pushRosterToAll()
    }

    private fun pushRosterToAll() {
        val peersSnapshot = synchronized(lock) { peers.values.toList() }
        val members = membersSnapshot()
        transportListener.onRoster(Roster(HOST_ID, members))
        peersSnapshot.forEach { peer ->
            RosterFrames.encode(HOST_ID, peer.member.id, members)?.let { roster ->
                port.sendBytes(listOf(peer.endpointId), roster.encode())
            }
        }
    }

    override fun broadcast(frame: Frame) {
        val endpointIds = synchronized(lock) {
            peers.keys.filter { it in connectedEndpoints }
        }
        port.sendBytes(endpointIds, frame.encode())
    }

    override fun onDisconnected(endpointId: String) {
        if (!isHost && endpointId == hostEndpointId) {
            synchronized(lock) {
                connectedEndpoints -= endpointId
                peers.remove(endpointId)
            }
            if (hostDisconnected.compareAndSet(false, true)) {
                transportListener.onDisconnected("Nearby 房间已结束")
            }
            return
        }
        val removed = synchronized(lock) {
            connectedEndpoints -= endpointId
            peers.remove(endpointId)
        } ?: return
        transportListener.onFrame(Frame(FrameType.LEAVE, removed.member.id, 0, ByteArray(0)))
        if (isHost) pushRosterToAll()
    }

    override fun onOperationFailed(operation: String, error: Throwable) {
        if (!closed.get()) transportListener.onDisconnected("$operation 失败：${error.message ?: "未知错误"}")
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        port.setListener(null)
        port.stopAll()
        synchronized(lock) {
            connectedEndpoints.clear()
            discoveredEndpoints.clear()
            pendingConnections.clear()
            peers.clear()
        }
    }

    private fun membersSnapshot(): List<MemberInfo> = synchronized(lock) {
        buildList {
            add(MemberInfo(HOST_ID, RosterCodec.truncateNickname(nickname), HOST_ENDPOINT))
            peers.values.forEach { add(it.member) }
        }
    }

    companion object {
        private const val HOST_ID = 0
        private const val HOST_ENDPOINT = "host"
        private const val MAX_MEMBERS = 6

        fun host(
            nickname: String,
            listener: TransportListener,
            port: NearbyConnectionsPort,
        ): NearbyRoomTransport = NearbyRoomTransport(nickname, listener, port, isHost = true)

        fun guest(
            nickname: String,
            listener: TransportListener,
            port: NearbyConnectionsPort,
            hostEndpointId: String,
        ): NearbyRoomTransport = NearbyRoomTransport(
            nickname,
            listener,
            port,
            isHost = false,
            hostEndpointId = hostEndpointId,
        )
    }
}
