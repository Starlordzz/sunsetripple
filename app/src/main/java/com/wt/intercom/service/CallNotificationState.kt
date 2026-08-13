package com.wt.intercom.service

enum class CallMode { FULL_DUPLEX, PUSH_TO_TALK }

data class CallNotificationState(
    val label: String,
    val mode: CallMode,
    val micMuted: Boolean = false,
    val pttActive: Boolean = false,
    val audioFocusInterrupted: Boolean = false,
) {
    fun controlLabel(): String? {
        if (audioFocusInterrupted) return null
        return when (mode) {
            CallMode.FULL_DUPLEX -> if (micMuted) "取消静音" else "静音"
            CallMode.PUSH_TO_TALK -> if (pttActive) "停止说话" else "开始说话"
        }
    }
}

internal fun initialNotificationState(
    live: CallNotificationState?,
    fallback: CallNotificationState,
): CallNotificationState = live ?: fallback
