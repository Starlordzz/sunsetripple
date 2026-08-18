package host.msknet.sunsetripple.session

import host.msknet.sunsetripple.ui.RoomKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RoomLifecycleCoordinatorTest {
    @Test
    fun wifiReleaseClearsSessionAndDisconnects() {
        var disconnected = false
        var runtimeStops = 0
        val coordinator = RoomLifecycleCoordinator(
            disconnectWifi = { disconnected = true },
            closeBluetooth = {},
            stopCallRuntime = { runtimeStops += 1 },
        )
        val session = RoomSession("me")
        coordinator.publishSession(session, RoomKind.WIFI)

        coordinator.release()

        assertNull(coordinator.session.value)
        assertNull(coordinator.roomKind.value)
        assertTrue(disconnected)
        assertEquals(1, runtimeStops)
    }

    @Test
    fun wifiGroupCanBeKeptForHostTransfer() {
        var disconnected = false
        val coordinator = RoomLifecycleCoordinator(
            disconnectWifi = { disconnected = true },
            closeBluetooth = {},
            stopCallRuntime = {},
        )
        coordinator.publishSession(RoomSession("me"), RoomKind.WIFI)

        coordinator.release(keepWifiGroup = true)

        assertFalse(disconnected)
    }

    @Test
    fun releaseWithoutRoomStillStopsRuntimeAndIsRepeatable() {
        var runtimeStops = 0
        val coordinator = RoomLifecycleCoordinator(
            disconnectWifi = {},
            closeBluetooth = {},
            stopCallRuntime = { runtimeStops += 1 },
        )

        coordinator.release()
        coordinator.release()

        assertEquals(2, runtimeStops)
    }
}
