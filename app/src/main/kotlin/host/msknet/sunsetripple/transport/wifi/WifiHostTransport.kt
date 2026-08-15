package host.msknet.sunsetripple.transport.wifi

import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.protocol.FrameStreamReader
import host.msknet.sunsetripple.protocol.FrameType
import host.msknet.sunsetripple.session.MemberInfo
import host.msknet.sunsetripple.session.Roster
import host.msknet.sunsetripple.session.RosterCodec
import host.msknet.sunsetripple.transport.RosterFrames
import host.msknet.sunsetripple.transport.ResumeJoinCodec
import host.msknet.sunsetripple.transport.Transport
import host.msknet.sunsetripple.transport.TransportListener
import host.msknet.sunsetripple.transport.TransportLog
import host.msknet.sunsetripple.transport.HostElection
import host.msknet.sunsetripple.transport.HostTransferCodec
import host.msknet.sunsetripple.transport.HostTransferPlan
import host.msknet.sunsetripple.transport.HostTransferSeed
import host.msknet.sunsetripple.transport.TransferCandidate
import host.msknet.sunsetripple.transport.readFrameSafely
import java.io.IOException
import java.io.OutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
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
    private val reconnectGraceMs: Long = RECONNECT_GRACE_MS,
    private val transferSeed: HostTransferSeed? = null,
    private val transferReservationGraceMs: Long = TRANSFER_RESERVATION_GRACE_MS,
) : Transport {

    override val isHost = true

    companion object {
        const val SIGNAL_PORT = 8988
        const val AUDIO_PORT = 8989
        const val HOST_IP = "192.168.49.1"
        const val HOST_ID = 0
        /** 房间人数上限（含主机），见设计规格「人数上限 6 台（含建房者）」。 */
        const val MAX_MEMBERS = 6
        /** 客户端 ID 上限：帧头 senderId 只有 1 字节。 */
        private const val MAX_MEMBER_ID = 255
        /** 入房握手读超时：连上却不发 JOIN 的对端不许占着线程和 fd 不放。 */
        private const val HANDSHAKE_TIMEOUT_MS = 5000
        /** 入房后的读超时：客户端每 3s 一个 PING，静默这么久即判定链路已死。 */
        private const val READ_TIMEOUT_MS = 10000
        private const val UDP_BUFFER = 2048
        private const val RECONNECT_GRACE_MS = 7_000L
        private const val TRANSFER_RESERVATION_GRACE_MS = 7_000L
    }

    private class Client(
        val id: Int,
        var nickname: String,
        var ip: String,
        var endpoint: String,
        val resumeToken: String,
        val joinOrder: Long,
        var link: ClientLink,
        var reconnecting: Boolean = false,
        var expiry: ScheduledFuture<*>? = null,
    )

    private data class ClientLink(
        val socket: Socket,
        val out: OutputStream,
        val dropped: AtomicBoolean = AtomicBoolean(false),
    )

    private val lock = Any()
    /** 成员表下发的串行锁：见 [pushRosterToAll]。 */
    private val pushLock = Any()
    private val transferLock = Any()
    private val clients = linkedMapOf<Int, Client>()
    private val expectedByEndpoint = transferSeed?.expectedByEndpoint()?.toMutableMap() ?: linkedMapOf()
    private var nextJoinOrder = transferSeed?.nextJoinOrder ?: 1L
    @Volatile private var running = true
    private val closed = AtomicBoolean(false)
    private val started = AtomicBoolean(false)
    @Volatile private var preparedTransfer: HostTransferPlan? = null
    private val scheduler = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "wifi-host-reconnect").apply { isDaemon = true }
    }
    private val server = ServerSocket(signalPort)
    private val udp = try {
        DatagramSocket(audioBindPort)
    } catch (e: Exception) {
        // 此时信令端口已经绑住了：不关掉的话 8988 会被这个建不起来的实例永久占着，
        // 用户重试建房必然再失败（"端口已被占用"且看不出是自己占的）。
        runCatching { server.close() }
        throw e
    }

    /** 实际监听端口（构造传 0 时由系统分配）。 */
    val signalPort: Int get() = server.localPort
    val audioPort: Int get() = udp.localPort

    fun start() {
        check(started.compareAndSet(false, true)) { "WifiHostTransport 已启动" }
        listener.onRoster(Roster(HOST_ID, membersSnapshot()))
        scheduleTransferReservationExpiry()
        Thread(::acceptLoop, "wifi-host-accept").start()
        Thread(::udpReceiveLoop, "wifi-host-udp").start()
    }

    private fun scheduleTransferReservationExpiry() {
        if (expectedByEndpoint.isEmpty()) return
        scheduler.schedule(
            { synchronized(lock) { expectedByEndpoint.clear() } },
            transferReservationGraceMs,
            TimeUnit.MILLISECONDS,
        )
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
            // 握手期必须有读超时：连上却不发 JOIN 的对端（扫端口的、半开链路）否则会把
            // 这个线程和 fd 永久钉在 read 上，而它还没进 clients，close() 也够不着。
            // 这类未 JOIN 的 socket 不纳入 close() 的清理范围，靠本超时自然退出，最长滞留 5s。
            socket.soTimeout = HANDSHAKE_TIMEOUT_MS
            FrameStreamReader(socket.getInputStream())
        } catch (e: Exception) {
            TransportLog.w("取客户端输入流失败: ${e.message}", e)
            runCatching { socket.close() }
            return
        }
        // 入房第一帧必须是 JOIN；否则视为非法连接直接关掉。
        // 这里只兜 IOException（含握手超时）：协议错误归 readFrameSafely 收敛成 null。
        // 切勿加宽泛的 catch(Exception)，否则换回裸 readFrame() 时行为无差别，测试也就失去判别力。
        val join = try {
            reader.readFrameSafely()
        } catch (e: IOException) {
            TransportLog.w("等待入房帧失败（超时或断流）: ${e.message}", e)
            runCatching { socket.close() }
            return
        }
        val ip = socket.inetAddress?.hostAddress
        if (join == null || join.type != FrameType.JOIN || ip == null) {
            TransportLog.w("非法入房请求（type=${join?.type}, ip=$ip），关闭连接")
            runCatching { socket.close() }
            return
        }
        // 昵称按 RosterCodec 同口径截断后再入表，免得主机 UI 显示的和下发出去的不一致。
        val resumeJoin = runCatching { ResumeJoinCodec.decode(join.payload) }.getOrNull() ?: run {
            runCatching { socket.close() }
            return
        }
        val client = try {
            admit(resumeJoin.nickname, resumeJoin.token.toTokenKey(), ip, resumeJoin.endpoint.orEmpty(), socket)
        } catch (e: IOException) {
            TransportLog.w("初始化入房连接失败: ${e.message}", e)
            runCatching { socket.close() }
            return
        } ?: run {
            runCatching { socket.close() }
            return
        }
        // 入房后放宽到心跳级超时，别清零：清零就退回"永久阻塞"，链路半开时这条线程再也回不来。
        runCatching { socket.soTimeout = READ_TIMEOUT_MS }
        val link = client.link
        val wasReconnecting = client.reconnecting
        client.reconnecting = false
        pushRosterToAll()
        if (wasReconnecting) listener.onMemberReconnected(client.id)
        var activeLeave = false
        try {
            while (running) {
                // 硬指标：接收循环一律走 readFrameSafely——返回 null＝断流或协议错误，断开该对端。
                val f = reader.readFrameSafely() ?: break
                when (f.type) {
                    FrameType.LEAVE -> { activeLeave = true; break }
                    FrameType.PING -> Unit
                    FrameType.JOIN,
                    FrameType.ROSTER,
                    FrameType.HOST_TRANSFER,
                    FrameType.HOST_SNAPSHOT,
                    -> Unit
                    else -> listener.onFrame(f)
                }
            }
        } catch (e: Exception) {
            TransportLog.w("客户端 ${client.id} 读取异常: ${e.message}", e)
        } finally {
            dropClient(client, link, activeLeave, notify = running)
        }
    }

    /**
     * 准入控制：满员或候选成员表编不进一帧 ROSTER 时拒绝入房，返回 null 由调用方关连接。
     *
     * 必须挡在入表之前——一旦超限的成员进了 clients，之后每一轮 [RosterFrames.encode]
     * 都会对所有人失败（载荷 > 512B），全房成员表当场冻结、新人麦克风哑、UI 永远不 connected。
     * 拒一个人只影响他自己。
     */
    private fun admit(
        nickname: String,
        token: String,
        ip: String,
        endpoint: String,
        socket: Socket,
    ): Client? = synchronized(lock) {
        val resumed = clients.values.firstOrNull { it.resumeToken == token && it.reconnecting }
        if (resumed != null) {
            resumed.expiry?.cancel(false)
            resumed.expiry = null
            resumed.nickname = nickname
            resumed.ip = ip
            if (endpoint.isNotBlank()) resumed.endpoint = endpoint
            resumed.link = ClientLink(socket, socket.getOutputStream())
            return resumed
        }
        val expected = expectedByEndpoint[endpoint]
        val reservedIds = expectedByEndpoint.values.mapTo(hashSetOf()) { it.newId }
        val memberId = expected?.newId
            ?: (1..MAX_MEMBER_ID).firstOrNull { it !in clients && it !in reservedIds }
        if (memberId == null) {
            TransportLog.w("成员 ID 已用尽，拒绝入房")
            return null
        }
        // +1 是主机自己；已经坐满就不再放人进来。
        if (expected == null && clients.size + expectedByEndpoint.size + 1 >= MAX_MEMBERS) {
            TransportLog.w("房间已满（上限 $MAX_MEMBERS 人含主机），拒绝「$nickname」入房")
            return null
        }
        val candidate = MemberInfo(memberId, nickname, ip)
        // 再试编一次：人数没到上限时，超长 IP（IPv6）也可能把载荷顶爆。
        try {
            RosterCodec.encode(candidate.id, membersSnapshot() + candidate)
        } catch (e: IllegalArgumentException) {
            TransportLog.w("成员表将超载荷，拒绝「$nickname」入房: ${e.message}", e)
            return null
        }
        val joinOrder = expected?.joinOrder ?: nextJoinOrder.also { nextJoinOrder++ }
        Client(candidate.id, nickname, ip, endpoint, token, joinOrder, ClientLink(socket, socket.getOutputStream()))
            .also {
                clients[it.id] = it
                if (expected != null) expectedByEndpoint.remove(endpoint)
            }
    }

    /**
     * 给每个客户端下发个性化成员表（yourId 不同），并更新主机自己的会话。
     * 下发失败的对端就地剔除，然后重发一轮——否则其他人看到的成员表会留着死人。
     *
     * 全程串行（[pushLock]）：并发 join 时若两个线程各取快照再交错写出，最后落地的可能是旧快照，
     * 全房成员表就停在缺人的版本上——客户端据此 retainAll 会把新成员的解码流删掉，
     * 该成员一直哑到下次进出房才自愈。取 pushLock 时不持有 [lock]，无锁序倒置。
     */
    private fun pushRosterToAll() = synchronized(pushLock) {
        while (true) {
            val members = membersSnapshot()
            listener.onRoster(Roster(HOST_ID, members))
            val targets = synchronized(lock) { clients.values.filterNot { it.reconnecting }.toList() }
            val snapshot = HostElection.plan(targets.map { client ->
                TransferCandidate(client.id, client.joinOrder, client.nickname, client.endpoint, connected = true)
            })?.let { plan ->
                Frame(FrameType.HOST_SNAPSHOT, HOST_ID, 0, HostTransferCodec.encode(plan))
            }
            val dead = ArrayList<Client>()
            for (c in targets) {
                // 硬指标：ROSTER 一律经 RosterFrames.encode；null＝载荷超限（已告警），跳过本轮下发。
                // 有 admit() 的准入控制兜底，正常路径不该走到这里。
                val frame = RosterFrames.encode(HOST_ID, c.id, members) ?: continue
                if (!sendTo(c, frame) || (snapshot != null && !sendTo(c, snapshot))) dead.add(c)
            }
            if (dead.isEmpty()) return@synchronized
            for (c in dead) dropClient(c, "成员表下发失败")
        }
    }

    /** 向单个客户端写一帧；失败返回 false 交由调用方剔除。socket 写抛 IOException 是断连常态。 */
    private fun sendTo(c: Client, frame: Frame): Boolean {
        val bytes = frame.encode()
        return try {
            // 同一 socket 可能被 pushRoster（客户端线程）与 broadcast（采集线程）同时写，需串行化。
            synchronized(c.link.out) {
                c.link.out.write(bytes)
                c.link.out.flush()
            }
            true
        } catch (e: Exception) {
            TransportLog.w("向成员 ${c.id} 发送 ${frame.type} 失败: ${e.message}", e)
            false
        }
    }

    private fun dropClient(c: Client, reason: String) {
        dropClient(c, c.link, activeLeave = true, notify = running)
        TransportLog.w("剔除成员 ${c.id}（$reason）")
    }

    private fun dropClient(c: Client, link: ClientLink, activeLeave: Boolean, notify: Boolean) {
        if (!link.dropped.compareAndSet(false, true)) return
        var reconnecting = false
        var removed = false
        var shouldNotify = notify
        synchronized(lock) {
            if (c.link !== link) return
            shouldNotify = notify && running && !closed.get() && !scheduler.isShutdown
            if (activeLeave || !shouldNotify) {
                removed = clients.remove(c.id) === c
            } else if (!c.reconnecting) {
                c.reconnecting = true
                reconnecting = true
                c.expiry = scheduler.schedule({ expireClient(c) }, reconnectGraceMs, TimeUnit.MILLISECONDS)
            }
        }
        runCatching { link.socket.close() }
        when {
            removed && shouldNotify -> {
                listener.onFrame(Frame(FrameType.LEAVE, c.id, 0, ByteArray(0)))
                pushRosterToAll()
            }
            reconnecting -> {
                listener.onMemberReconnecting(c.id)
                pushRosterToAll()
            }
        }
    }

    private fun expireClient(c: Client) {
        if (closed.get()) return
        val removed = synchronized(lock) {
            if (!c.reconnecting || clients.remove(c.id) !== c) return
            true
        }
        if (removed) {
            listener.onMemberReconnectFailed(c.id)
            pushRosterToAll()
        }
    }

    private fun udpReceiveLoop() {
        val buf = ByteArray(UDP_BUFFER)
        while (running) {
            val frame = try {
                val packet = DatagramPacket(buf, buf.size)
                udp.receive(packet)
                Frame.decode(buf.copyOf(packet.length))
            } catch (e: IllegalArgumentException) {
                TransportLog.w("丢弃畸形音频包: ${e.message}", e)   // UDP 单包坏了不影响后续
                continue
            } catch (e: Exception) {
                if (!running || udp.isClosed) break
                TransportLog.w("音频端口接收异常: ${e.message}", e)
                continue
            }
            // 回调单独兜底：listener 抛出不是"坏包"，不能记成丢包，更不能打死接收线程。
            try {
                listener.onFrame(frame)
            } catch (e: Exception) {
                TransportLog.w("音频帧回调异常: ${e.message}", e)
            }
        }
    }

    override fun broadcast(frame: Frame) {
        require(frame.type != FrameType.HOST_TRANSFER) { "HOST_TRANSFER 只能由 prepareHostTransfer 发送" }
        require(frame.type != FrameType.HOST_SNAPSHOT) { "HOST_SNAPSHOT 只能由成员表更新发送" }
        if (frame.type == FrameType.AUDIO) {
            val data = frame.encode()
            val targets = synchronized(lock) { clients.values.filterNot { it.reconnecting }.map { it.ip } }
            for (ip in targets) {
                runCatching {
                    udp.send(DatagramPacket(data, data.size, InetAddress.getByName(ip), peerAudioPort))
                }.onFailure { TransportLog.w("音频发往 $ip 失败: ${it.message}", it) }
            }
        } else {
            val targets = synchronized(lock) { clients.values.filterNot { it.reconnecting }.toList() }
            val dead = targets.filterNot { sendTo(it, frame) }
            for (c in dead) dropClient(c, "信令发送失败")
            if (dead.isNotEmpty()) pushRosterToAll()
        }
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
                    endpoint = client.endpoint,
                    connected = !client.reconnecting,
                )
            }) ?: return@synchronized null
            val successor = snapshot.firstOrNull { it.id == plan.successorId && !it.reconnecting }
                ?: continue
            val frame = Frame(FrameType.HOST_TRANSFER, HOST_ID, 0, HostTransferCodec.encode(plan))
            if (!sendTo(successor, frame)) {
                dropClient(successor, "房主交接发送失败")
                continue
            }
            preparedTransfer = plan
            snapshot.filter { it !== successor && !it.reconnecting }.forEach { client ->
                if (!sendTo(client, frame)) dropClient(client, "房主交接发送失败")
            }
            return@synchronized plan
        }
        null
    }

    /** 幂等停机：先落 running 再关 socket，唤醒所有阻塞在 accept/read/receive 的线程。 */
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        running = false
        scheduler.shutdownNow()
        runCatching { server.close() }
            .onFailure { TransportLog.w("关闭信令端口失败: ${it.message}", it) }
        runCatching { udp.close() }
            .onFailure { TransportLog.w("关闭音频端口失败: ${it.message}", it) }
        val targets = synchronized(lock) {
            val all = clients.values.toList()
            clients.clear()
            all
        }
        if (preparedTransfer == null) {
            for (c in targets) {
                runCatching {
                    sendTo(c, Frame(FrameType.LEAVE, HOST_ID, 0, ByteArray(0)))
                }
            }
        }
        for (c in targets) {
            runCatching { c.link.socket.close() }
        }
    }

    private fun ByteArray.toTokenKey(): String = joinToString("") { "%02x".format(it.toInt() and 0xFF) }
}
