package com.wt.intercom.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SunsetMotionTest {

    @Test
    fun `启用的控件按下时轻微缩小而禁用控件保持稳定`() {
        assertEquals(0.975f, SunsetMotion.controlScale(pressed = true, enabled = true))
        assertEquals(1f, SunsetMotion.controlScale(pressed = false, enabled = true))
        assertEquals(1f, SunsetMotion.controlScale(pressed = true, enabled = false))
    }

    @Test
    fun `活动波纹随相位扩散并淡出`() {
        assertEquals(RippleMotionFrame(scale = 0.94f, alpha = 0.90f), SunsetMotion.rippleFrame(true, 0f))
        assertEquals(RippleMotionFrame(scale = 1.06f, alpha = 0.55f), SunsetMotion.rippleFrame(true, 1f))
        assertEquals(RippleMotionFrame(scale = 1f, alpha = 0.55f), SunsetMotion.rippleFrame(false, 1f))
    }

    @Test
    fun `头图太阳漂移保持在克制范围内`() {
        assertEquals(-0.012f, SunsetMotion.headerSunOffset(0f))
        assertEquals(0.012f, SunsetMotion.headerSunOffset(1f))
    }

    @Test
    fun `入房波纹从触点扩散到全屏并在末段淡出`() {
        assertEquals(EntryRippleFrame(scale = 0f, alpha = 0.88f), SunsetMotion.entryRippleFrame(0f))
        assertEquals(EntryRippleFrame(scale = 1f, alpha = 0f), SunsetMotion.entryRippleFrame(1f))
    }

    @Test
    fun `入房转场期间拒绝重复触发直到完成`() {
        val gate = EntryTransitionGate()

        assertTrue(gate.tryBegin())
        assertFalse(gate.tryBegin())
        gate.finish()
        assertTrue(gate.tryBegin())
    }
}
