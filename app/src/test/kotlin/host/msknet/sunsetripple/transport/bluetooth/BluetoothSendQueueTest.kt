package host.msknet.sunsetripple.transport.bluetooth

import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.protocol.FrameType
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BluetoothSendQueueTest {

    @Test
    fun `3 个音频帧按入队顺序取出`() {
        val queue = BluetoothSendQueue(audioCapacity = 3)
        repeat(3) { queue.offer(frame(FrameType.AUDIO, it)) }

        assertEquals(listOf(0, 1, 2), List(3) { queue.take()!!.seq })
    }

    @Test
    fun `第 4 个音频入队时丢最旧音频`() {
        val queue = BluetoothSendQueue(audioCapacity = 3)
        repeat(4) { queue.offer(frame(FrameType.AUDIO, it)) }

        assertEquals(listOf(1, 2, 3), List(3) { queue.take()!!.seq })
    }

    @Test
    fun `音频溢出不丢信令且保持剩余帧顺序`() {
        val queue = BluetoothSendQueue(audioCapacity = 3)
        listOf(
            frame(FrameType.AUDIO, 0),
            frame(FrameType.ROSTER, 10),
            frame(FrameType.AUDIO, 1),
            frame(FrameType.PTT_STATE, 11),
            frame(FrameType.AUDIO, 2),
            frame(FrameType.LEAVE, 12),
            frame(FrameType.AUDIO, 3),
        ).forEach(queue::offer)

        val actual = List(6) { queue.take()!! }.map { it.type to it.seq }
        assertEquals(
            listOf(
                FrameType.ROSTER to 10,
                FrameType.AUDIO to 1,
                FrameType.PTT_STATE to 11,
                FrameType.AUDIO to 2,
                FrameType.LEAVE to 12,
                FrameType.AUDIO to 3,
            ),
            actual,
        )
    }

    @Test
    fun `close 唤醒阻塞的 take 并返回 null`() {
        val queue = BluetoothSendQueue(audioCapacity = 3)
        val result = AtomicReference<Frame?>()
        val taker = Thread { result.set(queue.take()) }

        taker.start()
        awaitBlocked(taker)
        queue.close()
        taker.join(1_000)

        assertFalse("take 线程应在 close 后退出", taker.isAlive)
        assertNull(result.get())
    }

    @Test
    fun `close 后先排空已有帧再返回 null`() {
        val queue = BluetoothSendQueue(audioCapacity = 3)
        queue.offer(frame(FrameType.ROSTER, 10))

        queue.close()

        assertEquals(10, queue.take()!!.seq)
        assertNull(queue.take())
    }

    private fun frame(type: FrameType, seq: Int) = Frame(type, senderId = 1, seq, byteArrayOf())

    private fun awaitBlocked(thread: Thread) {
        repeat(100) {
            if (thread.state == Thread.State.WAITING) return
            Thread.sleep(5)
        }
        assertTrue("take 应在空队列上阻塞", thread.state == Thread.State.WAITING)
    }
}
