import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/version.dart';

/// 版本号曾经同时硬编码在 4 处（pubspec / UpdateService / AppStrings /
/// update_service_test），发版时必然漏改一处。这个测试把「唯一真相源」
/// 变成可执行的契约：任何一处漂移都会让 CI 直接红。
void main() {
  group('版本号单一真相源', () {
    test('AppVersion 与 pubspec.yaml 一致', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match =
          RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml 里必须有顶层 version: 行');

      final raw = match!.group(1)!;
      expect(
        raw,
        '${AppVersion.name}+${AppVersion.buildNumber}',
        reason: 'pubspec version 与 lib/core/version.dart 漂移了：'
            '发版时两处必须同步修改',
      );
    });

    test('AppVersion 与 CHANGELOG.md 最新版本小节一致', () {
      final changelog = File('CHANGELOG.md').readAsStringSync();
      final match =
          RegExp(r'^##\s+(\S+)', multiLine: true).firstMatch(changelog);
      expect(match, isNotNull, reason: 'CHANGELOG.md 必须有 ## <version> 小节');

      expect(
        match!.group(1),
        AppVersion.name,
        reason: 'CHANGELOG 顶部小节必须与当前版本号一致，'
            '否则 release.yml 提取不到本次更新日志',
      );
    });

    test('AppChangelog 首行即当前版本号，中英文条数一致', () {
      expect(AppChangelog.zhBody.split('\n').first, AppVersion.name);
      expect(AppChangelog.enBody.split('\n').first, AppVersion.name);
      expect(AppChangelog.zh, isNotEmpty);
      expect(AppChangelog.en, isNotEmpty);
      expect(
        AppChangelog.zh.length,
        AppChangelog.en.length,
        reason: '中英文更新摘要条数必须一致',
      );
    });
  });
}
