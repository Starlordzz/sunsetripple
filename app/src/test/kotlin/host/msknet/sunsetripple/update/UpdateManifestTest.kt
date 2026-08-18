package host.msknet.sunsetripple.update

import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateManifestTest {
    @Test
    fun signingPayloadUsesStableFieldOrderAndOmitsEmptySignature() {
        assertEquals(
            """{"versionCode":6,"versionName":"0.1.0-alpha.5","channel":"prerelease","minimumVersionCode":5,"packageName":"host.msknet.sunsetripple","apkUrl":"https://example.invalid/app.apk","apkSha256":"${UpdateManifestVerifier.sha256("apk".toByteArray())}","certificateSha256":"${UpdateManifestVerifier.sha256("certificate".toByteArray())}","summary":"Alpha 5"}""",
            UpdateManifestCodec.signingPayload(sampleManifest()).toString(Charsets.UTF_8),
        )
    }

    @Test
    fun signedManifestAndApkHashAreVerified() {
        val keys = KeyPairGenerator.getInstance("EC").apply { initialize(256) }.generateKeyPair()
        val unsigned = sampleManifest()
        val signer = Signature.getInstance("SHA256withECDSA").apply {
            initSign(keys.private)
            update(UpdateManifestCodec.signingPayload(unsigned))
        }
        val manifest = unsigned.copy(signature = Base64.getEncoder().encodeToString(signer.sign()))
        val verifier = UpdateManifestVerifier(
            Base64.getEncoder().encodeToString(keys.public.encoded),
            "host.msknet.sunsetripple",
        )

        val result = verifier.verify(UpdateManifestCodec.encode(manifest), 5, UpdateChannel.PRERELEASE)

        assertTrue(result is ManifestVerification.Valid)
        assertTrue(verifier.verifyApk("apk".toByteArray(), UpdateManifestVerifier.sha256("apk".toByteArray())))
        assertFalse(verifier.verifyApk("tampered".toByteArray(), manifest.apkSha256))
    }

    @Test
    fun stableChannelRejectsPrerelease() {
        val keys = KeyPairGenerator.getInstance("EC").apply { initialize(256) }.generateKeyPair()
        val verifier = UpdateManifestVerifier(
            Base64.getEncoder().encodeToString(keys.public.encoded),
            "host.msknet.sunsetripple",
        )

        assertEquals(
            ManifestVerification.Invalid("稳定通道不接受测试版本"),
            verifier.verify(UpdateManifestCodec.encode(sampleManifest()), 5, UpdateChannel.STABLE),
        )
    }

    private fun sampleManifest() = UpdateManifest(
        versionCode = 6,
        versionName = "0.1.0-alpha.5",
        channel = "prerelease",
        minimumVersionCode = 5,
        packageName = "host.msknet.sunsetripple",
        apkUrl = "https://example.invalid/app.apk",
        apkSha256 = UpdateManifestVerifier.sha256("apk".toByteArray()),
        certificateSha256 = UpdateManifestVerifier.sha256("certificate".toByteArray()),
        summary = "Alpha 5",
    )
}
