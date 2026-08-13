package com.wt.intercom.transport.nearby

import com.wt.intercom.protocol.Frame
import com.wt.intercom.protocol.FrameType
import com.wt.intercom.session.Roster
import com.wt.intercom.session.RosterCodec
import com.wt.intercom.transport.TransportListener
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NearbyRoomTransportTest {

    private class Recorder : TransportListener {
        val frames = CopyOnWriteArrayList<Frame>()
        val rosters = CopyOnWriteArrayList<Roster>()
        val disconnects = CopyOnWriteArrayList<String>()
        override fun onFrame(frame: Frame) { frames += frame }
        override fun onRoster(roster: Roster) { rosters += roster }
        override fun onDisconnected(reason: String) { disconnects += reason }
    }

    private class FakePort : NearbyConnectionsPort {
        var callback: NearbyConnectionsListener? = null
        val accepted = mutableListOf<String>()
        val rejected = mutableListOf<String>()
        val requested = mutableListOf<Pair<String, String>>()
        val sent = mutableListOf<Pair<List<String>, ByteArray>>()
        val disconnected = mutableListOf<String>()
        var advertisingName: String? = null
        var discoveryCount = 0
        override fun setListener(listener: NearbyConnectionsListener?) { callback = listener }
        override fun startAdvertising(localName: String) { advertisingName = localName }
        override fun startDiscovery() { discoveryCount++ }
        override fun requestConnection(localName: String, endpointId: String) {
            requested += localName to endpointId
        }
        override fun acceptConnection(endpointId: String) { accepted += endpointId }
        override fun rejectConnection(endpointId: String) { rejected += endpointId }
        override fun sendBytes(endpointIds: List<String>, bytes: ByteArray) { sent += endpointIds to bytes }
        override fun disconnect(endpointId: String) { disconnected += endpointId }
        override fun stopAll() = Unit
    }

    @Test
    fun `主机 JOIN 后分配 ID1 并下发个性化成员表`() {
        val port = FakePort()
        val recorder = Recorder()
        val transport = NearbyRoomTransport.host("主机", recorder, port)
        transport.start()

        port.callback!!.onConnectionInitiated(NearbyEndpoint("endpoint-1", "成员一"))
        port.callback!!.onConnectionResult("endpoint-1", true)
        port.callback!!.onBytesReceived(
            "endpoint-1",
            Frame(FrameType.JOIN, 0, 0, "成员一".toByteArray()).encode(),
        )

        assertEquals("主机", port.advertisingName)
        assertEquals(listOf("endpoint-1"), port.accepted)
        assertEquals(listOf(0, 1), recorder.rosters.last().members.map { it.id })
        val rosterFrame = Frame.decode(port.sent.last().second)
        assertEquals(listOf("endpoint-1"), port.sent.last().first)
        assertEquals(1, RosterCodec.decode(rosterFrame.payload).yourId)
        assertEquals("endpoint-1", RosterCodec.decode(rosterFrame.payload).members.last().ip)
    }

    @Test
    fun `主机 AUDIO 直接发给所有已连接成员且不经本地回送`() {
        val port = FakePort()
        val recorder = Recorder()
        val transport = NearbyRoomTransport.host("主机", recorder, port)
        transport.start()
        for (id in 1..2) {
            val endpoint = "endpoint-$id"
            port.callback!!.onConnectionInitiated(NearbyEndpoint(endpoint, "成员$id"))
            port.callback!!.onConnectionResult(endpoint, true)
            port.callback!!.onBytesReceived(
                endpoint,
                Frame(FrameType.JOIN, 0, 0, "成员$id".toByteArray()).encode(),
            )
        }
        port.sent.clear()

        transport.broadcast(Frame(FrameType.AUDIO, 0, 7, byteArrayOf(9)))

        assertEquals(listOf("endpoint-1", "endpoint-2"), port.sent.single().first.sorted())
        assertEquals(7, Frame.decode(port.sent.single().second).seq)
        assertTrue(recorder.frames.isEmpty())
    }

    @Test
    fun `客户端收到成员表后补齐网状连接并直发 AUDIO`() {
        val port = FakePort()
        val recorder = Recorder()
        val transport = NearbyRoomTransport.guest(
            nickname = "成员一",
            listener = recorder,
            port = port,
            hostEndpointId = "host-endpoint",
        )
        transport.start()

        assertEquals("成员一", port.advertisingName)
        assertEquals(1, port.discoveryCount)
        assertEquals(listOf("成员一" to "host-endpoint"), port.requested)

        port.callback!!.onConnectionInitiated(NearbyEndpoint("host-endpoint", "主机"))
        port.callback!!.onConnectionResult("host-endpoint", true)
        assertEquals(FrameType.JOIN, Frame.decode(port.sent.last().second).type)

        port.callback!!.onEndpointFound(NearbyEndpoint("endpoint-2", "成员二"))
        val roster = RosterCodec.encode(
            1,
            listOf(
                com.wt.intercom.session.MemberInfo(0, "主机", "host"),
                com.wt.intercom.session.MemberInfo(1, "成员一", "endpoint-1"),
                com.wt.intercom.session.MemberInfo(2, "成员二", "endpoint-2"),
            ),
        )
        port.callback!!.onBytesReceived(
            "host-endpoint",
            Frame(FrameType.ROSTER, 0, 0, roster).encode(),
        )
        assertTrue(port.requested.contains("成员一" to "endpoint-2"))

        port.callback!!.onConnectionInitiated(NearbyEndpoint("endpoint-2", "成员二"))
        port.callback!!.onConnectionResult("endpoint-2", true)
        port.sent.clear()
        transport.broadcast(Frame(FrameType.AUDIO, 1, 9, byteArrayOf(7)))

        assertEquals(listOf("endpoint-2", "host-endpoint"), port.sent.single().first.sorted())
        assertEquals(9, Frame.decode(port.sent.single().second).seq)
        assertEquals(1, recorder.rosters.last().yourId)
    }

    @Test
    fun `客户端不会把 AUDIO 发给成员表之外的已接受端点`() {
        val port = FakePort()
        val recorder = Recorder()
        val transport = NearbyRoomTransport.guest(
            nickname = "成员一",
            listener = recorder,
            port = port,
            hostEndpointId = "host-endpoint",
        )
        transport.start()
        port.callback!!.onConnectionInitiated(NearbyEndpoint("host-endpoint", "主机"))
        port.callback!!.onConnectionResult("host-endpoint", true)
        port.callback!!.onConnectionInitiated(NearbyEndpoint("unknown-endpoint", "未知设备"))
        port.callback!!.onConnectionResult("unknown-endpoint", true)
        val roster = RosterCodec.encode(
            1,
            listOf(
                com.wt.intercom.session.MemberInfo(0, "主机", "host"),
                com.wt.intercom.session.MemberInfo(1, "成员一", "endpoint-1"),
            ),
        )
        port.callback!!.onBytesReceived(
            "host-endpoint",
            Frame(FrameType.ROSTER, 0, 0, roster).encode(),
        )
        port.sent.clear()

        transport.broadcast(Frame(FrameType.AUDIO, 1, 4, byteArrayOf(7)))

        assertEquals(listOf("host-endpoint"), port.sent.single().first)
    }

    @Test
    fun `客户端只接受主机成员表且新成员表会移除离房端点`() {
        val port = FakePort()
        val recorder = Recorder()
        val transport = NearbyRoomTransport.guest(
            nickname = "成员一",
            listener = recorder,
            port = port,
            hostEndpointId = "host-endpoint",
        )
        transport.start()
        for ((endpointId, name) in listOf("host-endpoint" to "主机", "endpoint-2" to "成员二")) {
            port.callback!!.onConnectionInitiated(NearbyEndpoint(endpointId, name))
            port.callback!!.onConnectionResult(endpointId, true)
        }
        sendRoster(port, "host-endpoint", memberIds = listOf(0, 1, 2))
        val rosterCount = recorder.rosters.size

        sendRoster(port, "endpoint-2", memberIds = listOf(0, 2))
        assertEquals("非主机伪造的成员表必须忽略", rosterCount, recorder.rosters.size)

        sendRoster(port, "host-endpoint", memberIds = listOf(0, 1))
        assertTrue("离房成员的底层端点必须主动断开", "endpoint-2" in port.disconnected)
        port.sent.clear()
        transport.broadcast(Frame(FrameType.AUDIO, 1, 5, byteArrayOf(8)))

        assertEquals(listOf("host-endpoint"), port.sent.single().first)
    }

    @Test
    fun `客户端在首份成员表前与主机断开也会幂等结束会话`() {
        val port = FakePort()
        val recorder = Recorder()
        NearbyRoomTransport.guest(
            nickname = "成员一",
            listener = recorder,
            port = port,
            hostEndpointId = "host-endpoint",
        ).start()
        port.callback!!.onConnectionInitiated(NearbyEndpoint("host-endpoint", "主机"))
        port.callback!!.onConnectionResult("host-endpoint", true)

        port.callback!!.onDisconnected("host-endpoint")
        port.callback!!.onDisconnected("host-endpoint")

        assertEquals(listOf("Nearby 房间已结束"), recorder.disconnects)
    }

    @Test
    fun `人数上限含主机且成员离开后复用最小空闲 ID`() {
        val port = FakePort()
        val recorder = Recorder()
        NearbyRoomTransport.host("主机", recorder, port).start()

        for (id in 1..5) joinHost(port, "endpoint-$id", "成员$id")
        joinHost(port, "endpoint-6", "第七台")

        assertEquals(listOf(0, 1, 2, 3, 4, 5), recorder.rosters.last().members.map { it.id })
        assertEquals(listOf("endpoint-6"), port.rejected)
        assertTrue("满员端点不得先接受再拒绝", "endpoint-6" !in port.accepted)

        port.callback!!.onDisconnected("endpoint-2")
        joinHost(port, "endpoint-new", "新成员")

        assertEquals(2, recorder.rosters.last().members.first { it.ip == "endpoint-new" }.id)
    }

    @Test
    fun `畸形帧只断发送端点且合法帧身份绑定端点分配 ID`() {
        val port = FakePort()
        val recorder = Recorder()
        NearbyRoomTransport.host("主机", recorder, port).start()
        joinHost(port, "endpoint-1", "成员一")
        joinHost(port, "endpoint-2", "成员二")

        port.callback!!.onBytesReceived("endpoint-1", byteArrayOf(1, 2, 3))
        val validWithTrailingByte =
            Frame(FrameType.AUDIO, 1, 1, byteArrayOf(4)).encode() + byteArrayOf(99)
        port.callback!!.onBytesReceived("endpoint-1", validWithTrailingByte)
        port.callback!!.onBytesReceived(
            "endpoint-2",
            Frame(FrameType.AUDIO, 99, 8, byteArrayOf(7)).encode(),
        )

        assertEquals(listOf("endpoint-1", "endpoint-1"), port.disconnected)
        assertEquals(2, recorder.frames.single().senderId)
        assertEquals(8, recorder.frames.single().seq)
    }

    private fun joinHost(port: FakePort, endpointId: String, nickname: String) {
        port.callback!!.onConnectionInitiated(NearbyEndpoint(endpointId, nickname))
        port.callback!!.onConnectionResult(endpointId, true)
        port.callback!!.onBytesReceived(
            endpointId,
            Frame(FrameType.JOIN, 0, 0, nickname.toByteArray()).encode(),
        )
    }

    private fun sendRoster(port: FakePort, fromEndpointId: String, memberIds: List<Int>) {
        val payload = RosterCodec.encode(
            yourId = 1,
            members = memberIds.map { id ->
                val endpointId = when (id) {
                    0 -> "host"
                    1 -> "endpoint-1"
                    else -> "endpoint-$id"
                }
                com.wt.intercom.session.MemberInfo(id, "成员$id", endpointId)
            },
        )
        port.callback!!.onBytesReceived(
            fromEndpointId,
            Frame(FrameType.ROSTER, 0, 0, payload).encode(),
        )
    }
}
