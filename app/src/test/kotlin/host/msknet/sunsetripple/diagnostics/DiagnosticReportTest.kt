package host.msknet.sunsetripple.diagnostics

import host.msknet.sunsetripple.audio.AudioQualitySnapshot
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticReportTest {
    @Test
    fun reportRedactsAddressesAndTokens() {
        val report = DiagnosticReport.create(
            appVersion = "alpha.5",
            androidApi = 35,
            roomType = "WIFI",
            connected = false,
            memberCount = 2,
            audioQuality = AudioQualitySnapshot(receivedFrames = 20, concealedFrames = 2),
            recentErrors = listOf("peer 192.168.49.1 at AA:BB:CC:DD:EE:FF token abcdefghijklmnopqrstuvwxyz123456"),
        ).encode()

        assertFalse(report.contains("192.168.49.1"))
        assertFalse(report.contains("AA:BB:CC:DD:EE:FF"))
        assertFalse(report.contains("abcdefghijklmnopqrstuvwxyz123456"))
        assertTrue(report.contains("redacted"))
    }
}
