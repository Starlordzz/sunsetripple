package host.msknet.sunsetripple.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CallControlBridgeTest {

    @Test
    fun `控制动作执行后返回最新通知状态`() {
        var muted = false
        var leaves = 0
        val bridge = CallControlBridge()
        bridge.attach(
            stateProvider = { CallNotificationState("WiFi 房", CallMode.FULL_DUPLEX, micMuted = muted) },
            onControl = { muted = !muted },
            onLeave = { leaves++ },
        )

        assertEquals("取消静音", bridge.control()!!.controlLabel())
        bridge.leave()
        assertEquals(1, leaves)
    }

    @Test
    fun `清空后旧通知动作不能控制已结束会话`() {
        var controls = 0
        val bridge = CallControlBridge()
        bridge.attach(
            stateProvider = { CallNotificationState("蓝牙房", CallMode.PUSH_TO_TALK) },
            onControl = { controls++ },
            onLeave = {},
        )

        bridge.clear()

        assertNull(bridge.control())
        assertEquals(0, controls)
    }
}
