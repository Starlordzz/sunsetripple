package com.wt.intercom.audio

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class MixerTest {

    @Test
    fun `两路逐样本相加`() {
        val out = Mixer.mix(listOf(shortArrayOf(100, -200), shortArrayOf(50, 300)))
        assertArrayEquals(shortArrayOf(150, 100), out)
    }

    @Test
    fun `正向饱和截断到 32767`() {
        val out = Mixer.mix(listOf(shortArrayOf(30000), shortArrayOf(30000)))
        assertArrayEquals(shortArrayOf(32767), out)
    }

    @Test
    fun `负向饱和截断到 -32768`() {
        val out = Mixer.mix(listOf(shortArrayOf(-30000), shortArrayOf(-30000)))
        assertArrayEquals(shortArrayOf(-32768), out)
    }

    @Test
    fun `单路原样返回`() {
        val out = Mixer.mix(listOf(shortArrayOf(1, 2, 3)))
        assertArrayEquals(shortArrayOf(1, 2, 3), out)
    }

    @Test
    fun `三路混合`() {
        val out = Mixer.mix(listOf(shortArrayOf(10), shortArrayOf(20), shortArrayOf(30)))
        assertArrayEquals(shortArrayOf(60), out)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `帧长不一致时拒绝混音_首路较短`() {
        Mixer.mix(listOf(shortArrayOf(1), shortArrayOf(1, 2, 3)))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `帧长不一致时拒绝混音_首路较长`() {
        Mixer.mix(listOf(shortArrayOf(1, 2, 3), shortArrayOf(1)))
    }
}
