import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart' show SHA256Digest;

import '../diagnostics/app_log.dart';
import 'update_manifest.dart';

/// 更新安装链路的错误基类。
///
/// 每一种失败都必须带着可读原因抛到 UI，**不允许**静默吞掉后继续走安装流程。
class UpdateInstallerException implements Exception {
  const UpdateInstallerException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// 下载阶段失败：网络错误、超时、体积超限、HTTP 非 200、SHA-256 不匹配。
class UpdateDownloadException extends UpdateInstallerException {
  const UpdateDownloadException(super.message);
}

/// 安装阶段失败：缺少「安装未知应用」授权、原生安装器拒绝、插件缺失。
class UpdateInstallException extends UpdateInstallerException {
  const UpdateInstallException(super.message);
}

/// 当前平台不支持这个动作（例如桌面端既不能自装也没有打开链接的通道）。
class UpdateUnsupportedException extends UpdateInstallerException {
  const UpdateUnsupportedException(super.message);
}

/// 创建 [HttpClient] 的工厂，测试里可以注入桩实现。
typedef UpdateHttpClientFactory = HttpClient Function();

/// 一次「下载 + 校验」任务：进度是 0.0–1.0 的流，完成后 [done] 给出临时文件。
///
/// 失败时错误会同时出现在 [progress] 与 [done] 上 —— UI 两边都能拿到可读原因。
class UpdateDownload {
  const UpdateDownload({required this.progress, required this.done});

  final Stream<double> progress;
  final Future<File> done;
}

/// 更新包的下载、校验与安装。
///
/// 分工：
///   * 清单验签 → [UpdateManifest]（纯 Dart，可测）；
///   * 本类负责「拿到一个已验证的 APK 文件」与「交给系统安装器」，
///     以及 iOS / 桌面端「只能打开下载页」这件事的诚实表达。
///
/// Android 侧下载完之后**不会**直接安装：先交给 `UpdateInstallerPlugin`，
/// 由原生侧再核对包名、versionCode 与签名证书 SHA-256 一致，才拉起系统安装确认框。
class UpdateInstaller {
  UpdateInstaller({UpdateHttpClientFactory? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  static const MethodChannel _channel =
      MethodChannel('host.msknet.sunsetripple/update_installer');

  final UpdateHttpClientFactory _clientFactory;

  /// 只有 Android 允许应用内下载安装。iOS 的沙箱不允许 App 自装，桌面端没有安装器。
  static bool get supportsInAppInstall => Platform.isAndroid;

  /// 拉取 Release 上的 `update.json` 并**验签**，只有验过的清单才会被返回。
  ///
  /// [manifestUrl] 必须命中 [UpdateManifest.isTrustedUpdateUrl]（https + 白名单域名），
  /// 响应体上限 [kUpdateManifestMaxBytes]，整体超时 [kUpdateManifestFetchTimeout]。
  /// 验签失败抛 [UpdateManifestSignatureException] —— 调用方会把它原样展示给用户。
  Future<UpdateManifest> fetchManifest(String manifestUrl) async {
    final uri = Uri.tryParse(manifestUrl);
    if (uri == null || !UpdateManifest.isTrustedUpdateUrl(uri)) {
      throw UpdateDownloadException('拒绝从不信任的地址获取更新清单: $manifestUrl');
    }

    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'SunsetRipple-App');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw UpdateDownloadException(
            '获取更新清单失败：HTTP ${response.statusCode}（$manifestUrl）');
      }
      if (response.contentLength > kUpdateManifestMaxBytes) {
        throw const UpdateDownloadException('更新清单体积异常，已放弃');
      }

      final payload = <int>[];
      await for (final chunk in response.timeout(kUpdateManifestFetchTimeout)) {
        payload.addAll(chunk);
        if (payload.length > kUpdateManifestMaxBytes) {
          throw const UpdateDownloadException('更新清单体积超过 64 KiB，已放弃');
        }
      }

      final String text;
      try {
        text = utf8.decode(payload);
      } on FormatException {
        throw const UpdateDownloadException('更新清单不是合法 UTF-8');
      }
      // 验签：任何一处不匹配都会抛异常，绝不返回「可能没问题」的清单。
      return UpdateManifest.verify(text);
    } on UpdateInstallerException {
      rethrow;
    } on UpdateManifestException {
      // 验签失败/字段非法的原因要原样冒到 UI，不能被下面的兜底吞成网络错误。
      rethrow;
    } on TimeoutException {
      throw const UpdateDownloadException('获取更新清单超时，请稍后再试');
    } catch (error) {
      // 断网、DNS 失败、TLS 失败等都在这里变成用户能读懂的句子。
      throw UpdateDownloadException('获取更新清单失败: $error');
    } finally {
      client.close(force: true);
    }
  }

  /// 下载 APK 并交给系统安装器（仅 Android）。
  ///
  /// 进度通过 [UpdateDownload.progress] 上报；校验失败/下载失败都会让
  /// [UpdateDownload.done] 以 [UpdateInstallerException] 结束。
  UpdateDownload downloadAndInstall(UpdateManifest manifest) {
    final controller = StreamController<double>();
    final done = () async {
      File? apk;
      try {
        if (!Platform.isAndroid) {
          throw const UpdateUnsupportedException(
              '当前平台不支持应用内安装更新（仅 Android）；iOS 请在浏览器中手动完成安装');
        }
        // 地址策略在下载入口再断言一次：即使清单来得再可信，也不会从非白名单域名取包。
        manifest.assertTrustedUpdateUrl();
        _report(controller, 0);
        apk = await downloadVerifiedFile(
          manifest.apkUri,
          manifest.apkSha256,
          onProgress: (progress) => _report(controller, progress),
        );
        _report(controller, 1);
        AppLog.info('UpdateInstaller',
            '已下载并校验 ${manifest.versionName}+${manifest.versionCode} → ${apk.path}');
        await _installVerified(apk, manifest);
        return apk;
      } catch (error) {
        _reportError(controller, error);
        rethrow;
      } finally {
        await controller.close();
      }
    }();
    return UpdateDownload(progress: controller.stream, done: done);
  }

  /// 打开外部下载页（iOS 与 Android 都走这里）。
  ///
  /// iOS 的沙箱不允许 App 自己安装，所以这里只负责把用户送到浏览器/应用市场；
  /// 桌面端没有可用的打开方式，直接给出「不支持」而不是假装成功。
  Future<void> openReleasePage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute || uri.scheme != 'https') {
      throw UpdateUnsupportedException('拒绝打开非 HTTPS 的更新页面: $url');
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UpdateUnsupportedException('当前平台不支持打开更新页面，请手动访问: $url');
    }
    try {
      await _channel.invokeMethod<void>('openUrl', <String, Object?>{
        'url': url,
      });
    } on MissingPluginException {
      throw const UpdateUnsupportedException('当前构建缺少打开链接的平台通道');
    } on PlatformException catch (error) {
      throw UpdateUnsupportedException(
          '打开更新页面失败: ${error.message ?? error.code}');
    }
  }

  /// 系统是否已允许本应用「安装未知应用」（Android 8.0+）。
  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ??
          false;
    } on MissingPluginException {
      // 老构建里没有插件：交给系统在安装时兜底提示，不谎报「已授权」。
      return false;
    }
  }

  /// 跳到系统的「安装未知应用」设置页。
  Future<bool> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel
              .invokeMethod<bool>('openInstallPermissionSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      AppLog.warn('UpdateInstaller', '打开安装权限设置页失败', error);
      return false;
    }
  }

  /// 下载到临时文件并**边下边算** SHA-256，随后逐字节比对给定摘要。
  ///
  /// 三条硬约束：
  ///   1. 只允许白名单内的 HTTPS 地址（自己再断言一次
  ///      [UpdateManifest.isTrustedUpdateUrl]，不依赖调用方自觉）；
  ///   2. 响应体超过 [kUpdateDownloadMaxBytes] 立即中断，不写满磁盘；
  ///   3. 摘要不匹配就把文件删掉，绝不让可疑的字节流流到安装器。
  ///
  /// 生产调用方是 [downloadAndInstall]；测试注入桩 [HttpClient] 直接驱动它，
  /// 覆盖「流式下载 → 边下边算摘要 → 摘要不符删除文件 → 体积上限中断」这几条路径。
  Future<File> downloadVerifiedFile(
    Uri url,
    String expectedSha256, {
    void Function(double progress)? onProgress,
  }) async {
    if (!UpdateManifest.isTrustedUpdateUrl(url)) {
      throw UpdateDownloadException('拒绝从非白名单地址下载: $url');
    }

    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    // 固定的子目录名：Android 的 FileProvider 只暴露
    // `res/xml/file_paths.xml` 里声明的那一段，名字必须写死。
    final root = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}$kUpdateDownloadDirectoryName');
    await root.create(recursive: true);
    final workingDirectory = await root.createTemp('apk-');
    final target =
        File('${workingDirectory.path}${Platform.pathSeparator}update.apk');

    var succeeded = false;
    try {
      final file = await _streamToFile(
        client: client,
        url: url,
        target: target,
        expectedSha256: expectedSha256,
        onProgress: onProgress,
      ).timeout(kUpdateDownloadTimeout);
      succeeded = true;
      return file;
    } on TimeoutException {
      throw const UpdateDownloadException('下载超时（5 分钟内没有完成），已放弃本次更新');
    } on UpdateInstallerException {
      rethrow;
    } catch (error) {
      // 断网 / DNS / TLS 失败等：给出可读原因，而不是把 SocketException 直接甩到界面。
      throw UpdateDownloadException('下载更新包失败: $error');
    } finally {
      client.close(force: true);
      if (!succeeded) {
        // 失败路径不留半截文件：临时目录整个删掉。
        try {
          await workingDirectory.delete(recursive: true);
        } catch (error) {
          AppLog.warn('UpdateInstaller', '清理下载临时文件失败', error);
        }
      }
    }
  }

  Future<File> _streamToFile({
    required HttpClient client,
    required Uri url,
    required File target,
    required String expectedSha256,
    void Function(double progress)? onProgress,
  }) async {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, 'SunsetRipple-App');
    request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw UpdateDownloadException('下载失败：HTTP ${response.statusCode}（$url）');
    }
    final declaredLength = response.contentLength;
    if (declaredLength > kUpdateDownloadMaxBytes) {
      throw UpdateDownloadException(
          '更新包体积 ${_humanBytes(declaredLength)} 超过上限 ${_humanBytes(kUpdateDownloadMaxBytes)}');
    }

    final digest = SHA256Digest();
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final rawChunk in response.timeout(kUpdateDownloadTimeout)) {
        // pointycastle 的 Digest.update 要 Uint8List：dart:io 的流不保证给的就是它。
        final chunk =
            rawChunk is Uint8List ? rawChunk : Uint8List.fromList(rawChunk);
        received += chunk.length;
        if (received > kUpdateDownloadMaxBytes) {
          throw UpdateDownloadException(
              '更新包体积超过上限 ${_humanBytes(kUpdateDownloadMaxBytes)}，已中断下载');
        }
        digest.update(chunk, 0, chunk.length);
        sink.add(chunk);
        if (declaredLength > 0 && onProgress != null) {
          onProgress(received / declaredLength);
        }
      }
    } finally {
      await sink.close();
    }

    final digestBytes = Uint8List(digest.digestSize);
    digest.doFinal(digestBytes, 0);
    final actualSha256 = _toHex(digestBytes);
    if (actualSha256 != expectedSha256.toLowerCase()) {
      await target.delete();
      throw UpdateDownloadException(
          '更新包校验失败：SHA-256 不匹配（期望 ${expectedSha256.toLowerCase()}，实际 $actualSha256）');
    }
    AppLog.info('UpdateInstaller',
        '更新包下载完成：${_humanBytes(received)}，SHA-256 $actualSha256');
    return target;
  }

  Future<void> _installVerified(File apk, UpdateManifest manifest) async {
    if (!await apk.exists()) {
      throw UpdateInstallException('待安装的更新包不存在: ${apk.path}');
    }
    if (!await canRequestPackageInstalls()) {
      await openInstallPermissionSettings();
      throw const UpdateInstallException(
          '需要先允许「安装未知应用」，已为你打开系统设置，授权后请再点一次「下载并安装」');
    }

    try {
      await _channel.invokeMethod<void>('installApk', <String, Object?>{
        'path': apk.path,
        'expectedPackageName': manifest.packageName,
        'expectedVersionCode': manifest.versionCode,
        'expectedCertificateSha256': manifest.certificateSha256,
      });
    } on MissingPluginException {
      throw const UpdateUnsupportedException('当前构建缺少安装插件，无法拉起系统安装器');
    } on PlatformException catch (error) {
      throw UpdateInstallException(
          '系统安装器拒绝了这个更新包: ${error.message ?? error.code}');
    }
  }

  void _report(StreamController<double> controller, double progress) {
    if (!controller.isClosed) controller.add(progress);
  }

  void _reportError(StreamController<double> controller, Object error) {
    if (!controller.isClosed) controller.addError(error);
  }
}

String _toHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String _humanBytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
