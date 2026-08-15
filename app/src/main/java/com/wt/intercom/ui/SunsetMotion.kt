package com.wt.intercom.ui

data class RippleMotionFrame(val scale: Float, val alpha: Float)
data class EntryRippleFrame(val scale: Float, val alpha: Float)

class EntryTransitionGate {
    private var active = false

    fun tryBegin(): Boolean {
        if (active) return false
        active = true
        return true
    }

    fun finish() {
        active = false
    }
}

object SunsetMotion {
    fun controlScale(pressed: Boolean, enabled: Boolean): Float =
        if (pressed && enabled) 0.975f else 1f

    fun rippleFrame(active: Boolean, phase: Float): RippleMotionFrame {
        if (!active) return RippleMotionFrame(scale = 1f, alpha = 0.55f)
        val progress = phase.coerceIn(0f, 1f)
        if (progress == 0f) return RippleMotionFrame(scale = 0.94f, alpha = 0.90f)
        if (progress == 1f) return RippleMotionFrame(scale = 1.06f, alpha = 0.55f)
        return RippleMotionFrame(
            scale = 0.94f + 0.12f * progress,
            alpha = 0.90f - 0.35f * progress,
        )
    }

    fun headerSunOffset(phase: Float): Float {
        val progress = phase.coerceIn(0f, 1f)
        if (progress == 0f) return -0.012f
        if (progress == 1f) return 0.012f
        return -0.012f + 0.024f * progress
    }

    fun entryRippleFrame(phase: Float): EntryRippleFrame {
        val progress = phase.coerceIn(0f, 1f)
        return EntryRippleFrame(
            scale = progress,
            alpha = 0.92f + 0.06f * progress,
        )
    }
}
