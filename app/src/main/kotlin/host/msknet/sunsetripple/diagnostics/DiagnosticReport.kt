package host.msknet.sunsetripple.diagnostics

import host.msknet.sunsetripple.audio.AudioQualitySnapshot
import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class DiagnosticReport(
    val schemaVersion: Int = 1,
    val generatedAt: String,
    val appVersion: String,
    val androidApi: Int,
    val roomType: String,
    val connected: Boolean,
    val memberCount: Int,
    val receivedFrames: Long,
    val concealedFrames: Long,
    val underruns: Long,
    val averageRecoveryMillis: Long,
    val networkQuality: String,
    val recentErrors: List<String>,
) {
    fun encode(): String = JSON.encodeToString(this)

    fun issueSummary(): String = buildString {
        appendLine("App: $appVersion")
        appendLine("Android API: $androidApi")
        appendLine("Room: $roomType")
        appendLine("Connected: $connected; members: $memberCount")
        appendLine("Network: $networkQuality; loss: $concealedFrames/${receivedFrames + concealedFrames}")
        appendLine("Underruns: $underruns; average recovery: ${averageRecoveryMillis}ms")
        if (recentErrors.isNotEmpty()) appendLine("Errors: ${recentErrors.joinToString()}")
    }

    companion object {
        private val JSON = Json { prettyPrint = true }

        fun create(
            appVersion: String,
            androidApi: Int,
            roomType: String,
            connected: Boolean,
            memberCount: Int,
            audioQuality: AudioQualitySnapshot,
            recentErrors: List<String>,
        ): DiagnosticReport = DiagnosticReport(
            generatedAt = Instant.now().toString(),
            appVersion = appVersion,
            androidApi = androidApi,
            roomType = roomType,
            connected = connected,
            memberCount = memberCount,
            receivedFrames = audioQuality.receivedFrames,
            concealedFrames = audioQuality.concealedFrames,
            underruns = audioQuality.underruns,
            averageRecoveryMillis = audioQuality.averageRecoveryMillis,
            networkQuality = audioQuality.networkQuality.name,
            recentErrors = recentErrors.map(DiagnosticSanitizer::sanitize).filter(String::isNotBlank).takeLast(20),
        )
    }
}

object DiagnosticSanitizer {
    private val macAddress = Regex("(?i)\\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\\b")
    private val ipv4Address = Regex("\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b")
    private val longToken = Regex("\\b[A-Za-z0-9+/=_-]{24,}\\b")

    fun sanitize(value: String): String = value
        .replace(macAddress, "[redacted-address]")
        .replace(ipv4Address, "[redacted-address]")
        .replace(longToken, "[redacted-token]")
        .take(400)
}
