package com.wt.intercom.transport.bluetooth

import android.Manifest
import android.bluetooth.BluetoothAdapter
import androidx.annotation.RequiresPermission
import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameStreamReader
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.MemberInfo
import com.wt.intercom.session.Roster
import com.wt.intercom.session.RosterCodec
import com.wt.intercom.transport.RosterFrames
import com.wt.intercom.transport.ResumeJoinCodec
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.HostElection
import com.wt.intercom.transport.HostTransferCodec
import com.wt.intercom.transport.HostTransferPlan
import com.wt.intercom.transport.HostTransferSeed
import com.wt.intercom.transport.TransferCandidate
import com.wt.intercom.transport.readFrameSafely
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class BluetoothHostTransport internal constructor(
    private val nickname: String,
    private val listener: BluetoothRoomTransportListener,
    private val reconnectGraceMs: Long = RECONNECT_GRACE_MS,
    private val transferSeed: HostTransferSeed? = null,
    private val transferReservationGraceMs: Long = TRANSFER_RESERVATION_GRACE_MS,
    private val serverFactory: () -> BluetoothConnectionServer,
) : BluetoothRoomTransport {

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    constructor(
        nickname: String,
        listener: BluetoothRoomTransportListener,
        adapter: BluetoothAdapter,
        transferSeed: HostTransferSeed? = null,
        secure: Boolean = true,
        transferReservationGraceMs: Long = TRANSFER_RESERVATION_GRACE_MS,
    ) : this(
        nickname,
        listener,
        transferSeed = transferSeed,
        transferReservationGraceMs = transferReservationGraceMs,
        serverFactory = { BluetoothRoomRfcomm.server(adapter, secure) },
    )

    override val isHost = true

    private class Client(
        val id: Int,
        var nickname: String,
        var address: String,
        val resumeToken: String,
        val joinOrder: Long,
        var link: ClientLink,
        var reconnecting: Boolean = false,
        var expiry: ScheduledFuture<*>? = null,
    )

    private data class ClientLink(
        val connection: BluetoothConnection,
        val queue: BluetoothSendQueue = BluetoothSendQueue(),
        val dropped: AtomicBoolean = AtomicBoolean(false),
        val writeLock: Any = Any(),
    )

    private val lock = Any()
    private val pushLock = Any()
    private val transferLock = Any()
    private val clients = linkedMapOf<Int, Client>()
    private val expectedByEndpoint = transferSeed?.expectedByEndpoint()?.toMutableMap() ?: linkedMapOf()
    private var nextJoinOrder = transferSeed?.nextJoinOrder ?: 1L
    private val pending = linkedSetOf<BluetoothConnection>()
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    @Volatile private var preparedTransfer: HostTransferPlan? = null
    private val scheduler = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "bluetooth-host-reconnect").apply { isDaemon = true }
    }
    @Volatile private var running = false
    @Volatile private var server: BluetoothConnectionServer? = null

    override fun start() {
        check(started.compareAndSet(false, true)) { "BluetoothHostTransport 已启动" }
        val opened = serverFactory()
        server = opened
        running = true
        listener.onRoster(Roster(HOST_ID, membersSnapshot()))
        scheduleTransferReservationExpiry()
        Thread({ acceptLoop(opened) }, "bluetooth-host-accept").start()
    }

    private fun scheduleTransferReservationExpiry() {
        if (expectedByEndpoint.isEmpty()) return
        scheduler.schedule(
            { synchronized(lock) { expectedByEndpoint.clear() } },
            transferReservationGraceMs,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun acceptLoop(opened: BluetoothConnectionServer) {
        while (running) {
            val connection = try {
                opened.accept()
            } catch (e: Exception) {
                if (running) {
                    TransportLog.w("蓝牙房停止监听: ${e.message}", e)
                    listener.onDisconnected("蓝牙监听已断开")
                }
                break
            }
            val accepted = synchronized(lock) {
                if (running) pending.add(connection) else false
            }
            if (!accepted) {
                runCatching { connection.close() }
                break
            }
            Thread({ clientLoop(connection) }, "bluetooth-host-client").start()
        }
    }

    private fun clientLoop(connection: BluetoothConnection) {
        val reader = try {
            FrameStreamReader(connection.input)
        } catch (e: Exception) {
            dropPending(connection)
            return
        }
        val join = try {
            reader.readFrameSafely()
        } catch (e: Exception) {
            null
        }
        if (join == null || join.type != FrameType.JOIN) {
            dropPending(connection)
            return
        }
        val resumeJoin = runCatching { ResumeJoinCodec.decode(join.payload) }.getOrNull() ?: run {
            dropPending(connection)
            return
        }
        val client = admit(resumeJoin.nickname, resumeJoin.token.toTokenKey(), connection) ?: run {
            dropPending(connection)
            return
        }
        val wasReconnecting = client.reconnecting
        client.reconnecting = false
        val link = client.link
        Thread({ writerLoop(client, link) }, "bluetooth-host-writer-${client.id}").start()
        pushRosterToAll()
        if (wasReconnecting) {
            listener.onMemberReconnected(client.id)
        }
        var activeLeave = false
        try {
            while (running) {
                val frame = reader.readFrameSafely() ?: break
                when (frame.type) {
                    FrameType.LEAVE -> { activeLeave = true; break }
                    FrameType.JOIN,
                    FrameType.ROSTER,
                    FrameType.HOST_TRANSFER,
                    FrameType.HOST_SNAPSHOT,
                    -> Unit
                    else -> listener.onFrame(
                        Frame(frame.type, client.id, frame.seq, frame.payload),
                    )
                }
            }
        } catch (e: Exception) {
            if (running) TransportLog.w("蓝牙成员 ${client.id} 读取异常: ${e.message}", e)
        } finally {
            dropClient(client, link, activeLeave, notify = running)
        }
    }

    private fun writerLoop(client: Client, link: ClientLink) {
        try {
            while (true) {
                val frame = link.queue.take() ?: break
                synchronized(link.writeLock) {
                    link.connection.output.apply {
                        write(frame.encode())
                        flush()
                    }
                }
            }
        } catch (e: Exception) {
            if (running) TransportLog.w("蓝牙成员 ${client.id} 写入异常: ${e.message}", e)
        } finally {
            dropClient(client, link, activeLeave = false, notify = running)
        }
    }

    private fun admit(nickname: String, token: String, connection: BluetoothConnection): Client? = synchronized(lock) {
        if (!running) return null
        val resumed = clients.values.firstOrNull { it.resumeToken == token && it.reconnecting }
        if (resumed != null) {
            resumed.expiry?.cancel(false)
            resumed.expiry = null
            resumed.nickname = nickname
            resumed.address = connection.remoteAddress
            resumed.link = ClientLink(connection)
            pending.remove(connection)
            return resumed
        }
        val expected = expectedByEndpoint[connection.remoteAddress]
        if (expected == null && clients.size + expectedByEndpoint.size + 1 >= MAX_MEMBERS) return null
        val reservedIds = expectedByEndpoint.values.mapTo(hashSetOf()) { it.newId }
        val id = expected?.newId ?: (1..255).firstOrNull { it !in clients && it !in reservedIds } ?: return null
        val candidate = MemberInfo(id, nickname, connection.remoteAddress)
        try {
            RosterCodec.encode(id, membersSnapshotLocked() + candidate)
        } catch (e: IllegalArgumentException) {
            return null
        }
        val joinOrder = expected?.joinOrder ?: nextJoinOrder.also { nextJoinOrder++ }
        Client(id, nickname, connection.remoteAddress, token, joinOrder, ClientLink(connection)).also {
            pending.remove(connection)
            clients[id] = it
            if (expected != null) expectedByEndpoint.remove(connection.remoteAddress)
        }
    }

    private fun membersSnapshot(): List<MemberInfo> = synchronized(lock) { membersSnapshotLocked() }

    private fun membersSnapshotLocked(): List<MemberInfo> = buildList {
        add(MemberInfo(HOST_ID, RosterCodec.truncateNickname(nickname), "host"))
        clients.values.forEach { add(MemberInfo(it.id, it.nickname, it.address)) }
    }

    private fun pushRosterToAll() = synchronized(pushLock) {
        val members = membersSnapshot()
        listener.onRoster(Roster(HOST_ID, members))
        val activeClients = synchronized(lock) { clients.values.filterNot { it.reconnecting }.toList() }
        val snapshot = HostElection.plan(activeClients.map { client ->
            TransferCandidate(client.id, client.joinOrder, client.nickname, client.address, connected = true)
        })?.let { plan ->
            Frame(FrameType.HOST_SNAPSHOT, HOST_ID, 0, HostTransferCodec.encode(plan))
        }
        activeClients.forEach { client ->
            RosterFrames.encode(HOST_ID, client.id, members)?.let(client.link.queue::offer)
            snapshot?.let(client.link.queue::offer)
        }
    }

    override fun sendTo(memberId: Int, frame: Frame) {
        synchronized(lock) { clients[memberId]?.takeUnless { it.reconnecting } }?.link?.queue?.offer(frame)
    }

    override fun broadcastSignal(frame: Frame) {
        require(frame.type != FrameType.AUDIO) { "AUDIO 必须使用 sendTo 定向发送" }
        require(frame.type != FrameType.HOST_TRANSFER) { "HOST_TRANSFER 只能由 prepareHostTransfer 发送" }
        require(frame.type != FrameType.HOST_SNAPSHOT) { "HOST_SNAPSHOT 只能由成员表更新发送" }
        synchronized(lock) { clients.values.filterNot { it.reconnecting } }.forEach { it.link.queue.offer(frame) }
    }

    override fun prepareHostTransfer(): HostTransferPlan? = synchronized(transferLock) {
        preparedTransfer?.let { return@synchronized it }
        while (running && !closed.get()) {
            val snapshot = synchronized(lock) { clients.values.toList() }
            val plan = HostElection.plan(snapshot.map { client ->
                TransferCandidate(
                    memberId = client.id,
                    joinOrder = client.joinOrder,
                    nickname = client.nickname,
                    endpoint = client.address,
                    connected = !client.reconnecting,
                )
            }) ?: return@synchronized null
            val successor = snapshot.firstOrNull { it.id == plan.successorId && !it.reconnecting }
                ?: continue
            val frame = Frame(FrameType.HOST_TRANSFER, HOST_ID, 0, HostTransferCodec.encode(plan))
            if (!writeTransfer(successor, frame)) {
                dropClient(successor, successor.link, activeLeave = true, notify = true)
                continue
            }
            preparedTransfer = plan
            snapshot.filter { it !== successor && !it.reconnecting }.forEach { client ->
                if (!writeTransfer(client, frame)) {
                    dropClient(client, client.link, activeLeave = true, notify = false)
                }
            }
            return@synchronized plan
        }
        null
    }

    private fun writeTransfer(client: Client, frame: Frame): Boolean = runCatching {
        val link = client.link
        synchronized(link.writeLock) {
            link.connection.output.apply {
                write(frame.encode())
                flush()
            }
        }
    }.onFailure { error ->
        TransportLog.w("向成员 ${client.id} 发送房主交接失败: ${error.message}", error)
    }.isSuccess

    private fun dropPending(connection: BluetoothConnection) {
        synchronized(lock) { pending.remove(connection) }
        runCatching { connection.close() }
    }

    private fun dropClient(
        client: Client,
        link: ClientLink,
        activeLeave: Boolean,
        notify: Boolean,
    ) {
        if (!link.dropped.compareAndSet(false, true)) return
        var reconnecting = false
        var removed = false
        var shouldNotify = notify
        synchronized(lock) {
            if (client.link !== link) return
            link.queue.close()
            shouldNotify = notify && running && !closed.get() && !scheduler.isShutdown
            if (activeLeave || !shouldNotify) {
                removed = clients.remove(client.id) === client
            } else if (!client.reconnecting) {
                client.reconnecting = true
                reconnecting = true
                client.expiry = scheduler.schedule(
                    { expireClient(client) },
                    reconnectGraceMs,
                    TimeUnit.MILLISECONDS,
                )
            }
        }
        runCatching { link.connection.close() }
        if (removed && shouldNotify) {
            listener.onFrame(Frame(FrameType.LEAVE, client.id, 0, ByteArray(0)))
            pushRosterToAll()
        } else if (reconnecting) {
            listener.onMemberReconnecting(client.id)
            pushRosterToAll()
        }
    }

    private fun expireClient(client: Client) {
        if (closed.get()) return
        val removed = synchronized(lock) {
            if (!client.reconnecting || clients.remove(client.id) !== client) return
            true
        }
        if (removed) {
            listener.onMemberReconnectFailed(client.id)
            pushRosterToAll()
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        running = false
        scheduler.shutdownNow()
        runCatching { server?.close() }
        val (active, handshaking) = synchronized(lock) {
            val active = clients.values.toList()
            val handshaking = pending.toList()
            clients.clear()
            pending.clear()
            active to handshaking
        }
        if (preparedTransfer == null) {
            active.forEach { client ->
                runCatching {
                    synchronized(client.link.writeLock) {
                        client.link.connection.output.apply {
                            write(Frame(FrameType.LEAVE, HOST_ID, 0, ByteArray(0)).encode())
                            flush()
                        }
                    }
                }
            }
        }
        active.forEach {
            it.link.queue.close()
            runCatching { it.link.connection.close() }
        }
        handshaking.forEach { runCatching { it.close() } }
    }

    private companion object {
        const val HOST_ID = 0
        const val MAX_MEMBERS = 6
        const val RECONNECT_GRACE_MS = 7_000L
        const val TRANSFER_RESERVATION_GRACE_MS = 7_000L
    }

    private fun ByteArray.toTokenKey(): String = joinToString("") { "%02x".format(it.toInt() and 0xFF) }
}
