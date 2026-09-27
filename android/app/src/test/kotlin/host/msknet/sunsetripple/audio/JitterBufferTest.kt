package host.msknet.sunsetripple.audio

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [JitterBuffer] 的纯逻辑单测：预缓冲、乱序重排、丢包判定、16 位序号回绕、
 * 积压上限、迟到帧、断流重对齐。不依赖 Android framework，普通 JVM 单测即可跑。
 *
 * 最要紧的一条是「丢包」与「欠载」必须返回不同结果——调用方靠这个区分
 * 「用 Opus PLC 补一帧」和「这一拍干脆不出声」，混在一起就会在正常网络抖动下
 * 补出金属音。
 */
class JitterBufferTest {

    private val a = byteArrayOf(1)
    private val b = byteArrayOf(2)
    private val c = byteArrayOf(3)
    private val d = byteArrayOf(4)

    /** 断言取到了完整包，并把它取出来。 */
    private fun packet(result: PollResult): ByteArray {
        assertTrue("期望 PollResult.Packet，实际是 $result", result is PollResult.Packet)
        return (result as PollResult.Packet).data
    }

    @Test
    fun pollReturnsNotReadyWhilePrebuffering() {
        val jb = JitterBuffer()

        jb.put(0, a)
        assertTrue("只攒了 1 帧不该出帧", jb.poll() is PollResult.NotReady)

        jb.put(1, b)
        assertTrue("只攒了 2 帧不该出帧", jb.poll() is PollResult.NotReady)

        assertFalse("没出过帧就不该是 started", jb.hasStarted())
        assertEquals("NotReady 不能吃掉缓冲里的包", 2, jb.pendingCount())
    }

    @Test
    fun pollStartsEmittingOncePrebufferIsFilled() {
        val jb = JitterBuffer()
        jb.put(0, a)
        jb.put(1, b)
        jb.put(2, c)
        assertFalse(jb.hasStarted())

        assertArrayEquals(a, packet(jb.poll()))
        assertTrue("攒满 prebufferFrames 后应当进入 started", jb.hasStarted())
        assertArrayEquals(b, packet(jb.poll()))
        assertArrayEquals(c, packet(jb.poll()))

        assertEquals(0, jb.pendingCount())
    }

    @Test
    fun outOfOrderArrivalIsReturnedInSequence() {
        val jb = JitterBuffer()

        // 网络乱序：7 先到，然后才是 5、6。
        jb.put(7, c)
        jb.put(5, a)
        jb.put(6, b)

        assertArrayEquals("必须先吐最小序号，而不是先到的包", a, packet(jb.poll()))
        assertArrayEquals(b, packet(jb.poll()))
        assertArrayEquals(c, packet(jb.poll()))
        assertTrue(jb.poll() is PollResult.NotReady)
    }

    @Test
    fun missingSequenceReportsLostInsteadOfNotReady() {
        val jb = JitterBuffer()
        jb.put(0, a)
        jb.put(1, b)
        jb.put(3, d) // 2 号包在网络上丢了

        assertArrayEquals(a, packet(jb.poll()))
        assertArrayEquals(b, packet(jb.poll()))

        val atGap = jb.poll()
        assertTrue("缺包位置必须报 Lost（调用方据此走 PLC），实际是 $atGap", atGap is PollResult.Lost)
        assertArrayEquals("Lost 之后要能继续吐后面的包", d, packet(jb.poll()))
        assertEquals(0, jb.pendingCount())
    }

    @Test
    fun consecutiveMissingSequencesReportOneLostEach() {
        val jb = JitterBuffer()
        jb.put(0, a)
        jb.put(1, b)
        jb.put(5, d) // 2、3、4 连着丢

        assertArrayEquals(a, packet(jb.poll()))
        assertArrayEquals(b, packet(jb.poll()))
        assertTrue(jb.poll() is PollResult.Lost)
        assertTrue(jb.poll() is PollResult.Lost)
        assertTrue(jb.poll() is PollResult.Lost)
        assertArrayEquals("连续 Lost 不能把 next 推过头", d, packet(jb.poll()))
    }

    @Test
    fun sequenceWrapAroundIsTreatedAsMonotonic() {
        val jb = JitterBuffer()

        // 16 位序号绕回：65534 → 65535 → 0 → 1 是连续递增的一串。
        jb.put(65534, a)
        jb.put(65535, b)
        jb.put(0, c)
        jb.put(1, d)

        assertArrayEquals(a, packet(jb.poll()))
        assertArrayEquals(b, packet(jb.poll()))
        assertArrayEquals("回绕后的 0 号不能被当成更大的序号而卡住", c, packet(jb.poll()))
        assertArrayEquals(d, packet(jb.poll()))

        assertEquals(0, jb.pendingCount())
        assertTrue("回绕帧吐完后是欠载，不是丢包", jb.poll() is PollResult.NotReady)
    }

    @Test
    fun lateWrappedSequenceIsDroppedAfterStart() {
        val jb = JitterBuffer()
        jb.put(65534, a)
        jb.put(65535, b)
        jb.put(0, c)

        assertArrayEquals(a, packet(jb.poll()))
        assertArrayEquals(b, packet(jb.poll())) // next 已经推进到回绕后的 0 号

        jb.put(65535, d) // 回绕前的老包迟到

        assertEquals("已播过的位置不能再入队", 1, jb.pendingCount())
        assertArrayEquals(c, packet(jb.poll()))
        assertTrue(jb.poll() is PollResult.NotReady)
    }

    @Test
    fun bufferCapDropsOldestPackets() {
        val jb = JitterBuffer()

        for (seq in 0 until 15) jb.put(seq, byteArrayOf(seq.toByte()))

        assertEquals("积压不能超过 maxBuffer(10)", 10, jb.pendingCount())
        for (seq in 5 until 15) {
            assertArrayEquals("应当丢最旧、保最新", byteArrayOf(seq.toByte()), packet(jb.poll()))
        }
        assertEquals(0, jb.pendingCount())
    }

    @Test
    fun latePacketAfterStartIsDropped() {
        val jb = JitterBuffer()
        jb.put(0, a)
        jb.put(1, b)
        jb.put(2, c)

        assertArrayEquals(a, packet(jb.poll())) // next = 1

        jb.put(0, d) // 已播过的序号迟到：必须丢弃

        assertEquals("迟到帧不能重新入队", 2, jb.pendingCount())
        assertArrayEquals(b, packet(jb.poll()))
        assertArrayEquals(c, packet(jb.poll()))
        assertEquals(0, jb.pendingCount())
        assertTrue("迟到的 0 号不能被重新播出", jb.poll() is PollResult.NotReady)
    }

    @Test
    fun duplicateSequenceIsStoredOnce() {
        val jb = JitterBuffer()

        jb.put(0, a)
        jb.put(0, b) // 同一序号重传
        assertEquals("同一序号只能占一个位置", 1, jb.pendingCount())

        jb.put(1, c)
        jb.put(2, d)

        val frames = generateSequence { (jb.poll() as? PollResult.Packet)?.data }.toList()
        assertEquals("重传不该多吐一帧", 3, frames.size)
        assertArrayEquals(d, frames[2])
    }

    @Test
    fun resetReturnsToUnstartedState() {
        val jb = JitterBuffer()
        jb.put(0, a)
        jb.put(1, b)
        jb.put(2, c)
        assertArrayEquals(a, packet(jb.poll()))
        assertTrue(jb.hasStarted())

        jb.reset()

        assertFalse(jb.hasStarted())
        assertEquals(0, jb.pendingCount())
        assertTrue("reset 后要重新走预缓冲", jb.poll() is PollResult.NotReady)
        assertTrue(jb.poll() is PollResult.NotReady)
    }

    @Test
    fun resetAllowsReuseFromNewSequenceBase() {
        val jb = JitterBuffer()
        jb.put(0, a)
        jb.put(1, b)
        jb.put(2, c)
        assertArrayEquals(a, packet(jb.poll()))
        assertArrayEquals(b, packet(jb.poll()))

        jb.reset()

        // 新一路流又从 0 开始：不能因为旧状态把 0 当成迟到帧。
        jb.put(0, a)
        jb.put(1, b)
        jb.put(2, c)
        assertFalse(jb.hasStarted())
        assertArrayEquals(a, packet(jb.poll()))
        assertArrayEquals(b, packet(jb.poll()))
        assertArrayEquals(c, packet(jb.poll()))
    }

    @Test
    fun underrunReturnsNotReadyWithoutAdvancingNext() {
        val jb = JitterBuffer()
        jb.put(0, a)
        jb.put(1, b)
        jb.put(2, c)
        assertArrayEquals(a, packet(jb.poll()))
        assertArrayEquals(b, packet(jb.poll()))
        assertArrayEquals(c, packet(jb.poll()))
        assertEquals(0, jb.pendingCount())

        assertTrue("吐空之后是欠载，绝不能报 Lost 让调用方补 PLC", jb.poll() is PollResult.NotReady)
        assertTrue(jb.poll() is PollResult.NotReady)
        assertTrue("欠载后仍保持 started", jb.hasStarted())

        jb.put(3, d) // next 没被欠载推进，这一帧应当正常播出
        assertArrayEquals(d, packet(jb.poll()))
    }

    @Test
    fun realignsNextAfterLongStall() {
        val jb = JitterBuffer()
        jb.put(0, a)
        jb.put(1, b)
        jb.put(2, c)
        repeat(3) { jb.poll() } // 吐完，next = 3
        assertTrue(jb.poll() is PollResult.NotReady)

        // 断流：3..19 永远补不回来了，新包直接从 20 开始。
        jb.put(20, d)
        jb.put(21, a)
        jb.put(22, b)

        assertArrayEquals(
            "断流后要跳到 firstKey，而不是连报 17 个 Lost",
            d,
            packet(jb.poll()),
        )
        assertEquals(2, jb.pendingCount())
        assertArrayEquals(a, packet(jb.poll()))
    }
}
