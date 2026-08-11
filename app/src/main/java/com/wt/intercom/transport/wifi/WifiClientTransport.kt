package com.wt.intercom.transport.wifi

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameStreamReader
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.MemberInfo
import com.wt.intercom.session.RosterCodec
import com.wt.intercom.transport.Transport
import com.wt.intercom.transport.TransportListener
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.readFrameSafely
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/**
 * WiFi 直连房成员侧：TCP 连 GO 入房拿成员表，语音经 UDP 与所有成员直接互发。
 *
 * 端口是构造参数只为可测；生产用默认值即 [WifiHostTransport] 的固定端口。
 */
class WifiClientTransport(
    private val nickname: String,
    private val hostIp: String,
    private val listener: TransportListener,
    private val signalPort: Int = WifiHostTransport.SIGNAL_PORT,
    audioBindPort: Int = WifiHostTransport.AUDIO_PORT,
    private val peerAudioPort: Int = WifiHostTransport.AUDIO_PORT,
) : Transport {

    private companion object {
        const val CONNECT_TIMEOUT_MS = 5000
        const val PING_INTERVAL_MS = 3000L
        const val UDP_BUFFER = 2048
    }

    @Volatile private var running = true
    @Volatile private var peers: List<MemberInfo> = emptyList()
    @Volatile private var selfId = -1
    private val closed = AtomicBoolean(false)
    private val started = AtomicBoolean(false)
    private val tcp = Socket()
    private val udp = DatagramSocket(audioBindPort)
    private val writeLock = Any()

    val audioPort: Int get() = udp.localPort

    /**
     * 阻塞连接与入房，须在后台线程调用。连接失败抛出（房加不上要让 UI 看见），
     * 但会先释放已占的 UDP 端口，避免重试时端口被自己占死。
     */
    fun start() {
        check(started.compareAndSet(false, true)) { "WifiClientTransport 已启动" }
        try {
            tcp.connect(InetSocketAddress(hostIp, signalPort), CONNECT_TIMEOUT_MS)
            synchronized(writeLock) {
                tcp.getOutputStream().apply {
                    write(Frame(FrameType.JOIN, 0, 0, nickname.toByteArray(Charsets.UTF_8)).encode())
                    flush()
                }
            }
        } catch (e: Exception) {
            close()
            throw e
        }
        Thread(::tcpReadLoop, "wifi-client-tcp").start()
        Thread(::udpReceiveLoop, "wifi-client-udp").start()
        Thread(::pingLoop, "wifi-client-ping").start()
    }

    private fun tcpReadLoop() {
        val reader = try {
            FrameStreamReader(tcp.getInputStream())
        } catch (e: Exception) {
            TransportLog.w("取信令输入流失败: ${e.message}", e)
            notifyDisconnected("房间已结束")
            return
        }
        while (running) {
            // 硬指标：接收循环一律走 readFrameSafely——null＝断流或协议错误，判定房间结束。
            val f = try {
                reader.readFrameSafely()
            } catch (e: Exception) {
                // 本端 close() 或对端复位会让 read 抛 IOException，同样按房间结束处理。
                if (running) TransportLog.w("信令连接读取异常: ${e.message}", e)
                notifyDisconnected("房间已结束")
                return
            }
            if (f == null) {
                notifyDisconnected("房间已结束")
                return
            }
            when (f.type) {
                FrameType.ROSTER -> {
                    val roster = try {
                        RosterCodec.decode(f.payload)
                    } catch (e: IllegalArgumentException) {
                        TransportLog.w("成员表解析失败，忽略本帧: ${e.message}", e)
                        continue
                    }
                    selfId = roster.yourId
                    peers = roster.members
                    listener.onRoster(roster)
                }
                FrameType.JOIN -> Unit   // 主机不会下发 JOIN，忽略
                else -> listener.onFrame(f)
            }
        }
    }

    private fun udpReceiveLoop() {
        val buf = ByteArray(UDP_BUFFER)
        while (running) {
            try {
                val packet = DatagramPacket(buf, buf.size)
                udp.receive(packet)
                listener.onFrame(Frame.decode(buf.copyOf(packet.length)))
            } catch (e: IllegalArgumentException) {
                TransportLog.w("丢弃畸形音频包: ${e.message}", e)
            } catch (e: Exception) {
                if (!running || udp.isClosed) break
                TransportLog.w("音频端口接收异常: ${e.message}", e)
            }
        }
    }

    /** 心跳：让主机的读循环有活跃信号，也让本端尽早发现半开链路。 */
    private fun pingLoop() {
        while (running) {
            try {
                Thread.sleep(PING_INTERVAL_MS)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
            val id = selfId
            if (!running || id < 0) continue
            runCatching { writeTcp(Frame(FrameType.PING, id, 0, ByteArray(0))) }
                .onFailure { TransportLog.w("心跳发送失败: ${it.message}", it) }
        }
    }

    private fun writeTcp(frame: Frame) {
        val bytes = frame.encode()
        synchronized(writeLock) {
            tcp.getOutputStream().apply {
                write(bytes)
                flush()
            }
        }
    }

    override fun broadcast(frame: Frame) {
        if (frame.type == FrameType.AUDIO) {
            val data = frame.encode()
            for (m in peers) {
                if (m.id == selfId) continue
                runCatching {
                    udp.send(DatagramPacket(data, data.size, InetAddress.getByName(m.ip), peerAudioPort))
                }.onFailure { TransportLog.w("音频发往 ${m.ip} 失败: ${it.message}", it) }
            }
        } else {
            runCatching { writeTcp(frame) }
                .onFailure { TransportLog.w("信令 ${frame.type} 发送失败: ${it.message}", it) }
        }
    }

    /** 停机后仍可能有读线程走到通知分支，用 running 拦掉重复上报。 */
    private fun notifyDisconnected(reason: String) {
        if (!running) return
        running = false
        listener.onDisconnected(reason)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        running = false
        runCatching { tcp.close() }
            .onFailure { TransportLog.w("关闭信令连接失败: ${it.message}", it) }
        runCatching { udp.close() }
            .onFailure { TransportLog.w("关闭音频端口失败: ${it.message}", it) }
    }
}
