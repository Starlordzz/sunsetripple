package host.msknet.sunsetripple

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * 「把签名过的更新包交给系统安装器」的平台通道实现。
 *
 * Dart 侧（`lib/core/update/update_installer.dart`）负责：拉清单、验签、下载、比对
 * SHA-256。走到这里时字节流已经可信，但**原生侧仍会再核对三项**才拉起安装器：
 *
 *   1. 包名 == 清单里的 `packageName`（`host.msknet.sunsetripple`）；
 *   2. versionCode == 清单里的 `versionCode`（防止拿旧包替换新包）；
 *   3. 签名证书 SHA-256 == 清单里的 `certificateSha256`
 *      （这是唯一能证明「这个 APK 是同一个发布密钥签出来的」的证据，
 *       换密钥就意味着用户会遇到 INSTALL_FAILED_UPDATE_INCOMPATIBLE）。
 *
 * 任何一项不符都返回错误，**不会**跳到系统安装确认框：宁可让用户重试一次，
 * 也不能让一个可疑的 APK 走到「安装」按钮前面。
 *
 * Android 8.0+ 还需要用户显式授权「安装未知应用」
 * （`REQUEST_INSTALL_PACKAGES` + `canRequestPackageInstalls()`），
 * 未授权时这里给出可读错误并引导到系统设置页。
 */
class UpdateInstallerPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "SunsetUpdate"
        private const val METHOD_CHANNEL = "host.msknet.sunsetripple/update_installer"

        /** 与 AndroidManifest.xml 里 `android:authorities="${applicationId}.update.fileprovider"` 一致。 */
        private const val FILE_PROVIDER_SUFFIX = ".update.fileprovider"

        private const val APK_MIME = "application/vnd.android.package-archive"

        const val ERROR_INVALID_ARGUMENT = "invalid_argument"
        const val ERROR_APK_REJECTED = "apk_rejected"
        const val ERROR_NOT_ALLOWED = "install_not_allowed"
        const val ERROR_INSTALL_FAILED = "install_failed"
    }

    private val channel = MethodChannel(messenger, METHOD_CHANNEL).apply {
        setMethodCallHandler(this@UpdateInstallerPlugin)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
            "openInstallPermissionSettings" -> result.success(openInstallPermissionSettings())
            "openUrl" -> openUrl(call, result)
            "installApk" -> installApk(call, result)
            else -> result.notImplemented()
        }
    }

    /** Android 8.0+ 的「安装未知应用」授权状态；低于该版本恒为 true（无需授权）。 */
    fun canRequestPackageInstalls(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** 跳到系统「安装未知应用」设置页。 */
    fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (error: Exception) {
            Log.w(TAG, "无法打开安装未知应用设置页", error)
            false
        }
    }

    private fun openUrl(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val uri = url?.let { Uri.parse(it) }
        if (uri == null || uri.scheme?.lowercase() != "https") {
            result.error(ERROR_INVALID_ARGUMENT, "只允许打开 https 链接: $url", null)
            return
        }
        try {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, uri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            result.success(true)
        } catch (error: Exception) {
            Log.w(TAG, "打开链接失败: $url", error)
            result.error(ERROR_INSTALL_FAILED, error.message ?: error.toString(), null)
        }
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error(ERROR_INVALID_ARGUMENT, "缺少 path 参数", null)
            return
        }

        val apk = File(path)
        if (!apk.isFile) {
            result.error(ERROR_INVALID_ARGUMENT, "更新包不存在: $path", null)
            return
        }

        val info = archiveInfo(apk)
        if (info?.packageName.isNullOrBlank()) {
            result.error(ERROR_APK_REJECTED, "无法读取更新包信息（文件可能已损坏）", null)
            return
        }

        val expectedPackage = call.argument<String>("expectedPackageName")
        if (!expectedPackage.isNullOrBlank() && info!!.packageName != expectedPackage) {
            result.error(
                ERROR_APK_REJECTED,
                "更新包包名 ${info.packageName} 与清单 $expectedPackage 不一致",
                null,
            )
            return
        }

        val expectedVersionCode = call.argument<Number>("expectedVersionCode")?.toInt() ?: 0
        val actualVersionCode = versionCodeOf(info!!)
        if (expectedVersionCode > 0 && actualVersionCode != expectedVersionCode) {
            result.error(
                ERROR_APK_REJECTED,
                "更新包 versionCode $actualVersionCode 与清单 $expectedVersionCode 不一致",
                null,
            )
            return
        }

        val expectedCertificate =
            call.argument<String>("expectedCertificateSha256")?.lowercase()?.trim()
        if (!expectedCertificate.isNullOrBlank()) {
            val actualCertificate = certificateSha256(info)
            if (actualCertificate == null) {
                result.error(ERROR_APK_REJECTED, "无法读取更新包的签名证书", null)
                return
            }
            if (actualCertificate != expectedCertificate) {
                result.error(
                    ERROR_APK_REJECTED,
                    "更新包签名证书 $actualCertificate 与清单 $expectedCertificate 不一致",
                    null,
                )
                return
            }
        }

        if (!canRequestPackageInstalls()) {
            openInstallPermissionSettings()
            result.error(
                ERROR_NOT_ALLOWED,
                "需要先允许「安装未知应用」，已为你打开系统设置",
                null,
            )
            return
        }

        val uri = try {
            FileProvider.getUriForFile(
                context,
                "${context.packageName}$FILE_PROVIDER_SUFFIX",
                apk,
            )
        } catch (error: Exception) {
            Log.w(TAG, "生成 FileProvider URI 失败", error)
            result.error(ERROR_INSTALL_FAILED, "无法把更新包交给系统安装器: ${error.message}", null)
            return
        }

        // 优先 ACTION_VIEW + APK MIME：这是 Android 8.0 之后官方推荐的安装入口，
        // ACTION_INSTALL_PACKAGE 只作为个别 ROM 的兜底（且已被标记废弃）。
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME)
            clipData = ClipData.newRawUri(null, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            context.startActivity(viewIntent)
            result.success(true)
        } catch (notFound: ActivityNotFoundException) {
            Log.i(TAG, "没有能处理 ACTION_VIEW 的安装器，回退到 ACTION_INSTALL_PACKAGE")
            try {
                @Suppress("DEPRECATION")
                val fallback = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                    data = uri
                    clipData = ClipData.newRawUri(null, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                }
                context.startActivity(fallback)
                result.success(true)
            } catch (error: Exception) {
                Log.w(TAG, "拉起系统安装器失败", error)
                result.error(ERROR_INSTALL_FAILED, error.message ?: error.toString(), null)
            }
        } catch (error: Exception) {
            Log.w(TAG, "拉起系统安装器失败", error)
            result.error(ERROR_INSTALL_FAILED, error.message ?: error.toString(), null)
        }
    }

    /** 只读地解析 APK 的包信息；API < 33 用旧重载，避免 PackageInfoFlags。 */
    private fun archiveInfo(apk: File): PackageInfo? {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageArchiveInfo(
                apk.absolutePath,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageArchiveInfo(apk.absolutePath, flags)
        }
    }

    @Suppress("DEPRECATION")
    private fun versionCodeOf(info: PackageInfo): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode.toInt()
        } else {
            info.versionCode
        }

    @Suppress("DEPRECATION")
    private fun certificateSha256(info: PackageInfo): String? {
        val signatures: Array<Signature>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        val certificate = signatures?.firstOrNull() ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest(certificate.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }
}
