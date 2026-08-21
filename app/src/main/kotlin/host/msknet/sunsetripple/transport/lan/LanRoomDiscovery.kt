package host.msknet.sunsetripple.transport.lan

import java.io.Closeable
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 跨平台局域网/热点房间发现信标。
 * 允许 Android、iOS、HarmonyOS NEXT 设备在同属一个 Wi-Fi 或手机热点时，
 * 无需专有厂商 P2P 协议即可自动发现并加入房间。
 */
data class LanDiscoveredRoom(
    val roomName: String,
    val hostIp: String,
    val signalPort: Int,
    val memberCount: Int,
    val lastSeenTimestamp: Long = System.currentTimeMillis(),
)

object LanDiscoveryConfig {
    const val DISCOVERY_PORT = 8990
    const val BEACON_MAGIC = "SUNSET_RIPPLE_BEACON"
    const val BROADCAST_INTERVAL_MS = 1000L
    const val ROOM_EXPIRY_MS = 3500L
}

/**
 * 房主端局域网广播宣告器：周期性在子网广播房间存在信息。
 */
class LanRoomAdvertiser(
    private val roomName: String,
    private val hostIp: String,
    private val signalPort: Int,
    private val getMemberCount: () -> Int,
    private val broadcastPort: Int = LanDiscoveryConfig.DISCOVERY_PORT,
) : Closeable {

    private val running = AtomicBoolean(false)
    private var scheduler: ScheduledExecutorService? = null
    private var socket: DatagramSocket? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        val sock = DatagramSocket().apply { broadcast = true }
        socket = sock
        val executor = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "lan-advertiser").apply { isDaemon = true }
        }
        scheduler = executor
        executor.scheduleAtFixedRate(
            { sendBeacon(sock) },
            0,
            LanDiscoveryConfig.BROADCAST_INTERVAL_MS,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun sendBeacon(sock: DatagramSocket) {
        if (!running.get() || sock.isClosed) return
        try {
            val count = getMemberCount()
            val payload = "${LanDiscoveryConfig.BEACON_MAGIC}|$roomName|$hostIp|$signalPort|$count"
            val bytes = payload.toByteArray(Charsets.UTF_8)
            val packet = DatagramPacket(
                bytes,
                bytes.size,
                InetAddress.getByName("255.255.255.255"),
                broadcastPort,
            )
            sock.send(packet)
        } catch (_: Exception) {
            // 局域网广播瞬态异常忽略
        }
    }

    override fun close() {
        if (running.compareAndSet(true, false)) {
            scheduler?.shutdownNow()
            scheduler = null
            socket?.close()
            socket = null
        }
    }
}

/**
 * 客户端局域网房间扫描监听器：接收子网广播并维护活跃房间列表。
 */
class LanRoomScanner(
    private val listenPort: Int = LanDiscoveryConfig.DISCOVERY_PORT,
    private val onRoomsUpdated: (List<LanDiscoveredRoom>) -> Unit,
) : Closeable {

    private val running = AtomicBoolean(false)
    private val discovered = ConcurrentHashMap<String, LanDiscoveredRoom>()
    private var listenSocket: DatagramSocket? = null
    private var listenThread: Thread? = null
    private var cleanupExecutor: ScheduledExecutorService? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        val sock = DatagramSocket(listenPort).apply {
            broadcast = true
            soTimeout = 1000
        }
        listenSocket = sock

        listenThread = Thread({
            val buf = ByteArray(512)
            while (running.get() && !sock.isClosed) {
                try {
                    val packet = DatagramPacket(buf, buf.size)
                    sock.receive(packet)
                    val text = String(packet.data, packet.offset, packet.length, Charsets.UTF_8)
                    val parts = text.split("|")
                    if (parts.size >= 5 && parts[0] == LanDiscoveryConfig.BEACON_MAGIC) {
                        val roomName = parts[1]
                        val hostIp = parts[2]
                        val signalPort = parts[3].toIntOrNull() ?: continue
                        val memberCount = parts[4].toIntOrNull() ?: 1
                        val room = LanDiscoveredRoom(
                            roomName = roomName,
                            hostIp = hostIp,
                            signalPort = signalPort,
                            memberCount = memberCount,
                            lastSeenTimestamp = System.currentTimeMillis(),
                        )
                        val key = "$hostIp:$signalPort"
                        discovered[key] = room
                        notifyUpdate()
                    }
                } catch (_: SocketTimeoutException) {
                    // 超时后继续循环检查 running 状态
                } catch (_: Exception) {
                    // 忽略单次解析错误
                }
            }
        }, "lan-scanner-listen").apply { isDaemon = true; start() }

        cleanupExecutor = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "lan-scanner-cleanup").apply { isDaemon = true }
        }.apply {
            scheduleAtFixedRate(
                { pruneExpiredRooms() },
                LanDiscoveryConfig.ROOM_EXPIRY_MS,
                1000L,
                TimeUnit.MILLISECONDS,
            )
        }
    }

    private fun pruneExpiredRooms() {
        val now = System.currentTimeMillis()
        var changed = false
        val it = discovered.entries.iterator()
        while (it.hasNext()) {
            val entry = it.next()
            if (now - entry.value.lastSeenTimestamp > LanDiscoveryConfig.ROOM_EXPIRY_MS) {
                it.remove()
                changed = true
            }
        }
        if (changed) {
            notifyUpdate()
        }
    }

    private fun notifyUpdate() {
        onRoomsUpdated(discovered.values.toList())
    }

    override fun close() {
        if (running.compareAndSet(true, false)) {
            listenSocket?.close()
            listenSocket = null
            listenThread?.join(500)
            listenThread = null
            cleanupExecutor?.shutdownNow()
            cleanupExecutor = null
            discovered.clear()
        }
    }
}

