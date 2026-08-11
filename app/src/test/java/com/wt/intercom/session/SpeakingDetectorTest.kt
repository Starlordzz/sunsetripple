package com.wt.intercom.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpeakingDetectorTest {

    private val loud = ShortArray(320) { 3000 }
    private val quiet = ShortArray(320) { 10 }

    @Test
    fun `响帧触发说话状态`() {
        val d = SpeakingDetector()
        d.feed(loud)
        assertTrue(d.isSpeaking())
    }

    @Test
    fun `静音帧不触发`() {
        val d = SpeakingDetector()
        d.feed(quiet)
        assertFalse(d.isSpeaking())
    }

    @Test
    fun `余晖保持后衰减归零`() {
        val d = SpeakingDetector(hangoverFrames = 3)
        d.feed(loud)
        repeat(3) {
            assertTrue(d.isSpeaking())
            d.feed(quiet)
        }
        assertFalse(d.isSpeaking())
    }
}
