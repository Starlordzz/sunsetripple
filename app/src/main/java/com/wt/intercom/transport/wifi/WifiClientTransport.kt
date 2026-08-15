package com.wt.intercom.transport.wifi

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameStreamReader
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.MemberInfo
import com.wt.intercom.session.RosterCodec
import com.wt.intercom.transport.ReconnectPolicy
import com.wt.intercom.transport.ResumeJoinCodec
import com.wt.intercom.transport.Transport
import com.wt.intercom.transport.TransportListener
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.HostTransferCodec
import com.wt.intercom.transport.HostTransferPlan
import com.wt.intercom.transport.readFrameSafely
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** WiFi 直连房成员侧：每次重连都重建 TCP、UDP 与其工作线程。 */
class WifiClientTransport(
    private val nickname: String,
    private val hostIp: String,
    private val listener: TransportListener,
    private val localEndpoint: String? = null,
    private val signalPort: Int = WifiHostTransport.SIGNAL_PORT,
    private val audioBindPort: Int = WifiHostTransport.AUDIO_PORT,
    private val peerAudioPort: Int = WifiHostTransport.AUDIO_PORT,
    private val nextReconnectDelayMs: (ReconnectPolicy) -> Long? = { it.nextDelayMs() },
    private val socketFactory: () -> Socket = { Socket() },
    private val udpFactory: (Int) -> DatagramSocket = { DatagramSocket(it) },
) : Transport {

    override val isHost = false

    private data class Link(
        val tcp: Socket,
        val udp: DatagramSocket,
        val failed: AtomicBoolean = AtomicBoolean(false),
        val writeLock: Any = Any(),
    )

    private val closed = AtomicBoolean(false)
    private val started = AtomicBoolean(false)
    private val joined = AtomicBoolean(false)
    private val scheduler = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "wifi-client-reconnect").apply { isDaemon = true }
    }
    private val reconnectPolicy = ReconnectPolicy()
    private val resumeToken = ByteArray(16).also(SecureRandom()::nextBytes)
    @Volatile private var current: Link = newLink()
    @Volatile private var peers: List<MemberInfo> = emptyList()
    @Volatile private var selfId = -1
    @Volatile private var recoverySnapshot: HostTransferPlan? = null

    val audioPort: Int get() = current.udp.localPort

    fun start() {
        check(started.compareAndSet(false, true)) { "WifiClientTransport 已启动" }
        try {
            open(current)
        } catch (e: Exception) {
            close()
            throw e
        }
    }

    private fun newLink(): Link {
        val socket = socketFactory()
        return try {
            Link(socket, udpFactory(audioBindPort))
        } catch (e: Exception) {
            runCatching { socket.close() }
            throw e
        }
    }

    private fun open(link: Link) {
        if (closed.get()) {
            closeLink(link)
            return
        }
        link.tcp.connect(InetSocketAddress(hostIp, signalPort), CONNECT_TIMEOUT_MS)
        synchronized(link.writeLock) {
            link.tcp.getOutputStream().apply {
                write(
                    Frame(
                        FrameType.JOIN,
                        0,
                        0,
                        ResumeJoinCodec.encode(resumeToken, nickname, localEndpoint),
                    ).encode(),
                )
                flush()
            }
        }
        if (closed.get()) {
            closeLink(link)
            return
        }
        current = link
        Thread({ tcpReadLoop(link) }, "wifi-client-tcp").start()
        Thread({ udpReceiveLoop(link) }, "wifi-client-udp").start()
        Thread({ pingLoop(link) }, "wifi-client-ping").start()
    }

    private fun tcpReadLoop(link: Link) {
        val reader = runCatching { FrameStreamReader(link.tcp.getInputStream()) }.getOrElse {
            handleFailure(link)
            return
        }
        try {
            while (!closed.get() && current === link) {
                val frame = reader.readFrameSafely() ?: break
                when (frame.type) {
                    FrameType.ROSTER -> {
                        val roster = runCatching { RosterCodec.decode(frame.payload) }.getOrNull() ?: continue
                        selfId = roster.yourId
                        peers = roster.members
                        joined.set(true)
                        reconnectPolicy.reset()
                        listener.onRoster(roster)
                    }
                    FrameType.LEAVE -> if (frame.senderId == HOST_ID) {
                        recoverOrDisconnect("房间已结束")
                        return
                    } else listener.onFrame(frame)
                    FrameType.HOST_TRANSFER -> if (frame.senderId == HOST_ID) {
                        val plan = runCatching { HostTransferCodec.decode(frame.payload) }.getOrNull() ?: continue
                        listener.onHostTransfer(plan)
                        close()
                        return
                    }
                    FrameType.HOST_SNAPSHOT -> if (frame.senderId == HOST_ID) {
                        runCatching { HostTransferCodec.decode(frame.payload) }
                            .onSuccess {
                                recoverySnapshot = it
                                listener.onHostTransferSnapshot(it)
                            }
                    }
                    FrameType.JOIN -> Unit
                    else -> listener.onFrame(frame)
                }
            }
        } catch (e: Exception) {
            if (!closed.get()) TransportLog.w("信令连接读取异常: ${e.message}", e)
        } finally {
            handleFailure(link)
        }
    }

    private fun udpReceiveLoop(link: Link) {
        val buf = ByteArray(UDP_BUFFER)
        while (!closed.get() && current === link) {
            val frame = try {
                val packet = DatagramPacket(buf, buf.size)
                link.udp.receive(packet)
                Frame.decode(buf.copyOf(packet.length))
            } catch (e: IllegalArgumentException) {
                continue
            } catch (e: Exception) {
                if (closed.get() || link.udp.isClosed || current !== link) break
                continue
            }
            runCatching { listener.onFrame(frame) }
        }
    }

    private fun pingLoop(link: Link) {
        while (!closed.get() && current === link) {
            try {
                Thread.sleep(PING_INTERVAL_MS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
            val id = selfId
            if (id >= 0) runCatching { writeTcp(link, Frame(FrameType.PING, id, 0, ByteArray(0))) }
        }
    }

    private fun writeTcp(link: Link, frame: Frame) = synchronized(link.writeLock) {
        link.tcp.getOutputStream().apply { write(frame.encode()); flush() }
    }

    override fun broadcast(frame: Frame) {
        require(frame.type != FrameType.HOST_TRANSFER) { "客户端不能发送 HOST_TRANSFER" }
        require(frame.type != FrameType.HOST_SNAPSHOT) { "客户端不能发送 HOST_SNAPSHOT" }
        val link = current
        if (frame.type == FrameType.AUDIO) {
            val data = frame.encode()
            peers.filter { it.id != selfId }.forEach { member ->
                runCatching {
                    link.udp.send(DatagramPacket(data, data.size, InetAddress.getByName(member.ip), peerAudioPort))
                }
            }
        } else if (frame.type == FrameType.LEAVE) {
            runCatching { writeTcp(link, frame) }
        } else {
            runCatching { writeTcp(link, frame) }.onFailure { handleFailure(link) }
        }
    }

    private fun handleFailure(link: Link) {
        if (!link.failed.compareAndSet(false, true)) return
        closeLink(link)
        if (closed.get() || current !== link) return
        if (!joined.get()) {
            listener.onDisconnected("房间已结束")
            return
        }
        scheduleReconnect()
    }

    private fun scheduleReconnect() {
        val delay = nextReconnectDelayMs(reconnectPolicy)
        if (delay == null) {
            recoverOrDisconnect("房间已结束")
            return
        }
        scheduler.schedule({
            if (closed.get()) return@schedule
            val replacement = runCatching { newLink() }.getOrElse {
                scheduleReconnect()
                return@schedule
            }
            current = replacement
            runCatching { open(replacement) }.onFailure {
                closeLink(replacement)
                scheduleReconnect()
            }
        }, delay, TimeUnit.MILLISECONDS)
    }

    private fun recoverOrDisconnect(reason: String) {
        recoverySnapshot?.let(listener::onHostTransfer) ?: listener.onDisconnected(reason)
        close()
    }

    private fun closeLink(link: Link) {
        runCatching { link.tcp.close() }
        runCatching { link.udp.close() }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        scheduler.shutdownNow()
        closeLink(current)
    }

    private companion object {
        const val HOST_ID = 0
        const val CONNECT_TIMEOUT_MS = 5_000
        const val PING_INTERVAL_MS = 3_000L
        const val UDP_BUFFER = 2_048
    }
}
