package host.msknet.sunsetripple.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class AppNavigationCoordinatorTest {
    @Test
    fun navigationPublishesTheRequestedScreen() {
        val coordinator = AppNavigationCoordinator()

        coordinator.navigateTo(Screen.ABOUT_UPDATE)

        assertEquals(Screen.ABOUT_UPDATE, coordinator.screen.value)
    }

    @Test
    fun stableAboutScreenCanBeRestored() {
        assertEquals(
            Screen.ABOUT_UPDATE,
            ScreenRestoration.restore(ScreenRestoration.save(Screen.ABOUT_UPDATE)),
        )
    }

    @Test
    fun transientScreensRestoreToHome() {
        val transientScreens = Screen.entries - Screen.HOME - Screen.ABOUT_UPDATE

        transientScreens.forEach { screen ->
            assertEquals(Screen.HOME, ScreenRestoration.restore(ScreenRestoration.save(screen)))
            assertEquals(
                ScreenRestoration.TRANSIENT_SCREEN_MESSAGE,
                ScreenRestoration.restoreState(ScreenRestoration.save(screen)).message,
            )
        }
    }

    @Test
    fun missingOrUnknownStateRestoresToHome() {
        assertEquals(Screen.HOME, ScreenRestoration.restore(null))
        assertEquals(Screen.HOME, ScreenRestoration.restore("REMOVED_SCREEN"))
        assertEquals(null, ScreenRestoration.restoreState("REMOVED_SCREEN").message)
    }
}
