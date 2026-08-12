package com.wt.intercom.session

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class BluetoothMixPlannerTest {

    @Test
    fun `发给成员2的混音排除成员2`() {
        val result = BluetoothMixPlanner.plan(
            memberIds = setOf(1, 2),
            remotePcm = mapOf(1 to shortArrayOf(100), 2 to shortArrayOf(200)),
            hostPcm = shortArrayOf(10),
            frameSamples = 1,
        )

        assertArrayEquals(shortArrayOf(300), result.hostPlayback)
        assertArrayEquals(shortArrayOf(210), result.downlinks.getValue(1))
        assertArrayEquals(shortArrayOf(110), result.downlinks.getValue(2))
    }

    @Test
    fun `没有其他说话者时给成员发送静音`() {
        val result = BluetoothMixPlanner.plan(
            memberIds = setOf(1),
            remotePcm = mapOf(1 to shortArrayOf(100, 0)),
            hostPcm = null,
            frameSamples = 2,
        )

        assertArrayEquals(shortArrayOf(100, 0), result.hostPlayback)
        assertArrayEquals(shortArrayOf(0, 0), result.downlinks.getValue(1))
    }

    @Test
    fun `混音使用饱和截断`() {
        val result = BluetoothMixPlanner.plan(
            memberIds = setOf(1, 2),
            remotePcm = mapOf(1 to shortArrayOf(1), 2 to shortArrayOf(30_000)),
            hostPcm = shortArrayOf(30_000),
            frameSamples = 1,
        )

        assertArrayEquals(shortArrayOf(32767), result.downlinks.getValue(1))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `帧长不一致时拒绝规划`() {
        BluetoothMixPlanner.plan(
            memberIds = setOf(1),
            remotePcm = mapOf(1 to shortArrayOf(1)),
            hostPcm = shortArrayOf(1, 2),
            frameSamples = 1,
        )
    }
}
