package host.msknet.sunsetripple.update

import org.junit.Assert.assertEquals
import org.junit.Test

class AboutUpdateCoordinatorTest {
    @Test
    fun checkPublishesCheckerResult() {
        val coordinator = AboutUpdateCoordinator(
            CheckOnlyUpdateService(UpdateChecker(UpdateSource { Result.success("0.1.0-alpha.6") })),
        )

        coordinator.check()

        assertEquals(UpdateState.Available("0.1.0-alpha.6"), coordinator.state.value)
    }

    @Test
    fun adapterFailureCanBePublished() {
        val coordinator = AboutUpdateCoordinator(
            CheckOnlyUpdateService(UpdateChecker(UpdateSource { Result.success(null) })),
        )

        coordinator.reportFailure("没有可用的浏览器")

        assertEquals(UpdateState.Failed("没有可用的浏览器"), coordinator.state.value)
    }
}
