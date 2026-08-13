package com.wt.intercom.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CallNotificationStateTest {

    @Test
    fun `全双工通知按当前状态提供静音切换`() {
        assertEquals("静音", CallNotificationState("WiFi 房", CallMode.FULL_DUPLEX).controlLabel())
        assertEquals(
            "取消静音",
            CallNotificationState("WiFi 房", CallMode.FULL_DUPLEX, micMuted = true).controlLabel(),
        )
    }

    @Test
    fun `蓝牙通知使用点击开始和停止说话`() {
        assertEquals("开始说话", CallNotificationState("蓝牙房", CallMode.PUSH_TO_TALK).controlLabel())
        assertEquals(
            "停止说话",
            CallNotificationState("蓝牙房", CallMode.PUSH_TO_TALK, pttActive = true).controlLabel(),
        )
    }

    @Test
    fun `只听模式不提供开始说话动作`() {
        assertNull(
            CallNotificationState(
                label = "蓝牙房",
                mode = CallMode.PUSH_TO_TALK,
                audioFocusInterrupted = true,
            ).controlLabel(),
        )
    }

    @Test
    fun `服务启动时优先采用实时会话状态`() {
        val fallback = CallNotificationState("蓝牙房", CallMode.PUSH_TO_TALK)
        val live = fallback.copy(audioFocusInterrupted = true)

        assertEquals(live, initialNotificationState(live, fallback))
        assertEquals(fallback, initialNotificationState(null, fallback))
    }
}
