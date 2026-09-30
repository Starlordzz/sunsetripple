import 'dart:convert';
import 'dart:io';
import '../diagnostics/app_log.dart';
import '../version.dart';

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

class UpdateAvailable extends UpdateState {
  final String versionName;
  final String releaseNotes;

  /// Release 页面地址（`html_url`），iOS 与「不想自装」的用户从这里手动下载。
  final String downloadUrl;

  /// Release 资产里 `update.json` 的直链；老版本发布没有这个资产时为 null。
  ///
  /// 只有拿到它，应用内「下载并安装」才能走「验签 → 下载 → 校验 → 系统安装」这条路。
  final String? manifestUrl;

  const UpdateAvailable({
    required this.versionName,
    required this.releaseNotes,
    required this.downloadUrl,
    this.manifestUrl,
  });
}

class UpdateFailed extends UpdateState {
  final String message;

  const UpdateFailed(this.message);
}

/// 语义化版本解析与比较（遵循 SemVer 2.0.0 规范）。
class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  const SemVer({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease = const [],
  });

  static SemVer? parse(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1).trim();
    }
    if (v.isEmpty) return null;

    // 剥离构建元数据（+...）
    final buildIdx = v.indexOf('+');
    if (buildIdx != -1) {
      v = v.substring(0, buildIdx);
    }

    // 剥离预发布标识（-...）
    final dashIdx = v.indexOf('-');
    String mainPart = v;
    List<String> pre = [];
    if (dashIdx != -1) {
      mainPart = v.substring(0, dashIdx);
      final prePart = v.substring(dashIdx + 1);
      if (prePart.isNotEmpty) {
        pre = prePart.split('.');
      }
    }

    final segments = mainPart.split('.');
    if (segments.isEmpty) return null;

    final major = int.tryParse(segments[0]);
    if (major == null) return null;
    final minor = segments.length > 1 ? (int.tryParse(segments[1]) ?? 0) : 0;
    final patch = segments.length > 2 ? (int.tryParse(segments[2]) ?? 0) : 0;

    return SemVer(
      major: major,
      minor: minor,
      patch: patch,
      preRelease: pre,
    );
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // SemVer 规范：主版本号相等时，带 pre-release 的版本优先级低于正式版本
    // 例如 0.1.0-alpha.8 < 0.1.0
    if (preRelease.isEmpty && other.preRelease.isNotEmpty) return 1;
    if (preRelease.isNotEmpty && other.preRelease.isEmpty) return -1;
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;

    final maxLen = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;

    for (int i = 0; i < maxLen; i++) {
      if (i >= preRelease.length) return -1; // 标识更短的优先级更低
      if (i >= other.preRelease.length) return 1;

      final a = preRelease[i];
      final b = other.preRelease[i];

      final aNum = int.tryParse(a);
      final bNum = int.tryParse(b);

      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else if (aNum != null && bNum == null) {
        // 数字标识低于非数字标识
        return -1;
      } else if (aNum == null && bNum != null) {
        return 1;
      } else {
        final cmp = a.compareTo(b);
        if (cmp != 0) return cmp;
      }
    }

    return 0;
  }
}

class UpdateService {
  /// 与 `pubspec.yaml` 同源，见 [AppVersion]。
  static const String currentVersion = AppVersion.name;

  /// GitHub Releases **列表**接口，而不是 `/releases/latest`。
  ///
  /// 为什么不用 `/releases/latest`：GitHub 该端点只返回**非 prerelease** 的 Release，
  /// 而本项目所有版本都是 alpha/beta（一律标 `--prerelease`），实测该端点直接 404，
  /// 于是「检查更新」永远拿不到任何东西。改用列表接口后由客户端自己挑版本。
  static const String releasesUrl =
      'https://api.github.com/repos/Starlordzz/sunsetripple/releases?per_page=30';

  /// 当前构建是不是预发布渠道：版本名里带 `-`（如 `0.1.0-alpha.14`）。
  ///
  /// 预发布渠道能看到 prerelease 版本；正式版只看正式版，避免正式用户被推到 alpha 上。
  static bool get includePrerelease => currentVersion.contains('-');

  Future<UpdateState> checkUpdate() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(releasesUrl));
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'SunsetRipple-App');

      final response = await request.close();
      if (response.statusCode != 200) {
        AppLog.warn(
            'UpdateService', 'Check update HTTP ${response.statusCode}');
        return UpdateFailed('HTTP ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      final releases = decoded is List ? decoded : const <dynamic>[];
      if (releases.isEmpty) {
        // 还没有任何 Release：不是错误，只是没什么可更新的。
        return const UpdateUpToDate();
      }

      final data =
          selectRelease(releases, includePrerelease: includePrerelease);
      if (data == null) {
        AppLog.warn('UpdateService', 'Release 列表里没有可用的版本标签');
        return const UpdateFailed('Release 列表里没有可用的版本标签');
      }

      final tagName = data['tag_name'] as String? ?? '';
      final releaseNotes = data['body'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '';

      if (tagName.isNotEmpty && isNewer(tagName, currentVersion)) {
        return UpdateAvailable(
          versionName: tagName.replaceFirst('v', ''),
          releaseNotes: releaseNotes,
          downloadUrl: htmlUrl,
          manifestUrl: findManifestAssetUrl(data['assets']),
        );
      }
      return const UpdateUpToDate();
    } catch (e) {
      AppLog.warn('UpdateService', 'Check update failed', e);
      return UpdateFailed(e.toString());
    } finally {
      client.close();
    }
  }

  /// 从 `GET /releases` 的响应里挑出用于检查更新的那一条；没有合适的返回 null。
  ///
  /// 规则（按顺序）：
  /// - 丢掉 `draft`；
  /// - [includePrerelease] 为 false 时丢掉 `prerelease`；
  /// - `tag_name` 必须能解析成 SemVer —— 滚动通道那种固定 tag（`updates-prerelease`）
  ///   因此天然不会被误当成新版本；
  /// - 取 SemVer 最大者；版本相同时后发布（`created_at` 更晚）的优先。
  ///
  /// 纯函数，不碰网络：选择规则可以脱离 HTTP 单测。
  static Map<String, dynamic>? selectRelease(
    Iterable<dynamic> releases, {
    required bool includePrerelease,
  }) {
    Map<String, dynamic>? best;
    SemVer? bestVersion;
    String bestCreatedAt = '';

    for (final entry in releases) {
      if (entry is! Map) continue;
      final release = entry.cast<String, dynamic>();
      if (release['draft'] == true) continue;
      if (!includePrerelease && release['prerelease'] == true) continue;

      final tag = release['tag_name'];
      if (tag is! String) continue;
      final version = SemVer.parse(tag);
      if (version == null) continue;

      final createdAt = release['created_at'] is String
          ? release['created_at'] as String
          : '';
      final comparison =
          bestVersion == null ? 1 : version.compareTo(bestVersion);
      if (comparison > 0 ||
          (comparison == 0 && createdAt.compareTo(bestCreatedAt) > 0)) {
        best = release;
        bestVersion = version;
        bestCreatedAt = createdAt;
      }
    }

    return best;
  }

  /// 从 GitHub Release 的 `assets` 数组里找签名清单资产（`update.json`）的直链。
  ///
  /// 找不到就返回 null：应用会退化成「打开 Release 页面手动下载」，而不是假装能自装。
  static String? findManifestAssetUrl(Object? assets) {
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      if (asset['name'] != 'update.json') continue;
      final url = asset['browser_download_url'];
      if (url is String && url.startsWith('https://')) return url;
    }
    return null;
  }

  /// 真正的语义版本比较：只有 remote 严格大于 current 时才返回 true
  static bool isNewer(String remote, String current) {
    final remoteVer = SemVer.parse(remote);
    final currentVer = SemVer.parse(current);

    if (remoteVer != null && currentVer != null) {
      return remoteVer.compareTo(currentVer) > 0;
    }

    // 解析失败时的兜底（不应视作更新，防止误导用户回退）
    return false;
  }
}
