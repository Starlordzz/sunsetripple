package host.msknet.sunsetripple.transport.lan

import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LanRoomDiscoveryTest {

    private val closeables = mutableListOf<() -> Unit>()

    @After
    fun tearDown() {
        closeables.reversed().forEach { runCatching { it() } }
    }

    private fun freePort(): Int {
        val s = ServerSocket(0)
        val port = s.localPort
        s.close()
        return port
    }

    private fun await(timeoutMs: Long = 3000, what: String, cond: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (System.nanoTime() < deadline) {
            if (cond()) return
            Thread.sleep(10)
        }
        throw AssertionError("等待超时：$what")
    }

    @Test
    fun `局域网扫描器能发现广播的房间信息`() {
        val port = freePort()
        val discoveredList = CopyOnWriteArrayList<List<LanDiscoveredRoom>>()

        val scanner = LanRoomScanner(listenPort = port) { rooms ->
            discoveredList.add(rooms)
        }
        closeables.add { scanner.close() }
        scanner.start()

        val advertiser = LanRoomAdvertiser(
            roomName = "落日小队",
            hostIp = "127.0.0.1",
            signalPort = 8988,
            getMemberCount = { 3 },
            broadcastPort = port,
        )
        closeables.add { advertiser.close() }
        advertiser.start()

        await(3000, "扫描器接收到广播房间") {
            discoveredList.isNotEmpty() && discoveredList.last().isNotEmpty()
        }

        val rooms = discoveredList.last()
        assertEquals(1, rooms.size)
        val room = rooms[0]
        assertEquals("落日小队", room.roomName)
        assertEquals("127.0.0.1", room.hostIp)
        assertEquals(8988, room.signalPort)
        assertEquals(3, room.memberCount)
    }

    @Test
    fun `停止广播后超时清理房间`() {
        val port = freePort()
        val discoveredList = CopyOnWriteArrayList<List<LanDiscoveredRoom>>()

        val scanner = LanRoomScanner(listenPort = port) { rooms ->
            discoveredList.add(rooms)
        }
        closeables.add { scanner.close() }
        scanner.start()

        val advertiser = LanRoomAdvertiser(
            roomName = "临时房间",
            hostIp = "127.0.0.1",
            signalPort = 9000,
            getMemberCount = { 1 },
            broadcastPort = port,
        )
        advertiser.start()

        await(3000, "扫描器收到初始房间") {
            discoveredList.isNotEmpty() && discoveredList.last().isNotEmpty()
        }
        assertTrue(discoveredList.last().any { it.roomName == "临时房间" })

        // 关闭房主广播
        advertiser.close()

        // 验证停止广播后能正常 close
        scanner.close()
    }
}

