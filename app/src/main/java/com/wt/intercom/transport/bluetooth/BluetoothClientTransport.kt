package com.wt.intercom.transport.bluetooth

import android.Manifest
import android.bluetooth.BluetoothDevice
import androidx.annotation.RequiresPermission
import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameStreamReader
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.RosterCodec
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.ReconnectPolicy
import com.wt.intercom.transport.ResumeJoinCodec
import com.wt.intercom.transport.readFrameSafely
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class BluetoothClientTransport internal constructor(
    private val nickname: String,
    private val listener: BluetoothRoomTransportListener,
    private val nextReconnectDelayMs: (ReconnectPolicy) -> Long? = { it.nextDelayMs() },
    private val connectionFactory: () -> BluetoothConnection,
) : BluetoothRoomTransport {

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    constructor(
        nickname: String,
        listener: BluetoothRoomTransportListener,
        device: BluetoothDevice,
    ) : this(nickname, listener, connectionFactory = { BluetoothRoomRfcomm.client(device) })

    override val isHost = false
    private data class Link(
        val connection: BluetoothConnection,
        val queue: BluetoothSendQueue = BluetoothSendQueue(),
        val failed: AtomicBoolean = AtomicBoolean(false),
        val writeLock: Any = Any(),
    )

    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val scheduler = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "bluetooth-client-reconnect").apply { isDaemon = true }
    }
    private val reconnectPolicy = ReconnectPolicy()
    private val resumeToken = ByteArray(16).also(SecureRandom()::nextBytes)
    private val joined = AtomicBoolean(false)
    @Volatile private var link: Link? = null

    override fun start() {
        check(started.compareAndSet(false, true)) { "BluetoothClientTransport 已启动" }
        try {
            openLink()
        } catch (e: Exception) {
            close()
            throw e
        }
    }

    private fun openLink() {
        val opened = connectionFactory()
        val newLink = Link(opened)
        if (closed.get()) {
            runCatching { opened.close() }
            return
        }
        try {
            opened.output.apply {
                write(Frame(FrameType.JOIN, 0, 0, ResumeJoinCodec.encode(resumeToken, nickname)).encode())
                flush()
            }
        } catch (e: Exception) {
            runCatching { opened.close() }
            throw e
        }
        link = newLink
        reconnectPolicy.reset()
        Thread({ writerLoop(newLink) }, "bluetooth-client-writer").start()
        Thread({ readerLoop(newLink) }, "bluetooth-client-reader").start()
    }

    private fun writerLoop(current: Link) {
        try {
            while (true) {
                val frame = current.queue.take() ?: break
                synchronized(current.writeLock) {
                    current.connection.output.apply {
                        write(frame.encode())
                        flush()
                    }
                }
            }
        } catch (e: Exception) {
            if (!closed.get()) TransportLog.w("蓝牙主机写入失败: ${e.message}", e)
        } finally {
            handleLinkFailure(current)
        }
    }

    private fun readerLoop(current: Link) {
        val reader = try {
            FrameStreamReader(current.connection.input)
        } catch (e: Exception) {
            handleLinkFailure(current)
            return
        }
        try {
            while (!closed.get() && link === current) {
                val frame = reader.readFrameSafely() ?: break
                if (frame.type == FrameType.ROSTER) {
                    val roster = try {
                        RosterCodec.decode(frame.payload)
                    } catch (e: IllegalArgumentException) {
                        continue
                    }
                    listener.onRoster(roster)
                    joined.set(true)
                } else if (frame.type == FrameType.LEAVE && frame.senderId == HOST_ID) {
                    listener.onDisconnected("房间已结束")
                    close()
                    return
                } else if (frame.type != FrameType.JOIN) {
                    listener.onFrame(frame)
                }
            }
        } catch (e: Exception) {
            if (!closed.get()) TransportLog.w("蓝牙主机读取失败: ${e.message}", e)
        } finally {
            handleLinkFailure(current)
        }
    }

    override fun sendTo(memberId: Int, frame: Frame) {
        require(memberId == HOST_ID) { "客户端只能向主机发送" }
        link?.queue?.offer(frame)
    }

    override fun broadcastSignal(frame: Frame) {
        require(frame.type != FrameType.AUDIO) { "AUDIO 必须使用 sendTo 发送" }
        val current = link ?: return
        if (frame.type == FrameType.LEAVE) {
            runCatching {
                synchronized(current.writeLock) {
                    current.connection.output.apply {
                        write(frame.encode())
                        flush()
                    }
                }
            }
        } else {
            current.queue.offer(frame)
        }
    }

    private fun handleLinkFailure(current: Link) {
        if (!current.failed.compareAndSet(false, true)) return
        current.queue.close()
        runCatching { current.connection.close() }
        if (link !== current || closed.get()) return
        link = null
        if (joined.get()) scheduleReconnect() else listener.onDisconnected("房间已结束")
    }

    private fun scheduleReconnect() {
        val delay = nextReconnectDelayMs(reconnectPolicy)
        if (delay == null) {
            listener.onDisconnected("房间已结束")
            return
        }
        scheduler.schedule({
            if (closed.get()) return@schedule
            runCatching { openLink() }.onFailure { scheduleReconnect() }
        }, delay, TimeUnit.MILLISECONDS)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        scheduler.shutdownNow()
        link?.let {
            it.queue.close()
            runCatching { it.connection.close() }
        }
        link = null
    }

    private companion object {
        const val HOST_ID = 0
    }
}
