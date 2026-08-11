package com.wt.intercom.transport.wifi

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameStreamReader
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.MemberInfo
import com.wt.intercom.session.Roster
import com.wt.intercom.transport.RosterFrames
import com.wt.intercom.transport.Transport
import com.wt.intercom.transport.TransportListener
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.readFrameSafely
import java.io.OutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/**
 * WiFi 直连房组主侧：TCP 信令服务器（分配 ID、维护并下发成员表）+ UDP 音频收发。
 * 语音是网状的：GO 不转发音频，只当普通一员收发自己的。
 *
 * 构造即绑定端口（失败直接抛给调用方，房建不起来要让 UI 看见）；[start] 起线程。
 * 端口与本机 IP 是构造参数只为可测：生产用默认值即 WiFi Direct 的固定组主地址。
 */
class WifiHostTransport(
    private val nickname: String,
    private val listener: TransportListener,
    private val hostIp: String = HOST_IP,
    signalPort: Int = SIGNAL_PORT,
    audioBindPort: Int = AUDIO_PORT,
    private val peerAudioPort: Int = AUDIO_PORT,
) : Transport {

    companion object {
        const val SIGNAL_PORT = 8988
        const val AUDIO_PORT = 8989
        const val HOST_IP = "192.168.49.1"
        const val HOST_ID = 0
        /** 客户端 ID 上限：帧头 senderId 只有 1 字节。 */
        private const val MAX_MEMBER_ID = 255
        private const val UDP_BUFFER = 2048
    }

    private class Client(
        val id: Int,
        val nickname: String,
        val ip: String,
        val socket: Socket,
        val out: OutputStream,
    )

    private val lock = Any()
    private val clients = linkedMapOf<Int, Client>()
    private var nextId = 1
    @Volatile private var running = true
    private val closed = AtomicBoolean(false)
    private val started = AtomicBoolean(false)
    private val server = ServerSocket(signalPort)
    private val udp = DatagramSocket(audioBindPort)

    /** 实际监听端口（构造传 0 时由系统分配）。 */
    val signalPort: Int get() = server.localPort
    val audioPort: Int get() = udp.localPort

    fun start() {
        check(started.compareAndSet(false, true)) { "WifiHostTransport 已启动" }
        listener.onRoster(Roster(HOST_ID, membersSnapshot()))
        Thread(::acceptLoop, "wifi-host-accept").start()
        Thread(::udpReceiveLoop, "wifi-host-udp").start()
    }

    private fun membersSnapshot(): List<MemberInfo> = synchronized(lock) {
        buildList {
            add(MemberInfo(HOST_ID, nickname, hostIp))
            for (c in clients.values) add(MemberInfo(c.id, c.nickname, c.ip))
        }
    }

    private fun acceptLoop() {
        while (running) {
            val socket = try {
                server.accept()
            } catch (e: Exception) {
                if (running) TransportLog.w("信令端口停止监听: ${e.message}", e)
                break
            }
            Thread({ clientLoop(socket) }, "wifi-host-client").start()
        }
    }

    /**
     * 单个客户端的完整生命周期。任何一步失败只断这一个对端，不影响 accept 循环与其他成员。
     */
    private fun clientLoop(socket: Socket) {
        val reader = try {
            FrameStreamReader(socket.getInputStream())
        } catch (e: Exception) {
            TransportLog.w("取客户端输入流失败: ${e.message}", e)
            runCatching { socket.close() }
            return
        }
        // 入房第一帧必须是 JOIN；否则视为非法连接直接关掉。
        val join = reader.readFrameSafely()
        val ip = socket.inetAddress?.hostAddress
        if (join == null || join.type != FrameType.JOIN || ip == null) {
            TransportLog.w("非法入房请求（type=${join?.type}, ip=$ip），关闭连接")
            runCatching { socket.close() }
            return
        }
        val client: Client = synchronized(lock) {
            if (nextId > MAX_MEMBER_ID) null else {
                Client(
                    nextId++,
                    String(join.payload, Charsets.UTF_8),
                    ip,
                    socket,
                    socket.getOutputStream(),
                ).also { clients[it.id] = it }
            }
        } ?: run {
            TransportLog.w("成员 ID 已用尽，拒绝入房")
            runCatching { socket.close() }
            return
        }
        pushRosterToAll()
        try {
            while (running) {
                // 硬指标：接收循环一律走 readFrameSafely——返回 null＝断流或协议错误，断开该对端。
                val f = reader.readFrameSafely() ?: break
                when (f.type) {
                    FrameType.LEAVE -> break
                    FrameType.PING -> Unit
                    FrameType.JOIN, FrameType.ROSTER -> Unit   // 客户端不该发这两类，忽略
                    else -> listener.onFrame(f)
                }
            }
        } catch (e: Exception) {
            TransportLog.w("客户端 ${client.id} 读取异常: ${e.message}", e)
        } finally {
            val removed = synchronized(lock) { clients.remove(client.id) != null }
            runCatching { socket.close() }
            if (removed) {
                listener.onFrame(Frame(FrameType.LEAVE, client.id, 0, ByteArray(0)))
                pushRosterToAll()
            }
        }
    }

    /**
     * 给每个客户端下发个性化成员表（yourId 不同），并更新主机自己的会话。
     * 下发失败的对端就地剔除，然后重发一轮——否则其他人看到的成员表会留着死人。
     */
    private fun pushRosterToAll() {
        while (true) {
            val members = membersSnapshot()
            listener.onRoster(Roster(HOST_ID, members))
            val targets = synchronized(lock) { clients.values.toList() }
            val dead = ArrayList<Client>()
            for (c in targets) {
                // 硬指标：ROSTER 一律经 RosterFrames.encode；null＝载荷超限（已告警），跳过本轮下发。
                val frame = RosterFrames.encode(HOST_ID, c.id, members) ?: continue
                if (!sendTo(c, frame)) dead.add(c)
            }
            if (dead.isEmpty()) return
            for (c in dead) dropClient(c, "成员表下发失败")
        }
    }

    /** 向单个客户端写一帧；失败返回 false 交由调用方剔除。socket 写抛 IOException 是断连常态。 */
    private fun sendTo(c: Client, frame: Frame): Boolean {
        val bytes = frame.encode()
        return try {
            // 同一 socket 可能被 pushRoster（客户端线程）与 broadcast（采集线程）同时写，需串行化。
            synchronized(c.out) {
                c.out.write(bytes)
                c.out.flush()
            }
            true
        } catch (e: Exception) {
            TransportLog.w("向成员 ${c.id} 发送 ${frame.type} 失败: ${e.message}", e)
            false
        }
    }

    private fun dropClient(c: Client, reason: String) {
        val removed = synchronized(lock) { clients.remove(c.id) != null }
        runCatching { c.socket.close() }   // 关 socket 会唤醒该客户端的读线程，由它走 finally
        if (removed) {
            TransportLog.w("剔除成员 ${c.id}（$reason）")
            listener.onFrame(Frame(FrameType.LEAVE, c.id, 0, ByteArray(0)))
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
                TransportLog.w("丢弃畸形音频包: ${e.message}", e)   // UDP 单包坏了不影响后续
            } catch (e: Exception) {
                if (!running || udp.isClosed) break
                TransportLog.w("音频端口接收异常: ${e.message}", e)
            }
        }
    }

    override fun broadcast(frame: Frame) {
        if (frame.type == FrameType.AUDIO) {
            val data = frame.encode()
            val targets = synchronized(lock) { clients.values.map { it.ip } }
            for (ip in targets) {
                runCatching {
                    udp.send(DatagramPacket(data, data.size, InetAddress.getByName(ip), peerAudioPort))
                }.onFailure { TransportLog.w("音频发往 $ip 失败: ${it.message}", it) }
            }
        } else {
            val targets = synchronized(lock) { clients.values.toList() }
            val dead = targets.filterNot { sendTo(it, frame) }
            for (c in dead) dropClient(c, "信令发送失败")
            if (dead.isNotEmpty()) pushRosterToAll()
        }
    }

    /** 幂等停机：先落 running 再关 socket，唤醒所有阻塞在 accept/read/receive 的线程。 */
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        running = false
        runCatching { server.close() }
            .onFailure { TransportLog.w("关闭信令端口失败: ${it.message}", it) }
        runCatching { udp.close() }
            .onFailure { TransportLog.w("关闭音频端口失败: ${it.message}", it) }
        val targets = synchronized(lock) {
            val all = clients.values.toList()
            clients.clear()
            all
        }
        for (c in targets) runCatching { c.socket.close() }
    }
}
