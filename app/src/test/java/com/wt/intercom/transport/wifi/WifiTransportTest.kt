package com.wt.intercom.transport.wifi

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.Roster
import com.wt.intercom.transport.Transport
import com.wt.intercom.transport.TransportListener
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Host/Client 传输是纯 java.net 代码（不碰 Android API），可在 JVM 上用回环 socket 端到端测试。
 * 端口全部由构造参数注入（生产默认 8988/8989），测试用 0 让系统分配，避免与真机常量冲突。
 */
class WifiTransportTest {

    private class Recorder : TransportListener {
        val frames = CopyOnWriteArrayList<Frame>()
        val rosters = CopyOnWriteArrayList<Roster>()
        val disconnects = CopyOnWriteArrayList<String>()
        override fun onFrame(frame: Frame) { frames.add(frame) }
        override fun onRoster(roster: Roster) { rosters.add(roster) }
        override fun onDisconnected(reason: String) { disconnects.add(reason) }
    }

    private val closeables = mutableListOf<() -> Unit>()

    @After
    fun tearDown() {
        closeables.reversed().forEach { runCatching { it() } }
    }

    private fun <T : Transport> track(t: T): T = t.also { closeables.add { it.close() } }

    private fun trackSocket(s: Socket): Socket = s.also { closeables.add { it.close() } }

    /** 轮询等待条件成立，最多 [timeoutMs] 毫秒。 */
    private fun await(timeoutMs: Long = 3000, what: String, cond: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (System.nanoTime() < deadline) {
            if (cond()) return
            Thread.sleep(10)
        }
        throw AssertionError("等待超时：$what")
    }

    private fun startHost(hostRec: Recorder, hostIp: String = "127.0.0.1"): WifiHostTransport =
        track(
            WifiHostTransport(
                nickname = "主机",
                listener = hostRec,
                hostIp = hostIp,
                signalPort = 0,
                audioBindPort = 0,
            )
        ).also { it.start() }

    /** 连上主机并发一帧 JOIN 的裸 socket 成员，用来把房间填到指定人数。 */
    private fun joinRaw(host: WifiHostTransport, nickname: String): Socket {
        val s = trackSocket(Socket())
        s.connect(InetSocketAddress("127.0.0.1", host.signalPort), 2000)
        s.getOutputStream().apply {
            write(Frame(FrameType.JOIN, 0, 0, nickname.toByteArray(Charsets.UTF_8)).encode())
            flush()
        }
        return s
    }

    /** 断言主机已断开这条连接：正常收 FIN 读到 -1，被复位则抛 SocketException，都算断开；超时即失败。 */
    private fun assertDropped(s: Socket, what: String) {
        s.soTimeout = 3000
        val read = try {
            s.getInputStream().read()
        } catch (e: SocketException) {
            -1
        }
        assertEquals("$what：连接应被主机关闭", -1, read)
    }

    @Test
    fun `客户端入房后双方拿到一致成员表`() {
        val hostRec = Recorder()
        val host = startHost(hostRec)
        val cliRec = Recorder()
        val client = track(
            WifiClientTransport("小明", "127.0.0.1", cliRec, signalPort = host.signalPort, audioBindPort = 0)
        )
        client.start()

        await(what = "客户端收到成员表") { cliRec.rosters.isNotEmpty() }
        val roster = cliRec.rosters.last()
        assertEquals(1, roster.yourId)
        assertEquals(listOf(0, 1), roster.members.map { it.id })
        assertEquals(listOf("主机", "小明"), roster.members.map { it.nickname })

        await(what = "主机成员表含 2 人") { hostRec.rosters.lastOrNull()?.members?.size == 2 }
        assertEquals(0, hostRec.rosters.last().yourId)
    }

    @Test
    fun `音频帧经 UDP 从客户端直达主机`() {
        val hostRec = Recorder()
        val host = track(
            WifiHostTransport("主机", hostRec, hostIp = "127.0.0.1", signalPort = 0, audioBindPort = 0)
        )
        host.start()
        val cliRec = Recorder()
        val client = track(
            WifiClientTransport(
                "小明", "127.0.0.1", cliRec,
                signalPort = host.signalPort,
                audioBindPort = 0,
                peerAudioPort = host.audioPort,
            )
        )
        client.start()
        await(what = "客户端收到成员表") { cliRec.rosters.isNotEmpty() }

        client.broadcast(Frame(FrameType.AUDIO, 1, 7, byteArrayOf(1, 2, 3)))

        await(what = "主机收到音频帧") { hostRec.frames.any { it.type == FrameType.AUDIO } }
        val audio = hostRec.frames.first { it.type == FrameType.AUDIO }
        assertEquals(1, audio.senderId)
        assertEquals(7, audio.seq)
        assertEquals(listOf<Byte>(1, 2, 3), audio.payload.toList())
    }

    @Test
    fun `客户端断开后主机产出 LEAVE 帧并更新成员表`() {
        val hostRec = Recorder()
        val host = startHost(hostRec)
        val cliRec = Recorder()
        val client = WifiClientTransport("小明", "127.0.0.1", cliRec, signalPort = host.signalPort, audioBindPort = 0)
        client.start()
        await(what = "主机成员表含 2 人") { hostRec.rosters.lastOrNull()?.members?.size == 2 }

        client.close()

        await(what = "主机产出 LEAVE") { hostRec.frames.any { it.type == FrameType.LEAVE } }
        assertEquals(1, hostRec.frames.first { it.type == FrameType.LEAVE }.senderId)
        await(what = "主机成员表回到 1 人") { hostRec.rosters.lastOrNull()?.members?.size == 1 }
    }

    @Test
    fun `首帧不是 JOIN 的连接被主机关闭`() {
        val hostRec = Recorder()
        val host = startHost(hostRec)
        val raw = trackSocket(Socket())
        raw.connect(InetSocketAddress("127.0.0.1", host.signalPort), 2000)
        raw.getOutputStream().apply {
            write(Frame(FrameType.AUDIO, 9, 0, ByteArray(4)).encode())
            flush()
        }
        assertDropped(raw, "首帧非 JOIN")
        assertEquals(1, hostRec.rosters.last().members.size)
    }

    /**
     * 硬指标 1 的判别用例：入房首帧就畸形（未知类型 99）时该连接必须被断掉，主机继续服务别人。
     * 把 `clientLoop` 的首帧读换回裸 `readFrame()` 本例即失败——IAE 穿透打死该线程，
     * socket 永远不关，下面的 read 会超时而不是读到 -1。
     */
    @Test
    fun `首帧畸形的连接被断开且主机继续服务`() {
        val hostRec = Recorder()
        val host = startHost(hostRec)
        val raw = trackSocket(Socket())
        raw.connect(InetSocketAddress("127.0.0.1", host.signalPort), 2000)
        raw.getOutputStream().apply {
            write(byteArrayOf(99, 1, 0, 0, 0, 0))   // 未知帧类型：Frame.decode 抛 IllegalArgumentException
            flush()
        }

        assertDropped(raw, "首帧畸形")

        val cliRec = Recorder()
        val client = track(
            WifiClientTransport("小明", "127.0.0.1", cliRec, signalPort = host.signalPort, audioBindPort = 0)
        )
        client.start()
        await(what = "新客户端入房") { cliRec.rosters.isNotEmpty() }
        assertEquals(listOf(0, 1), cliRec.rosters.last().members.map { it.id })
        assertEquals(2, hostRec.rosters.last().members.size)
    }

    /**
     * 规格：房间上限 6 人（含建房者）。第 7 人必须在门口被拒——放他进表会让全员的
     * ROSTER 编码超 512B，成员表当场冻结（既有成员的 UI 从此不再更新）。
     */
    @Test
    fun `房间满员后拒绝新成员且既有成员表不受影响`() {
        val hostRec = Recorder()
        val host = startHost(hostRec)
        // 4 个裸 socket + 1 个真客户端 = 5 名成员，加主机正好坐满 6 人。昵称取满 60 字节逼近载荷上限。
        repeat(4) { i -> joinRaw(host, "c$i".padEnd(60, 'x')) }
        val cliRec = Recorder()
        val client = track(
            WifiClientTransport(
                "last".padEnd(60, 'x'), "127.0.0.1", cliRec,
                signalPort = host.signalPort, audioBindPort = 0,
            )
        )
        client.start()
        await(what = "房间坐满 6 人") { hostRec.rosters.lastOrNull()?.members?.size == 6 }
        await(what = "末位成员拿到 6 人成员表") { cliRec.rosters.lastOrNull()?.members?.size == 6 }

        val seventh = joinRaw(host, "第七人")

        assertDropped(seventh, "第 7 人应被拒")
        // 前 6 人的成员表原样健在，也没人被踢
        assertEquals(listOf(0, 1, 2, 3, 4, 5), hostRec.rosters.last().members.map { it.id })
        assertEquals(listOf(0, 1, 2, 3, 4, 5), cliRec.rosters.last().members.map { it.id })
        assertTrue("既有成员不该收到断开通知", cliRec.disconnects.isEmpty())
    }

    /** 硬指标 1：接收循环用 readFrameSafely，畸形帧（未知类型）不得炸线程，只断该对端。 */
    @Test
    fun `畸形帧只断开该对端且主机继续服务`() {
        val hostRec = Recorder()
        val host = startHost(hostRec)
        val raw = trackSocket(Socket())
        raw.connect(InetSocketAddress("127.0.0.1", host.signalPort), 2000)
        val out = raw.getOutputStream()
        out.write(Frame(FrameType.JOIN, 0, 0, "捣乱".toByteArray()).encode())
        out.flush()
        await(what = "捣乱者入房") { hostRec.rosters.lastOrNull()?.members?.size == 2 }

        // 未知帧类型 99：FrameStreamReader.readFrame 内部 Frame.decode 抛 IllegalArgumentException
        out.write(byteArrayOf(99, 1, 0, 0, 0, 0))
        out.flush()

        await(what = "主机踢掉畸形对端") { hostRec.rosters.lastOrNull()?.members?.size == 1 }

        // 主机仍能接受新连接
        val cliRec = Recorder()
        val client = track(
            WifiClientTransport("小明", "127.0.0.1", cliRec, signalPort = host.signalPort, audioBindPort = 0)
        )
        client.start()
        await(what = "新客户端入房") { cliRec.rosters.isNotEmpty() }
        assertNotNull(cliRec.rosters.last())
        assertTrue(hostRec.rosters.last().members.size == 2)
    }

    @Test
    fun `主机关闭后客户端收到断开通知`() {
        val hostRec = Recorder()
        val host = startHost(hostRec)
        val cliRec = Recorder()
        val client = track(
            WifiClientTransport("小明", "127.0.0.1", cliRec, signalPort = host.signalPort, audioBindPort = 0)
        )
        client.start()
        await(what = "客户端收到成员表") { cliRec.rosters.isNotEmpty() }

        host.close()

        await(what = "客户端感知断开") { cliRec.disconnects.isNotEmpty() }
    }
}
