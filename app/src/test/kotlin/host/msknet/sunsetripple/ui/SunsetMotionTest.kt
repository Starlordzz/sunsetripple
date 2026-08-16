package host.msknet.sunsetripple.ui

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
    fun `房间页面从触点持续展开且铺满后不再退场`() {
        assertEquals(EntryRippleFrame(scale = 0f, alpha = 1f), SunsetMotion.entryRippleFrame(0f))

        val middle = SunsetMotion.entryRippleFrame(0.5f)
        assertEquals(0.5f, middle.scale)
        assertEquals(1f, middle.alpha)

        assertEquals(EntryRippleFrame(scale = 1f, alpha = 1f), SunsetMotion.entryRippleFrame(1f))
    }

    @Test
    fun `房间布局在展开时只收拢横幅而不二次淡入位移`() {
        val start = SunsetMotion.roomTransitionFrame(0f)
        val middle = SunsetMotion.roomTransitionFrame(0.5f)
        val end = SunsetMotion.roomTransitionFrame(1f)

        assertEquals(214f, start.headerHeightDp)
        assertTrue(middle.headerHeightDp in 166f..214f)
        assertEquals(166f, end.headerHeightDp)
        listOf(start, middle, end).forEach { frame ->
            assertEquals(1f, frame.contentAlpha)
            assertEquals(0f, frame.contentTranslationDp)
        }
    }

    @Test
    fun `遮罩活动期间页面在其下方直接交换而不叠加第二套转场`() {
        val method = SunsetMotion::class.java.methods.firstOrNull {
            it.name == "useImmediateScreenSwap" && it.parameterTypes.contentEquals(arrayOf(Float::class.javaPrimitiveType))
        }
        assertTrue("缺少遮罩期间直接交换页面的时序策略", method != null)
        method ?: return

        assertFalse(method.invoke(SunsetMotion, 0f) as Boolean)
        assertTrue(method.invoke(SunsetMotion, SunsetMotion.ENTRY_COVER_PHASE) as Boolean)
        assertTrue(method.invoke(SunsetMotion, 0.99f) as Boolean)
        assertTrue(method.invoke(SunsetMotion, 1f) as Boolean)
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
