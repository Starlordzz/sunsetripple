package host.msknet.sunsetripple.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class AppCoordinatorTest {
    @Test
    fun eventsPublishImmutableUiState() {
        val coordinator = AppCoordinator("device")

        coordinator.setNickname("12345678901234567")
        coordinator.setRoomRole(RoomRole.HOST)
        coordinator.setHost(true)
        coordinator.setSpeaker(false)
        coordinator.setStatus("connecting")

        assertEquals("1234567890123456", coordinator.state.value.nickname)
        assertEquals(RoomRole.HOST, coordinator.state.value.roomRole)
        assertEquals("connecting", coordinator.state.value.status)
        assertFalse(coordinator.state.value.speakerOn)
    }

    @Test
    fun roomResetPreservesUserPreferences() {
        val coordinator = AppCoordinator("device")
        coordinator.setSpeaker(false)
        coordinator.setRoomRole(RoomRole.GUEST)
        coordinator.setHost(true)

        coordinator.resetRoom("ended")

        assertEquals(RoomRole.NONE, coordinator.state.value.roomRole)
        assertFalse(coordinator.state.value.isHost)
        assertFalse(coordinator.state.value.speakerOn)
        assertEquals("ended", coordinator.state.value.status)
    }
}
