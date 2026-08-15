package host.msknet.sunsetripple.transport.wifi

import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.protocol.FrameStreamReader
import host.msknet.sunsetripple.protocol.FrameType
import host.msknet.sunsetripple.session.Roster
import host.msknet.sunsetripple.session.RosterCodec
import host.msknet.sunsetripple.session.MemberInfo
import host.msknet.sunsetripple.transport.ReconnectPolicy
import host.msknet.sunsetripple.transport.ResumeJoinCodec
import host.msknet.sunsetripple.transport.TransportListener
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiReconnectTest {
    private class Recorder : TransportListener {
        val rosters = CopyOnWriteArrayList<Roster>()
        val reconnecting = CopyOnWriteArrayList<Int>()
        val reconnected = CopyOnWriteArrayList<Int>()
        val failed = CopyOnWriteArrayList<Int>()
        val disconnects = CopyOnWriteArrayList<String>()
        override fun onFrame(frame: Frame) = Unit
        override fun onRoster(roster: Roster) { rosters += roster }
        override fun onMemberReconnecting(memberId: Int) { reconnecting += memberId }
        override fun onMemberReconnected(memberId: Int) { reconnected += memberId }
        override fun onMemberReconnectFailed(memberId: Int) { failed += memberId }
        override fun onDisconnected(reason: String) { disconnects += reason }
    }

    private val closeables = mutableListOf<AutoCloseable>()
    @After fun tearDown() = closeables.reversed().forEach { runCatching { it.close() } }

    @Test
    fun `主机异常断线保留成员且同 token 恢复原 ID`() {
        val recorder = Recorder()
        val host = WifiHostTransport(
            "主机", recorder, hostIp = "127.0.0.1", signalPort = 0, audioBindPort = 0,
            reconnectGraceMs = 2_000,
        ).also { it.start() }
        closeables += AutoCloseable { host.close() }
        val token = ByteArray(16) { it.toByte() }

        val first = join(host.signalPort, token, "成员一")
        assertEquals(1, nextRoster(first).yourId)
        first.close()
        await("成员进入重连中") { recorder.reconnecting == listOf(1) }
        assertTrue(recorder.rosters.last().members.any { it.id == 1 })

        val resumed = join(host.signalPort, token, "成员一")
        assertEquals(1, nextRoster(resumed).yourId)
        await("成员恢复") { recorder.reconnected == listOf(1) }
    }

    @Test
    fun `客户端断流后按三次退避重建 TCP 与 UDP 并最终结束`() {
        val server = ServerSocket(0)
        closeables += AutoCloseable { server.close() }
        val accepted = CopyOnWriteArrayList<Socket>()
        val serverThread = Thread {
            repeat(4) {
                val socket = server.accept()
                accepted += socket
                FrameStreamReader(socket.getInputStream()).readFrame()
                if (it == 0) {
                    socket.getOutputStream().apply {
                        write(
                            Frame(
                                FrameType.ROSTER,
                                0,
                                0,
                                RosterCodec.encode(
                                    1,
                                    listOf(
                                        MemberInfo(0, "主机", "127.0.0.1"),
                                        MemberInfo(1, "成员", "127.0.0.1"),
                                    ),
                                ),
                            ).encode(),
                        )
                        flush()
                    }
                }
                socket.close()
            }
        }.apply { isDaemon = true; start() }
        val recorder = Recorder()
        val udpCreations = AtomicInteger()
        val delays = CopyOnWriteArrayList<Long>()
        val client = WifiClientTransport(
            nickname = "成员",
            hostIp = "127.0.0.1",
            listener = recorder,
            signalPort = server.localPort,
            audioBindPort = 0,
            nextReconnectDelayMs = { policy: ReconnectPolicy ->
                policy.nextDelayMs()?.also(delays::add)?.let { 1L }
            },
            udpFactory = { port -> DatagramSocket(port).also { udpCreations.incrementAndGet() } },
        )
        closeables += AutoCloseable { client.close() }
        client.start()
        await("客户端完成首次入房") { recorder.rosters.isNotEmpty() }

        await("三次重连后结束") { recorder.disconnects.isNotEmpty() }

        assertEquals(4, accepted.size)
        assertEquals(4, udpCreations.get())
        assertEquals(listOf(1_000L, 2_000L, 4_000L), delays.toList())
    }

    @Test
    fun `错误 token 不复用且 close 后已排程重连不能复活`() {
        val recorder = Recorder()
        val host = WifiHostTransport(
            "主机", recorder, hostIp = "127.0.0.1", signalPort = 0, audioBindPort = 0,
            reconnectGraceMs = 2_000,
        ).also { it.start() }
        closeables += AutoCloseable { host.close() }
        val first = join(host.signalPort, ByteArray(16) { 1 }, "成员一")
        assertEquals(1, nextRoster(first).yourId)
        first.close()
        await("原成员进入宽限期") { recorder.reconnecting == listOf(1) }
        val stranger = join(host.signalPort, ByteArray(16) { 2 }, "陌生成员")
        assertEquals(2, nextRoster(stranger).yourId)

        val retryServer = ServerSocket(0)
        closeables += AutoCloseable { retryServer.close() }
        Thread {
            val socket = retryServer.accept()
            FrameStreamReader(socket.getInputStream()).readFrame()
            socket.getOutputStream().apply {
                write(
                    Frame(
                        FrameType.ROSTER,
                        0,
                        0,
                        RosterCodec.encode(
                            1,
                            listOf(
                                MemberInfo(0, "主机", "127.0.0.1"),
                                MemberInfo(1, "成员", "127.0.0.1"),
                            ),
                        ),
                    ).encode(),
                )
                flush()
            }
            socket.close()
        }.apply { isDaemon = true; start() }
        val attempts = AtomicInteger()
        val clientRecorder = Recorder()
        val client = WifiClientTransport(
            nickname = "成员",
            hostIp = "127.0.0.1",
            listener = clientRecorder,
            signalPort = retryServer.localPort,
            audioBindPort = 0,
            nextReconnectDelayMs = { policy -> policy.nextDelayMs()?.let { 100L } },
            socketFactory = { attempts.incrementAndGet(); Socket() },
        )
        closeables += AutoCloseable { client.close() }
        client.start()
        await("客户端首次入房") { clientRecorder.rosters.isNotEmpty() }
        Thread.sleep(20)
        client.close()
        Thread.sleep(150)

        assertEquals("P2P 组消失关闭后不得重建连接", 1, attempts.get())
    }

    private fun join(port: Int, token: ByteArray, nickname: String): Socket = Socket().also { socket ->
        closeables += AutoCloseable { socket.close() }
        socket.connect(InetSocketAddress("127.0.0.1", port), 2_000)
        socket.getOutputStream().apply {
            write(Frame(FrameType.JOIN, 0, 0, ResumeJoinCodec.encode(token, nickname)).encode())
            flush()
        }
    }

    private fun nextRoster(socket: Socket): Roster {
        socket.soTimeout = 3_000
        return RosterCodec.decode(FrameStreamReader(socket.getInputStream()).readFrame()!!.payload)
    }

    private fun await(what: String, timeoutMs: Long = 3_000, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (System.nanoTime() < deadline) {
            if (condition()) return
            Thread.sleep(5)
        }
        throw AssertionError("等待超时：$what")
    }
}
