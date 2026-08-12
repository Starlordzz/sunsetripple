package com.wt.intercom.transport.bluetooth

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.Roster
import java.net.ServerSocket
import java.net.Socket
import java.io.ByteArrayOutputStream
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BluetoothTransportContractTest {

    private class Recorder : BluetoothRoomTransportListener {
        val frames = CopyOnWriteArrayList<Frame>()
        val rosters = CopyOnWriteArrayList<Roster>()
        val disconnects = CopyOnWriteArrayList<String>()
        override fun onFrame(frame: Frame) { frames.add(frame) }
        override fun onRoster(roster: Roster) { rosters.add(roster) }
        override fun onDisconnected(reason: String) { disconnects.add(reason) }
    }

    private class SocketConnection(private val socket: Socket) : BluetoothConnection {
        override val remoteAddress: String = socket.remoteSocketAddress.toString()
        override val input get() = socket.getInputStream()
        override val output get() = socket.getOutputStream()
        override fun close() = socket.close()
    }

    private class LoopbackServer : BluetoothConnectionServer {
        private val socket = ServerSocket(0)
        override fun accept(): BluetoothConnection = SocketConnection(socket.accept())
        override fun close() = socket.close()
        fun connectSocket(): Socket = Socket("127.0.0.1", socket.localPort)
        fun connect(): BluetoothConnection = SocketConnection(connectSocket())
    }

    private class RecordingConnection : BluetoothConnection {
        override val remoteAddress = "test"
        private val inputWriter = PipedOutputStream()
        override val input = PipedInputStream(inputWriter)
        override val output = ByteArrayOutputStream()
        val closed = AtomicBoolean(false)
        override fun close() {
            closed.set(true)
            input.close()
            inputWriter.close()
        }
    }

    private class ClosingRaceServer(
        private val connection: BluetoothConnection,
    ) : BluetoothConnectionServer {
        val acceptEntered = CountDownLatch(1)
        val releaseAccept = CountDownLatch(1)
        override fun accept(): BluetoothConnection {
            acceptEntered.countDown()
            releaseAccept.await()
            return connection
        }
        override fun close() = Unit
    }

    private val closeables = mutableListOf<AutoCloseable>()

    @After
    fun tearDown() {
        closeables.reversed().forEach { runCatching { it.close() } }
    }

    @Test
    fun `客户端 JOIN 后双方成员表为 0 和 1`() {
        val room = room()
        val client = room.client("成员一")

        await("双方收到两人成员表") {
            room.hostRecorder.rosters.lastOrNull()?.members?.size == 2 &&
                client.recorder.rosters.lastOrNull()?.members?.size == 2
        }

        assertEquals(listOf(0, 1), room.hostRecorder.rosters.last().members.map { it.id })
        assertEquals(1, client.recorder.rosters.last().yourId)
    }

    @Test
    fun `第二位成员获得 ID 2`() {
        val room = room()
        room.client("成员一")
        val second = room.client("成员二")

        await("第二位成员收到三人成员表") { second.recorder.rosters.lastOrNull()?.members?.size == 3 }

        assertEquals(2, second.recorder.rosters.last().yourId)
        assertEquals(listOf(0, 1, 2), second.recorder.rosters.last().members.map { it.id })
    }

    @Test
    fun `成员离开后复用最小空闲 ID`() {
        val room = room()
        val first = room.client("成员一")
        room.client("成员二")
        await("三人入房") { room.hostRecorder.rosters.lastOrNull()?.members?.size == 3 }

        first.transport.close()
        await("首位成员离开") { room.hostRecorder.rosters.lastOrNull()?.members?.map { it.id } == listOf(0, 2) }
        val replacement = room.client("替补")
        await("替补收到成员表") { replacement.recorder.rosters.isNotEmpty() }

        assertEquals(1, replacement.recorder.rosters.last().yourId)
    }

    @Test
    fun `第 7 人被拒且既有成员不受影响`() {
        val room = room()
        val admitted = List(5) { room.client("成员${it + 1}") }
        await("房间达到六人上限") { room.hostRecorder.rosters.lastOrNull()?.members?.size == 6 }

        val seventh = room.client("第七人")
        await("第七人收到断线") { seventh.recorder.disconnects.isNotEmpty() }

        assertEquals(listOf(0, 1, 2, 3, 4, 5), room.hostRecorder.rosters.last().members.map { it.id })
        assertTrue(admitted.all { it.recorder.disconnects.isEmpty() })
    }

    @Test
    fun `畸形帧只断开该连接`() {
        val room = room()
        val bad = room.server.connect()
        closeables += AutoCloseable { bad.close() }
        bad.output.apply {
            write(Frame(FrameType.JOIN, 0, 0, "异常成员".toByteArray()).encode())
            flush()
        }
        await("异常成员先完成入房") { room.hostRecorder.rosters.lastOrNull()?.members?.size == 2 }

        bad.output.apply {
            write(byteArrayOf(99, 1, 0, 0, 0, 0))
            flush()
        }
        await("异常成员被移除") { room.hostRecorder.rosters.lastOrNull()?.members?.size == 1 }
        val healthy = room.client("正常成员")
        await("主机继续接受新成员") { healthy.recorder.rosters.isNotEmpty() }

        assertEquals(1, healthy.recorder.rosters.last().yourId)
    }

    @Test
    fun `首帧不是 JOIN 的连接被拒绝`() {
        val room = room()
        val bad = room.server.connectSocket()
        closeables += AutoCloseable { bad.close() }

        bad.getOutputStream().apply {
            write(Frame(FrameType.AUDIO, 9, 0, byteArrayOf(1)).encode())
            flush()
        }

        bad.soTimeout = 3_000
        assertEquals(-1, bad.getInputStream().read())
        assertEquals(1, room.hostRecorder.rosters.last().members.size)
    }

    @Test
    fun `close 与 accept 返回竞态时仍关闭新连接`() {
        val connection = RecordingConnection()
        val server = ClosingRaceServer(connection)
        val host = BluetoothHostTransport("主机", Recorder()) { server }
        closeables += AutoCloseable { host.close() }
        host.start()
        assertTrue(server.acceptEntered.await(1, TimeUnit.SECONDS))

        host.close()
        server.releaseAccept.countDown()

        try {
            await("accept 返回的连接被关闭") { connection.closed.get() }
        } finally {
            connection.close()
        }
    }

    @Test
    fun `客户端连接中 close 后工厂返回的连接仍被关闭`() {
        val connection = RecordingConnection()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val client = BluetoothClientTransport("成员", Recorder()) {
            entered.countDown()
            release.await()
            connection
        }
        val startThread = Thread { runCatching { client.start() } }
        startThread.start()
        assertTrue(entered.await(1, TimeUnit.SECONDS))

        client.close()
        release.countDown()
        startThread.join(1_000)

        assertTrue(connection.closed.get())
        assertTrue(!startThread.isAlive)
    }

    @Test
    fun `sendTo 只把帧发给目标成员`() {
        val room = room()
        val first = room.client("成员一")
        val second = room.client("成员二")
        await("三人入房") { second.recorder.rosters.lastOrNull()?.members?.size == 3 }
        first.recorder.frames.clear()
        second.recorder.frames.clear()

        room.host.sendTo(2, Frame(FrameType.AUDIO, 0, 7, byteArrayOf(1)))
        await("目标成员收到定向帧") { second.recorder.frames.any { it.seq == 7 } }

        assertTrue(first.recorder.frames.none { it.seq == 7 })
    }

    @Test
    fun `主机使用连接分配的成员 ID 而不信任客户端帧头`() {
        val room = room()
        val client = room.client("成员一")
        await("成员完成入房") { client.recorder.rosters.isNotEmpty() }

        client.transport.sendTo(0, Frame(FrameType.PTT_STATE, 99, 8, byteArrayOf(1)))
        await("主机收到 PTT 状态") { room.hostRecorder.frames.any { it.seq == 8 } }

        assertEquals(1, room.hostRecorder.frames.first { it.seq == 8 }.senderId)
    }

    @Test
    fun `主机关闭后所有客户端收到断线`() {
        val room = room()
        val clients = List(3) { room.client("成员$it") }
        await("四人入房") { room.hostRecorder.rosters.lastOrNull()?.members?.size == 4 }

        room.host.close()
        await("所有客户端感知主机关闭") { clients.all { it.recorder.disconnects.isNotEmpty() } }
    }

    private data class ClientHandle(
        val transport: BluetoothClientTransport,
        val recorder: Recorder,
    )

    private inner class RoomHarness(
        val server: LoopbackServer,
        val host: BluetoothHostTransport,
        val hostRecorder: Recorder,
    ) {
        fun client(nickname: String): ClientHandle {
            val recorder = Recorder()
            val transport = BluetoothClientTransport(nickname, recorder) { server.connect() }
            closeables += AutoCloseable { transport.close() }
            transport.start()
            return ClientHandle(transport, recorder)
        }
    }

    private fun room(): RoomHarness {
        val server = LoopbackServer()
        val recorder = Recorder()
        val host = BluetoothHostTransport("主机", recorder) { server }
        closeables += AutoCloseable { host.close() }
        host.start()
        return RoomHarness(server, host, recorder)
    }

    private fun await(what: String, timeoutMs: Long = 3_000, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (System.nanoTime() < deadline) {
            if (condition()) return
            Thread.sleep(10)
        }
        throw AssertionError("等待超时：$what")
    }
}
