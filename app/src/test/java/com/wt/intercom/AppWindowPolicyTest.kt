package com.wt.intercom

import org.junit.Assert.assertTrue
import org.junit.Test

class AppWindowPolicyTest {

    @Test
    fun `应用窗口默认保持屏幕常亮`() {
        assertTrue(AppWindowPolicy.keepScreenOn)
    }
}
