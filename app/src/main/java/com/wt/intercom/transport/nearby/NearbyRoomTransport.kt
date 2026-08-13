package com.wt.intercom.transport.nearby

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.MemberInfo
import com.wt.intercom.session.Roster
import com.wt.intercom.session.RosterCodec
import com.wt.intercom.transport.RosterFrames
import com.wt.intercom.transport.ReconnectPolicy
import com.wt.intercom.transport.ResumeJoinCodec
import com.wt.intercom.transport.Transport
import com.wt.intercom.transport.TransportListener
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class NearbyRoomTransport private constructor(
    private val nickname: String,
    private val transportListener: TransportListener,
    private val port: NearbyConnectionsPort,
    private val isHost: Boolean,
    private val hostEndpointId: String? = null,
    private val reconnectGraceMs: Long = RECONNECT_GRACE_MS,
    private val nextReconnectDelayMs: (ReconnectPolicy) -> Long? = { it.nextDelayMs() },
) : Transport, NearbyConnectionsListener {

    private data class Peer(
        var endpointId: String,
        var member: MemberInfo,
        val resumeToken: String,
        var reconnecting: Boolean = false,
        var expiry: ScheduledFuture<*>? = null,
    )

    private val lock = Any()
    private val peers = linkedMapOf<String, Peer>()
    private val connectedEndpoints = linkedSetOf<String>()
    private val discoveredEndpoints = linkedMapOf<String, NearbyEndpoint>()
    private val pendingConnections = linkedSetOf<String>()
    private val reconnectPolicies = linkedMapOf<String, ReconnectPolicy>()
    private val reconnectTasks = linkedMapOf<String, ScheduledFuture<*>>()
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val hostDisconnected = AtomicBoolean(false)
    private val resumeToken = ByteArray(16).also(SecureRandom()::nextBytes)
    private val scheduler = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "nearby-reconnect").apply { isDaemon = true }
    }
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
        if (isHost && synchronized(lock) {
            peers.size + 1 >= MAX_MEMBERS && peers.values.none { it.reconnecting }
        }) {
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
        if (!isHost && endpointId != hostEndpointId) {
            if (accepted) finishPeerReconnect(endpointId) else schedulePeerReconnect(endpointId)
        }
        if (accepted && !isHost && endpointId == hostEndpointId) {
            port.sendBytes(
                listOf(endpointId),
                Frame(FrameType.JOIN, 0, 0, ResumeJoinCodec.encode(resumeToken, nickname)).encode(),
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
            val join = runCatching { ResumeJoinCodec.decode(frame.payload) }.getOrNull() ?: run {
                port.disconnect(endpointId)
                return
            }
            admit(endpointId, join.nickname, join.token.toTokenKey())
        } else if (!isHost && frame.type == FrameType.ROSTER && endpointId == hostEndpointId) {
            val roster = runCatching { RosterCodec.decode(frame.payload) }.getOrNull() ?: return
            val removedEndpoints = synchronized(lock) {
                selfId = roster.yourId
                val aliveEndpoints = roster.members
                    .filter { it.id != roster.yourId }
                    .mapTo(linkedSetOf()) { member ->
                        if (member.id == HOST_ID) hostEndpointId!! else member.ip
                    }
                val removed = peers.keys - aliveEndpoints
                removed.forEach(::removePeer)
                roster.members.filter { it.id != roster.yourId }.forEach { member ->
                    val endpointId = if (member.id == HOST_ID) hostEndpointId!! else member.ip
                    val existing = peers[endpointId]
                    if (existing == null) {
                        peers[endpointId] = Peer(endpointId, member, resumeToken = "")
                    } else {
                        existing.member = member
                    }
                }
                removed
            }
            removedEndpoints.forEach(port::disconnect)
            transportListener.onRoster(roster)
            connectMissingPeers()
        } else if (frame.type != FrameType.ROSTER && frame.type != FrameType.JOIN) {
            val peer = synchronized(lock) { peers[endpointId] } ?: return
            val boundFrame = Frame(frame.type, peer.member.id, frame.seq, frame.payload)
            if (frame.type == FrameType.LEAVE) {
                synchronized(lock) { removePeer(endpointId) }
            }
            transportListener.onFrame(boundFrame)
            if (isHost && frame.type == FrameType.LEAVE) pushRosterToAll()
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

    private fun admit(endpointId: String, requestedNickname: String, token: String) {
        var reconnectedId: Int? = null
        synchronized(lock) {
            if (endpointId !in connectedEndpoints) return
            peers[endpointId]?.let { return }
            val resumed = peers.values.firstOrNull { it.resumeToken == token && it.reconnecting }
            if (resumed != null) {
                val oldEndpointId = resumed.endpointId
                peers.remove(oldEndpointId)
                connectedEndpoints.remove(oldEndpointId)
                resumed.expiry?.cancel(false)
                resumed.expiry = null
                resumed.reconnecting = false
                resumed.endpointId = endpointId
                resumed.member = resumed.member.copy(
                    nickname = RosterCodec.truncateNickname(requestedNickname),
                    ip = endpointId,
                )
                peers[endpointId] = resumed
                reconnectedId = resumed.member.id
                return@synchronized
            }
            if (peers.size + 1 >= MAX_MEMBERS) {
                port.disconnect(endpointId)
                connectedEndpoints -= endpointId
                return
            }
            val id = (1..255).first { candidate -> peers.values.none { it.member.id == candidate } }
            val member = MemberInfo(id, RosterCodec.truncateNickname(requestedNickname), endpointId)
            peers[endpointId] = Peer(endpointId, member, token)
        }
        reconnectedId?.let(transportListener::onMemberReconnected)
        pushRosterToAll()
    }

    private fun pushRosterToAll() {
        val peersSnapshot = synchronized(lock) {
            peers.values.filter { it.endpointId in connectedEndpoints }
        }
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
        if (!isHost) {
            val memberId = synchronized(lock) {
                connectedEndpoints -= endpointId
                peers[endpointId]?.member?.id
            } ?: return
            transportListener.onMemberReconnecting(memberId)
            schedulePeerReconnect(endpointId, reset = true)
            return
        }
        val reconnecting = synchronized(lock) {
            connectedEndpoints -= endpointId
            val peer = peers[endpointId] ?: return
            if (peer.reconnecting) return
            peer.reconnecting = true
            peer.expiry = scheduler.schedule(
                { expirePeer(peer.member.id, endpointId) },
                reconnectGraceMs,
                TimeUnit.MILLISECONDS,
            )
            peer
        } ?: return
        transportListener.onMemberReconnecting(reconnecting.member.id)
        if (isHost) pushRosterToAll()
    }

    override fun onOperationFailed(operation: String, error: Throwable) {
        if (!closed.get()) transportListener.onDisconnected("$operation 失败：${error.message ?: "未知错误"}")
    }

    override fun onConnectionRequestFailed(endpointId: String, error: Throwable) {
        if (closed.get()) return
        synchronized(lock) { pendingConnections -= endpointId }
        if (!isHost && endpointId != hostEndpointId && synchronized(lock) { endpointId in peers }) {
            schedulePeerReconnect(endpointId)
        } else {
            onOperationFailed("Nearby 连接", error)
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        port.setListener(null)
        port.stopAll()
        scheduler.shutdownNow()
        synchronized(lock) {
            connectedEndpoints.clear()
            discoveredEndpoints.clear()
            pendingConnections.clear()
            reconnectPolicies.clear()
            reconnectTasks.clear()
            peers.clear()
        }
    }

    private fun membersSnapshot(): List<MemberInfo> = synchronized(lock) {
        buildList {
            add(MemberInfo(HOST_ID, RosterCodec.truncateNickname(nickname), HOST_ENDPOINT))
            peers.values.forEach { add(it.member) }
        }
    }

    private fun expirePeer(memberId: Int, endpointId: String) {
        if (closed.get()) return
        val removed = synchronized(lock) {
            val peer = peers[endpointId]
            if (peer?.member?.id != memberId || !peer.reconnecting) return
            peers.remove(endpointId) ?: return
        }
        transportListener.onMemberReconnectFailed(removed.member.id)
        if (isHost) pushRosterToAll()
    }

    private fun schedulePeerReconnect(endpointId: String, reset: Boolean = false) {
        val scheduled = synchronized(lock) {
            if (closed.get() || endpointId !in peers || endpointId in connectedEndpoints) return
            if (reset) {
                reconnectTasks.remove(endpointId)?.cancel(false)
                reconnectPolicies[endpointId] = ReconnectPolicy()
            }
            if (endpointId in reconnectTasks) return
            val policy = reconnectPolicies.getOrPut(endpointId) { ReconnectPolicy() }
            val delay = nextReconnectDelayMs(policy)
            if (delay == null) {
                reconnectPolicies.remove(endpointId)
                peers[endpointId]?.member?.id
            } else {
                reconnectTasks[endpointId] = scheduler.schedule(
                    {
                        val shouldRequest = synchronized(lock) {
                            reconnectTasks.remove(endpointId)
                            if (closed.get() || endpointId in connectedEndpoints || endpointId !in peers) {
                                false
                            } else {
                                pendingConnections += endpointId
                                true
                            }
                        }
                        if (shouldRequest) port.requestConnection(nickname, endpointId)
                    },
                    delay,
                    TimeUnit.MILLISECONDS,
                )
                null
            }
        }
        scheduled?.let(transportListener::onMemberReconnectFailed)
    }

    private fun finishPeerReconnect(endpointId: String) {
        val memberId = synchronized(lock) {
            reconnectTasks.remove(endpointId)?.cancel(false)
            val wasReconnecting = reconnectPolicies.remove(endpointId) != null
            if (wasReconnecting) peers[endpointId]?.member?.id else null
        }
        memberId?.let(transportListener::onMemberReconnected)
    }

    private fun removePeer(endpointId: String): Peer? {
        reconnectTasks.remove(endpointId)?.cancel(false)
        reconnectPolicies.remove(endpointId)
        connectedEndpoints.remove(endpointId)
        pendingConnections.remove(endpointId)
        return peers.remove(endpointId)?.also { it.expiry?.cancel(false) }
    }

    private fun ByteArray.toTokenKey(): String = joinToString("") { "%02x".format(it.toInt() and 0xFF) }

    companion object {
        private const val HOST_ID = 0
        private const val HOST_ENDPOINT = "host"
        private const val MAX_MEMBERS = 6
        private const val RECONNECT_GRACE_MS = 7_000L

        fun host(
            nickname: String,
            listener: TransportListener,
            port: NearbyConnectionsPort,
        ): NearbyRoomTransport = NearbyRoomTransport(nickname, listener, port, isHost = true)

        internal fun host(
            nickname: String,
            listener: TransportListener,
            port: NearbyConnectionsPort,
            reconnectGraceMs: Long,
        ): NearbyRoomTransport = NearbyRoomTransport(
            nickname,
            listener,
            port,
            isHost = true,
            reconnectGraceMs = reconnectGraceMs,
        )

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

        internal fun guest(
            nickname: String,
            listener: TransportListener,
            port: NearbyConnectionsPort,
            hostEndpointId: String,
            nextReconnectDelayMs: (ReconnectPolicy) -> Long?,
        ): NearbyRoomTransport = NearbyRoomTransport(
            nickname,
            listener,
            port,
            isHost = false,
            hostEndpointId = hostEndpointId,
            nextReconnectDelayMs = nextReconnectDelayMs,
        )
    }
}
