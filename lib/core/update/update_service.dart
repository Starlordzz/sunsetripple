import 'dart:convert';
import 'dart:io';
import '../diagnostics/app_log.dart';

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
  final String downloadUrl;

  const UpdateAvailable({
    required this.versionName,
    required this.releaseNotes,
    required this.downloadUrl,
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
  static const String latestReleaseUrl =
      'https://api.github.com/repos/Starlordzz/sunsetripple/releases/latest';

  Future<UpdateState> checkUpdate() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(latestReleaseUrl));
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'SunsetRipple-App');

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final tagName = data['tag_name'] as String? ?? '';
        final releaseNotes = data['body'] as String? ?? '';
        final htmlUrl = data['html_url'] as String? ?? '';

        if (tagName.isNotEmpty && isNewer(tagName, currentVersion)) {
          return UpdateAvailable(
            versionName: tagName.replaceFirst('v', ''),
            releaseNotes: releaseNotes,
            downloadUrl: htmlUrl,
          );
        } else {
          return const UpdateUpToDate();
        }
      } else {
        AppLog.warn('UpdateService', 'Check update HTTP ${response.statusCode}');
        return UpdateFailed('HTTP ${response.statusCode}');
      }
    } catch (e) {
      AppLog.warn('UpdateService', 'Check update failed', e);
      return UpdateFailed(e.toString());
    } finally {
      client.close();
    }
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
