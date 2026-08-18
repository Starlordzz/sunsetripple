package host.msknet.sunsetripple.update

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import host.msknet.sunsetripple.BuildConfig
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class GithubUpdateService(
    private val context: Context,
    private val manifestUrl: String,
    private val publicKeyBase64: String,
    private val channel: UpdateChannel,
) : UpdateService {
    private var verifiedManifest: UpdateManifest? = null
    private var verifiedApk: File? = null

    override fun check(): UpdateState {
        if (publicKeyBase64.isBlank()) return UpdateState.Failed("更新验证公钥未配置")
        return runCatching {
            val verifier = verifier()
            val raw = getBytes(manifestUrl, MAX_MANIFEST_BYTES).toString(Charsets.UTF_8)
            when (val result = verifier.verify(raw, BuildConfig.VERSION_CODE, channel)) {
                is ManifestVerification.Invalid -> {
                    if (result.reason == "没有更高版本") UpdateState.UpToDate else UpdateState.Failed(result.reason)
                }
                is ManifestVerification.Valid -> {
                    verifiedManifest = result.manifest
                    verifiedApk = null
                    UpdateState.Available(result.manifest.versionName, result.manifest.summary)
                }
            }
        }.getOrElse { UpdateState.Failed(it.userMessage("检查更新失败")) }
    }

    override fun download(): UpdateActionResult {
        val manifest = verifiedManifest ?: return UpdateActionResult.Failed("请先检查更新")
        return runCatching {
            val bytes = getBytes(manifest.apkUrl, MAX_APK_BYTES)
            val verifier = verifier()
            check(verifier.verifyApk(bytes, manifest.apkSha256)) { "APK 哈希校验失败" }
            val directory = File(context.cacheDir, "updates").apply { mkdirs() }
            val file = File(directory, "SunsetRipple-${manifest.versionCode}.apk")
            file.writeBytes(bytes)
            verifyArchive(file, manifest, verifier)
            verifiedApk = file
            UpdateActionResult.Completed(manifest.versionName)
        }.getOrElse { UpdateActionResult.Failed(it.userMessage("下载更新失败")) }
    }

    override fun install(): UpdateActionResult {
        val file = verifiedApk ?: return UpdateActionResult.Failed("更新包尚未完成校验")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !context.packageManager.canRequestPackageInstalls()) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return UpdateActionResult.PermissionRequired
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, APK_MIME_TYPE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        return UpdateActionResult.ConfirmationOpened
    }

    private fun verifier() = UpdateManifestVerifier(publicKeyBase64, context.packageName)

    private fun verifyArchive(file: File, manifest: UpdateManifest, verifier: UpdateManifestVerifier) {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageArchiveInfo(
                file.absolutePath,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageArchiveInfo(file.absolutePath, PackageManager.GET_SIGNING_CERTIFICATES)
        } ?: error("无法读取更新包")
        check(packageInfo.packageName == context.packageName) { "APK 包名校验失败" }
        val certificates = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.signingInfo?.apkContentsSigners.orEmpty().map { it.toByteArray() }
        } else {
            @Suppress("DEPRECATION")
            packageInfo.signatures.orEmpty().map { it.toByteArray() }
        }
        check(certificates.any { verifier.verifyCertificate(it, manifest.certificateSha256) }) {
            "APK 签名证书校验失败"
        }
    }

    private fun getBytes(url: String, maxBytes: Int): ByteArray {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 20_000
        connection.instanceFollowRedirects = true
        connection.setRequestProperty("Accept", "application/json, application/vnd.android.package-archive")
        try {
            check(connection.responseCode in 200..299) { "HTTP ${connection.responseCode}" }
            val declaredLength = connection.contentLengthLong
            check(declaredLength < 0 || declaredLength <= maxBytes) { "下载内容超过大小限制" }
            return connection.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    check(total <= maxBytes) { "下载内容超过大小限制" }
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun Throwable.userMessage(prefix: String): String = "$prefix：${message ?: javaClass.simpleName}"

    companion object {
        private const val MAX_MANIFEST_BYTES = 128 * 1024
        private const val MAX_APK_BYTES = 256 * 1024 * 1024
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }
}
