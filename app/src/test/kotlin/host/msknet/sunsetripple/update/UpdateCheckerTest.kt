package host.msknet.sunsetripple.update

import org.junit.Assert.assertEquals
import org.junit.Test

class UpdateCheckerTest {
    @Test
    fun successfulCheckWithNoVersionReportsUpToDate() {
        val checker = UpdateChecker(UpdateSource { Result.success(null) })

        assertEquals(UpdateState.UpToDate, checker.check())
    }

    @Test
    fun availableVersionIsExposed() {
        val checker = UpdateChecker(UpdateSource { Result.success("0.1.0-alpha.5") })

        assertEquals(UpdateState.Available("0.1.0-alpha.5"), checker.check())
    }

    @Test
    fun sourceFailureIsExposed() {
        val checker = UpdateChecker(UpdateSource { Result.failure(IllegalStateException("offline")) })

        assertEquals(UpdateState.Failed("offline"), checker.check())
    }
}
