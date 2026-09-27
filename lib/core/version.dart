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
  static const int buildNumber = 15;
}

/// 上一次发版的更新摘要，供「关于」页展示。
///
/// 与 [AppVersion.name] 同源：首行是版本号，其余是逐条摘要。
/// 避免在 `AppStrings` 里再抄一份版本号——那份副本正是漂移的来源之一。
class AppChangelog {
  const AppChangelog._();

  static const List<String> zh = <String>[
    '修复发布链路：CI 注入固定签名密钥，缺少签名材料时构建直接失败而非产出 debug 签名包',
    '安全信封改为失败关闭：启用 secureCodec 后一切明文业务帧被拒绝，杜绝单向加密的降级面',
    '统一聊天文本预算：live chat 与历史同步共用同一上限，消除长消息导致历史同步中断的裂缝',
    '蓝牙房房主转发按链路绑定重写 senderId，堵住成员冒用他人身份发言与撤回的路径',
    '版本号收敛为单一真相源，CI 新增静态分析、格式校验、覆盖率门槛与锁文件校验',
    '诊断日志 release 下丢弃 debug/info，导出报告补齐 IPv6 与平台信息脱敏',
  ];

  static const List<String> en = <String>[
    'Fixed the release pipeline: CI restores a pinned signing key, and builds fail instead of shipping debug-signed APKs',
    'Security envelope is now fail-closed: with a secureCodec configured, all plaintext business frames are rejected',
    'Unified the chat text budget so live chat and history sync agree, removing the mid-sync truncation gap',
    'BLE host relay now rewrites senderId per bound link, closing the member impersonation path',
    'Version number collapsed to a single source of truth; CI adds analyze, format, coverage and lockfile gates',
    'Release builds drop debug/info logs; exported reports redact IPv6 and platform details',
  ];

  /// 中文完整文本：版本号 + 逐条摘要。
  static String get zhBody =>
      '${AppVersion.name}\n${zh.map((line) => '· $line').join('\n')}';

  /// 英文完整文本：版本号 + 逐条摘要。
  static String get enBody =>
      '${AppVersion.name}\n${en.map((line) => '· $line').join('\n')}';
}
