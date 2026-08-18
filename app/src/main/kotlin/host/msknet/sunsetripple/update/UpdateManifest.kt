package host.msknet.sunsetripple.update

import java.security.KeyFactory
import java.security.MessageDigest
import java.security.PublicKey
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import java.net.URI
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class UpdateManifest(
    val versionCode: Int,
    val versionName: String,
    val channel: String,
    val minimumVersionCode: Int,
    val packageName: String,
    val apkUrl: String,
    val apkSha256: String,
    val certificateSha256: String,
    val summary: String,
    val signature: String = "",
)

enum class UpdateChannel { STABLE, PRERELEASE }

sealed interface ManifestVerification {
    data class Valid(val manifest: UpdateManifest) : ManifestVerification
    data class Invalid(val reason: String) : ManifestVerification
}

object UpdateManifestCodec {
    private val json = Json {
        ignoreUnknownKeys = false
        explicitNulls = false
        encodeDefaults = false
    }

    fun decode(raw: String): UpdateManifest = json.decodeFromString(raw)
    fun encode(manifest: UpdateManifest): String = json.encodeToString(manifest)
    fun signingPayload(manifest: UpdateManifest): ByteArray =
        encode(manifest.copy(signature = "")).toByteArray(Charsets.UTF_8)
}

class UpdateManifestVerifier(
    publicKeyBase64: String,
    private val expectedPackageName: String,
) {
    private val publicKey: PublicKey = KeyFactory.getInstance("EC").generatePublic(
        X509EncodedKeySpec(Base64.getDecoder().decode(publicKeyBase64)),
    )

    fun verify(
        rawManifest: String,
        installedVersionCode: Int,
        channel: UpdateChannel,
    ): ManifestVerification {
        val manifest = runCatching { UpdateManifestCodec.decode(rawManifest) }
            .getOrElse { return ManifestVerification.Invalid("更新清单格式无效") }
        if (manifest.packageName != expectedPackageName) {
            return ManifestVerification.Invalid("更新包名不匹配")
        }
        if (manifest.versionCode < manifest.minimumVersionCode) {
            return ManifestVerification.Invalid("更新清单版本范围无效")
        }
        if (manifest.versionName.isBlank() || manifest.summary.isBlank()) {
            return ManifestVerification.Invalid("更新清单内容不完整")
        }
        if (!isSha256(manifest.apkSha256) || !isSha256(manifest.certificateSha256)) {
            return ManifestVerification.Invalid("更新清单摘要格式无效")
        }
        if (!isHttpsUrl(manifest.apkUrl)) {
            return ManifestVerification.Invalid("更新下载地址无效")
        }
        if (channel == UpdateChannel.STABLE && manifest.channel != "stable") {
            return ManifestVerification.Invalid("稳定通道不接受测试版本")
        }
        if (!verifySignature(manifest)) {
            return ManifestVerification.Invalid("更新清单签名无效")
        }
        if (manifest.versionCode <= installedVersionCode) {
            return ManifestVerification.Invalid("没有更高版本")
        }
        return ManifestVerification.Valid(manifest)
    }

    fun verifyApk(bytes: ByteArray, expectedSha256: String): Boolean =
        sha256(bytes).equals(expectedSha256, ignoreCase = true)

    fun verifyCertificate(certificate: ByteArray, expectedSha256: String): Boolean =
        sha256(certificate).equals(expectedSha256, ignoreCase = true)

    private fun verifySignature(manifest: UpdateManifest): Boolean = runCatching {
        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(publicKey)
        verifier.update(UpdateManifestCodec.signingPayload(manifest))
        verifier.verify(Base64.getDecoder().decode(manifest.signature))
    }.getOrDefault(false)

    private fun isHttpsUrl(value: String): Boolean = runCatching {
        val uri = URI(value)
        uri.scheme == "https" && !uri.host.isNullOrBlank()
    }.getOrDefault(false)

    private fun isSha256(value: String): Boolean = value.length == 64 && value.all { it in "0123456789abcdefABCDEF" }

    companion object {
        fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
    }
}
