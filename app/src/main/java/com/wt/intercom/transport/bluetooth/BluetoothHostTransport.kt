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
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.readFrameSafely
import java.util.concurrent.atomic.AtomicBoolean

class BluetoothHostTransport internal constructor(
    private val nickname: String,
    private val listener: BluetoothRoomTransportListener,
    private val serverFactory: () -> BluetoothConnectionServer,
) : BluetoothRoomTransport {

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    constructor(
        nickname: String,
        listener: BluetoothRoomTransportListener,
        adapter: BluetoothAdapter,
    ) : this(nickname, listener, { BluetoothRoomRfcomm.server(adapter) })

    override val isHost = true

    private class Client(
        val id: Int,
        val nickname: String,
        val address: String,
        val connection: BluetoothConnection,
        val queue: BluetoothSendQueue = BluetoothSendQueue(),
    )

    private val lock = Any()
    private val pushLock = Any()
    private val clients = linkedMapOf<Int, Client>()
    private val pending = linkedSetOf<BluetoothConnection>()
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    @Volatile private var running = false
    @Volatile private var server: BluetoothConnectionServer? = null

    override fun start() {
        check(started.compareAndSet(false, true)) { "BluetoothHostTransport 已启动" }
        val opened = serverFactory()
        server = opened
        running = true
        listener.onRoster(Roster(HOST_ID, membersSnapshot()))
        Thread({ acceptLoop(opened) }, "bluetooth-host-accept").start()
    }

    private fun acceptLoop(opened: BluetoothConnectionServer) {
        while (running) {
            val connection = try {
                opened.accept()
            } catch (e: Exception) {
                if (running) TransportLog.w("蓝牙房停止监听: ${e.message}", e)
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
        val client = admit(
            RosterCodec.truncateNickname(String(join.payload, Charsets.UTF_8)),
            connection,
        ) ?: run {
            dropPending(connection)
            return
        }
        Thread({ writerLoop(client) }, "bluetooth-host-writer-${client.id}").start()
        pushRosterToAll()
        try {
            while (running) {
                val frame = reader.readFrameSafely() ?: break
                when (frame.type) {
                    FrameType.LEAVE -> break
                    FrameType.JOIN, FrameType.ROSTER -> Unit
                    else -> listener.onFrame(
                        Frame(frame.type, client.id, frame.seq, frame.payload),
                    )
                }
            }
        } catch (e: Exception) {
            if (running) TransportLog.w("蓝牙成员 ${client.id} 读取异常: ${e.message}", e)
        } finally {
            dropClient(client, notify = running)
        }
    }

    private fun writerLoop(client: Client) {
        try {
            while (true) {
                val frame = client.queue.take() ?: break
                client.connection.output.apply {
                    write(frame.encode())
                    flush()
                }
            }
        } catch (e: Exception) {
            if (running) TransportLog.w("蓝牙成员 ${client.id} 写入异常: ${e.message}", e)
        } finally {
            dropClient(client, notify = running)
        }
    }

    private fun admit(nickname: String, connection: BluetoothConnection): Client? = synchronized(lock) {
        if (!running || clients.size + 1 >= MAX_MEMBERS) return null
        val id = (1..255).firstOrNull { it !in clients } ?: return null
        val candidate = MemberInfo(id, nickname, connection.remoteAddress)
        try {
            RosterCodec.encode(id, membersSnapshotLocked() + candidate)
        } catch (e: IllegalArgumentException) {
            return null
        }
        Client(id, nickname, connection.remoteAddress, connection).also {
            pending.remove(connection)
            clients[id] = it
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
        synchronized(lock) { clients.values.toList() }.forEach { client ->
            RosterFrames.encode(HOST_ID, client.id, members)?.let(client.queue::offer)
        }
    }

    override fun sendTo(memberId: Int, frame: Frame) {
        synchronized(lock) { clients[memberId] }?.queue?.offer(frame)
    }

    override fun broadcastSignal(frame: Frame) {
        require(frame.type != FrameType.AUDIO) { "AUDIO 必须使用 sendTo 定向发送" }
        synchronized(lock) { clients.values.toList() }.forEach { it.queue.offer(frame) }
    }

    private fun dropPending(connection: BluetoothConnection) {
        synchronized(lock) { pending.remove(connection) }
        runCatching { connection.close() }
    }

    private fun dropClient(client: Client, notify: Boolean) {
        val removed = synchronized(lock) { clients.remove(client.id) === client }
        client.queue.close()
        runCatching { client.connection.close() }
        if (removed && notify) {
            listener.onFrame(Frame(FrameType.LEAVE, client.id, 0, ByteArray(0)))
            pushRosterToAll()
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        running = false
        runCatching { server?.close() }
        val (active, handshaking) = synchronized(lock) {
            val active = clients.values.toList()
            val handshaking = pending.toList()
            clients.clear()
            pending.clear()
            active to handshaking
        }
        active.forEach {
            it.queue.close()
            runCatching { it.connection.close() }
        }
        handshaking.forEach { runCatching { it.close() } }
    }

    private companion object {
        const val HOST_ID = 0
        const val MAX_MEMBERS = 6
    }
}
