package com.wt.intercom.transport.nearby

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NearbyRoomManagerTest {

    private class FakePort : NearbyConnectionsPort {
        var callback: NearbyConnectionsListener? = null
        var advertisingCount = 0
        var discoveryCount = 0
        var stopCount = 0
        val requested = mutableListOf<String>()
        override fun setListener(listener: NearbyConnectionsListener?) { callback = listener }
        override fun startAdvertising(localName: String) { advertisingCount++ }
        override fun startDiscovery() { discoveryCount++ }
        override fun requestConnection(localName: String, endpointId: String) { requested += endpointId }
        override fun acceptConnection(endpointId: String) = Unit
        override fun rejectConnection(endpointId: String) = Unit
        override fun sendBytes(endpointIds: List<String>, bytes: ByteArray) = Unit
        override fun disconnect(endpointId: String) = Unit
        override fun stopAll() { stopCount++ }
    }

    @Test
    fun `无 GMS 时明确报错且不开始广告或发现`() {
        val port = FakePort()
        val manager = NearbyRoomManager(port, gmsAvailable = { false })

        manager.startAdvertising("主机")
        manager.startDiscovery()

        assertEquals("此设备缺少 Google Play 服务", manager.lastError.value)
        assertEquals(0, port.advertisingCount)
        assertEquals(0, port.discoveryCount)
    }

    @Test
    fun `仅检查 GMS 可用性不会启动 SDK 操作`() {
        val port = FakePort()
        val manager = NearbyRoomManager(port, gmsAvailable = { true })

        assertTrue(manager.ensureAvailable())

        assertEquals(0, port.advertisingCount)
        assertEquals(0, port.discoveryCount)
        assertFalse(manager.advertising.value)
        assertFalse(manager.discovering.value)
        assertEquals(null, manager.lastError.value)
    }

    @Test
    fun `发现端点去重并跟踪连接状态与失败`() {
        val port = FakePort()
        val manager = NearbyRoomManager(port, gmsAvailable = { true })
        manager.startDiscovery()

        port.callback!!.onEndpointFound(NearbyEndpoint("one", "房间一"))
        port.callback!!.onEndpointFound(NearbyEndpoint("one", "房间一更新"))
        assertEquals(listOf("one"), manager.endpoints.value.map { it.id })

        manager.requestConnection("我", "one")
        assertEquals(NearbyEndpointState.CONNECTING, manager.endpoints.value.single().state)
        port.callback!!.onConnectionResult("one", true)
        assertEquals(NearbyEndpointState.CONNECTED, manager.endpoints.value.single().state)

        port.callback!!.onOperationFailed("Nearby 扫描", IllegalStateException("不可用"))
        assertTrue(manager.lastError.value.orEmpty().contains("不可用"))
        assertFalse(manager.discovering.value)
    }

    @Test
    fun `拒绝与断线移除端点且关闭幂等清空状态`() {
        val port = FakePort()
        val manager = NearbyRoomManager(port, gmsAvailable = { true })
        manager.startAdvertising("主机")
        manager.startDiscovery()
        port.callback!!.onEndpointFound(NearbyEndpoint("one", "房间一"))
        manager.requestConnection("我", "one")
        port.callback!!.onConnectionResult("one", false)
        assertTrue(manager.endpoints.value.isEmpty())

        port.callback!!.onEndpointFound(NearbyEndpoint("two", "房间二"))
        port.callback!!.onDisconnected("two")
        assertTrue(manager.endpoints.value.isEmpty())

        manager.close()
        manager.close()
        assertEquals(1, port.stopCount)
        assertFalse(manager.advertising.value)
        assertFalse(manager.discovering.value)
        assertTrue(manager.endpoints.value.isEmpty())
    }

    @Test
    fun `交接端口时停止发现并解除 manager 监听但仍可由 transport 接管`() {
        val port = FakePort()
        val manager = NearbyRoomManager(port, gmsAvailable = { true })
        manager.startDiscovery()
        port.callback!!.onEndpointFound(NearbyEndpoint("one", "房间一"))

        val handedOff = manager.handoffPort()
        manager.onOperationFailed("迟到回调", IllegalStateException("不应显示"))

        assertTrue(handedOff === port)
        assertEquals(1, port.stopCount)
        assertEquals(null, port.callback)
        assertFalse(manager.discovering.value)
        assertTrue(manager.endpoints.value.isEmpty())
        assertEquals(null, manager.lastError.value)

        val replacement = object : NearbyConnectionsListener {}
        handedOff.setListener(replacement)
        assertTrue(port.callback === replacement)
    }
}
