/// 应用版本号的**唯一真相源**（Dart 侧）。
///
/// 为什么需要这个文件：版本号曾经同时硬编码在四个地方——
/// `pubspec.yaml`、`UpdateService.currentVersion`、`AppStrings.changelogBody`
/// 与 `test/update_service_test.dart`。四处手写必然漂移：发版时改了
/// pubspec 却忘了改 `currentVersion`，用户就会收到「已是最新」的假结论。
///
/// 契约（由 `test/version_consistency_test.dart` 强制）：
///   pubspec.yaml `version:`
///     == 本文件的 [appVersion] + '+' + [buildNumber]
///     == CHANGELOG.md 的第一个版本小节标题
///
/// 发版流程只改 `pubspec.yaml` 与 `CHANGELOG.md`，再同步本文件两行常量。
class AppVersion {
  const AppVersion._();

  /// 语义化版本名，与 `pubspec.yaml` 的 `version:` 前半段完全一致。
  static const String name = '0.1.0-alpha.14';

  /// 构建号（versionCode），与 `pubspec.yaml` 的 `version:` 后半段一致。
  static const int buildNumber = 16;
}

/// 上一次发版的更新摘要，供「关于」页展示。
///
/// 与 [AppVersion.name] 同源：首行是版本号，其余是逐条摘要。
/// 避免在 `AppStrings` 里再抄一份版本号——那份副本正是漂移的来源之一。
class AppChangelog {
  const AppChangelog._();

  static const List<String> zh = <String>[
    'RoomSession 与首页双上帝对象拆解：聊天/遥测外提，建房入房编排独立成服务',
    '安全层从死代码变为可达路径：新增握手协商器与带外短码，握手失败保持明文',
    '更新链路真正落地：清单验签 + 流式下载校验 SHA-256 + Android 侧二次核对后安装',
    '新增 traceId 贯穿与会话指标导出，传输层补齐 9 处关键路径日志',
    '新增 21 条 JUnit 原生单测、8 条重连测试、10 条安全协商测试',
    'UI 硬编码文案归位 AppStrings，并以 i18n 一致性测试机械阻止回归',
  ];

  static const List<String> en = <String>[
    'Split the two god objects: chat/telemetry extracted, room setup moved into a launcher service',
    'Security layer is now reachable: handshake negotiator plus out-of-band safety code',
    'Update chain implemented end to end: manifest signature, streamed SHA-256, Android re-verification',
    'Added traceId threading and session metrics export; 9 missing transport log points filled',
    'Added 21 JUnit native tests, 8 reconnect tests and 10 secure-negotiation tests',
    'Moved hardcoded UI strings into AppStrings, with an i18n parity test to prevent regressions',
  ];

  /// 中文完整文本：版本号 + 逐条摘要。
  static String get zhBody =>
      '${AppVersion.name}\n${zh.map((line) => '· $line').join('\n')}';

  /// 英文完整文本：版本号 + 逐条摘要。
  static String get enBody =>
      '${AppVersion.name}\n${en.map((line) => '· $line').join('\n')}';
}
