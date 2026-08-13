package com.wt.intercom.audio

class MicGate {
    var userMuted: Boolean = false
        private set

    var focusInterrupted: Boolean = false
        private set

    val effectiveMuted: Boolean
        get() = userMuted || focusInterrupted

    fun setUserMuted(muted: Boolean) {
        userMuted = muted
    }

    fun setFocusInterrupted(interrupted: Boolean) {
        focusInterrupted = interrupted
    }
}
