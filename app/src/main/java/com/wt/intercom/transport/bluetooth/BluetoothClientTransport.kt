package com.wt.intercom.transport.bluetooth

import android.Manifest
import android.bluetooth.BluetoothDevice
import androidx.annotation.RequiresPermission
import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameStreamReader
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.RosterCodec
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.readFrameSafely
import java.util.concurrent.atomic.AtomicBoolean

class BluetoothClientTransport internal constructor(
    private val nickname: String,
    private val listener: BluetoothRoomTransportListener,
    private val connectionFactory: () -> BluetoothConnection,
) : BluetoothRoomTransport {

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    constructor(
        nickname: String,
        listener: BluetoothRoomTransportListener,
        device: BluetoothDevice,
    ) : this(nickname, listener, { BluetoothRoomRfcomm.client(device) })

    override val isHost = false
    private val queue = BluetoothSendQueue()
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val connected = AtomicBoolean(false)
    @Volatile private var running = false
    @Volatile private var connection: BluetoothConnection? = null

    override fun start() {
        check(started.compareAndSet(false, true)) { "BluetoothClientTransport 已启动" }
        val opened = try {
            connectionFactory()
        } catch (e: Exception) {
            close()
            throw e
        }
        connection = opened
        running = true
        connected.set(true)
        try {
            opened.output.apply {
                write(Frame(FrameType.JOIN, 0, 0, nickname.toByteArray(Charsets.UTF_8)).encode())
                flush()
            }
        } catch (e: Exception) {
            close()
            throw e
        }
        Thread({ writerLoop(opened) }, "bluetooth-client-writer").start()
        Thread({ readerLoop(opened) }, "bluetooth-client-reader").start()
    }

    private fun writerLoop(opened: BluetoothConnection) {
        try {
            while (true) {
                val frame = queue.take() ?: break
                opened.output.apply {
                    write(frame.encode())
                    flush()
                }
            }
        } catch (e: Exception) {
            if (running) TransportLog.w("蓝牙主机写入失败: ${e.message}", e)
        } finally {
            notifyDisconnected("房间已结束")
        }
    }

    private fun readerLoop(opened: BluetoothConnection) {
        val reader = try {
            FrameStreamReader(opened.input)
        } catch (e: Exception) {
            notifyDisconnected("房间已结束")
            return
        }
        try {
            while (running) {
                val frame = reader.readFrameSafely() ?: break
                if (frame.type == FrameType.ROSTER) {
                    val roster = try {
                        RosterCodec.decode(frame.payload)
                    } catch (e: IllegalArgumentException) {
                        continue
                    }
                    listener.onRoster(roster)
                } else if (frame.type != FrameType.JOIN) {
                    listener.onFrame(frame)
                }
            }
        } catch (e: Exception) {
            if (running) TransportLog.w("蓝牙主机读取失败: ${e.message}", e)
        } finally {
            notifyDisconnected("房间已结束")
        }
    }

    override fun sendTo(memberId: Int, frame: Frame) {
        require(memberId == HOST_ID) { "客户端只能向主机发送" }
        queue.offer(frame)
    }

    override fun broadcastSignal(frame: Frame) {
        require(frame.type != FrameType.AUDIO) { "AUDIO 必须使用 sendTo 发送" }
        queue.offer(frame)
    }

    private fun notifyDisconnected(reason: String) {
        if (!connected.compareAndSet(true, false)) return
        running = false
        queue.close()
        runCatching { connection?.close() }
        listener.onDisconnected(reason)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        connected.set(false)
        running = false
        queue.close()
        runCatching { connection?.close() }
    }

    private companion object {
        const val HOST_ID = 0
    }
}
