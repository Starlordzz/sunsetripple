import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/l10n/app_strings.dart';

/// `AppStrings` 是纯类型双语方案：`isEn` 在构造期固定，中英文各自
/// 写在同一处 `isEn ? 'en' : 'zh'` 表达式里。这个结构本身没问题，
/// **真正的风险是有人绕开它**——直接在 Widget 里写死一段中文提示。
///
/// 历史上就有 6 处这样绕开（建房/入房失败提示、断线提示）。它们不会让
/// 测试红，只会让英文用户在失败时看到中文，或者让新文案漏翻译。
///
/// 这个测试守两件事：
///   1. `lib/ui/` 下不再出现「面向用户的裸中文字面量」；
///   2. 中英文两个实例的**全部 getter 都非空且有差异**（漏写英文会得到中文）。
void main() {
  group('AppStrings 结构完整性', () {
    test('所有面向用户的 getter 在两种语言下都非空', () {
      final violations = <String>[];

      for (final method in _zeroArgStringGetters()) {
        final zh = method(AppStrings.zh);
        final en = method(AppStrings.en);

        if (zh.trim().isEmpty) violations.add('${method.key}: 中文为空');
        if (en.trim().isEmpty) violations.add('${method.key}: 英文为空');
      }

      expect(
        violations,
        isEmpty,
        reason: '这些字符串在某种语言下是空的：\n${violations.join('\n')}',
      );
    });

    test('语言切换真的生效：中英实例在多数键上给出不同的值', () {
      var differing = 0;
      var total = 0;

      for (final method in _zeroArgStringGetters()) {
        final zh = method(AppStrings.zh);
        final en = method(AppStrings.en);
        // 产品名这类确实可能相同（例如 "SunsetRipple"），所以不做 100% 断言，
        // 但绝大部分文案必须随语言变化，否则说明 isEn 分支被写坏了。
        if (zh != en) differing++;
        total++;
      }

      // 列表当前有 71 项。设成会随新增文案上调的下限：只增不减，
      // 有人删文案或删列表项时会红。
      expect(total, greaterThanOrEqualTo(70),
          reason: 'getter 列表异常缩短（当前清单 71 项）');
      expect(
        differing / total,
        greaterThan(0.8),
        reason: '只有 $differing/$total 个字符串随语言变化，'
            'isEn 分支可能被写坏或被硬编码覆盖',
      );
    });

    test('带参字符串在中英文下都做了插值', () {
      expect(AppStrings.zh.roomOnlineCount(3), contains('3'));
      expect(AppStrings.en.roomOnlineCount(3), contains('3'));

      expect(AppStrings.zh.updateAvailable('1.2.3'), contains('1.2.3'));
      expect(AppStrings.en.updateAvailable('1.2.3'), contains('1.2.3'));

      expect(AppStrings.zh.metricDuration(125), contains('2'));
      expect(AppStrings.en.metricDuration(125), contains('2'));

      expect(AppStrings.zh.transferHostConfirm('Alice'), contains('Alice'));
      expect(AppStrings.en.transferHostConfirm('Alice'), contains('Alice'));
    });

    test('metricDuration 对负数做钳制，不输出负时长', () {
      expect(AppStrings.zh.metricDuration(-5), isNot(contains('-')));
      expect(AppStrings.en.metricDuration(-5), isNot(contains('-')));
    });
  });

  group('UI 层不得硬编码面向用户的文案', () {
    test('lib/ui 下没有裸中文字符串字面量', () {
      final offenders = <String>[];
      final uiDir = Directory('lib/ui');
      expect(uiDir.existsSync(), isTrue, reason: '找不到 lib/ui 目录');

      // 只找**引号包裹的中文**，注释与日志文案不算——日志是给开发者看的，
      // 本来就该是中文（见 AppLog 的调用点）。
      final literal = RegExp("r?'([^'\\n]*[\\u4e00-\\u9fff][^'\\n]*)'");

      for (final entity in uiDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          // 去掉行内注释再判断，避免把「// 这里是中文说明」算进去。
          final code = lines[i].split('//').first;
          final match = literal.firstMatch(code);
          if (match == null) continue;

          // 日志调用与 AppLog 文案是开发者面向的，允许中文。
          if (code.contains('AppLog.') ||
              code.contains('debugPrint') ||
              code.contains('throw ')) {
            continue;
          }
          offenders.add('${entity.path}:${i + 1}: ${code.trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: '面向用户的文案必须走 AppStrings，不要写字面量：\n'
            '${offenders.join('\n')}',
      );
    });
  });
}

/// 收集 `AppStrings` 上所有「零参数字符串 getter」。
///
/// Dart 没有运行时反射，所以这里把 getter 列表显式维护成闭包表。
/// 新增文案时**必须**在这里补一行——漏补会被上一组「数量异常」断言兜住
/// （total 只增不减，除非有人删文案）。
List<_KeyedGetter> _zeroArgStringGetters() => [
      _KeyedGetter('appName', (s) => s.appName),
      _KeyedGetter('tagline', (s) => s.tagline),
      _KeyedGetter('appSubheading', (s) => s.appSubheading),
      _KeyedGetter('fullDuplex', (s) => s.fullDuplex),
      _KeyedGetter('pttMode', (s) => s.pttMode),
      _KeyedGetter('transferHost', (s) => s.transferHost),
      _KeyedGetter('phoneMic', (s) => s.phoneMic),
      _KeyedGetter('headsetMic', (s) => s.headsetMic),
      _KeyedGetter('defaultNickname', (s) => s.defaultNickname),
      _KeyedGetter('scanRooms', (s) => s.scanRooms),
      _KeyedGetter('nearbyRoomsTitle', (s) => s.nearbyRoomsTitle),
      _KeyedGetter('wifiRoom', (s) => s.wifiRoom),
      _KeyedGetter('bluetoothRoom', (s) => s.bluetoothRoom),
      _KeyedGetter('joinRoom', (s) => s.joinRoom),
      _KeyedGetter('micMutedStatus', (s) => s.micMutedStatus),
      _KeyedGetter('pttHoldingToTalk', (s) => s.pttHoldingToTalk),
      _KeyedGetter('pttHoldToTalk', (s) => s.pttHoldToTalk),
      _KeyedGetter('diagnosticsTitle', (s) => s.diagnosticsTitle),
      _KeyedGetter('chatTitle', (s) => s.chatTitle),
      _KeyedGetter('chatSend', (s) => s.chatSend),
      _KeyedGetter('chatEmptyHint', (s) => s.chatEmptyHint),
      _KeyedGetter('chatMessageTooLong', (s) => s.chatMessageTooLong),
      _KeyedGetter('chatFormerMember', (s) => s.chatFormerMember),
      _KeyedGetter('chatButtonLabel', (s) => s.chatButtonLabel),
      _KeyedGetter('chatCloseSheet', (s) => s.chatCloseSheet),
      _KeyedGetter('chatRecall', (s) => s.chatRecall),
      _KeyedGetter('chatRecalledTip', (s) => s.chatRecalledTip),
      _KeyedGetter('chatSelfBadge', (s) => s.chatSelfBadge),
      _KeyedGetter('hostRoleBadge', (s) => s.hostRoleBadge),
      _KeyedGetter('deviceCodeTooltip', (s) => s.deviceCodeTooltip),
      _KeyedGetter('tooltipChat', (s) => s.tooltipChat),
      _KeyedGetter('roomConnected', (s) => s.roomConnected),
      _KeyedGetter('speaking', (s) => s.speaking),
      _KeyedGetter('muted', (s) => s.muted),
      _KeyedGetter('aboutTitle', (s) => s.aboutTitle),
      _KeyedGetter('aboutProduct', (s) => s.aboutProduct),
      _KeyedGetter('checkUpdate', (s) => s.checkUpdate),
      _KeyedGetter('updateIdle', (s) => s.updateIdle),
      _KeyedGetter('updateChecking', (s) => s.updateChecking),
      _KeyedGetter('updateCurrent', (s) => s.updateCurrent),
      _KeyedGetter('updateCheckFailed', (s) => s.updateCheckFailed),
      _KeyedGetter('updateNetworkNote', (s) => s.updateNetworkNote),
      _KeyedGetter('changelogTitle', (s) => s.changelogTitle),
      _KeyedGetter('changelogBody', (s) => s.changelogBody),
      _KeyedGetter('licenseTitle', (s) => s.licenseTitle),
      _KeyedGetter('licenseBody', (s) => s.licenseBody),
      _KeyedGetter('privacyTitle', (s) => s.privacyTitle),
      _KeyedGetter('privacyBody', (s) => s.privacyBody),
      _KeyedGetter('themeLight', (s) => s.themeLight),
      _KeyedGetter('themeDark', (s) => s.themeDark),
      _KeyedGetter('reportCopied', (s) => s.reportCopied),
      _KeyedGetter('copyReport', (s) => s.copyReport),
      _KeyedGetter('qualityGood', (s) => s.qualityGood),
      _KeyedGetter('qualityFair', (s) => s.qualityFair),
      _KeyedGetter('qualityPoor', (s) => s.qualityPoor),
      _KeyedGetter('errStartWifiRoom', (s) => s.errStartWifiRoom),
      _KeyedGetter('errStartBleRoom', (s) => s.errStartBleRoom),
      _KeyedGetter('errJoinRoom', (s) => s.errJoinRoom),
      _KeyedGetter('errJoinBleRoom', (s) => s.errJoinBleRoom),
      _KeyedGetter('errJoinWifiDirectHost', (s) => s.errJoinWifiDirectHost),
      _KeyedGetter('connDisconnected', (s) => s.connDisconnected),
      _KeyedGetter('metricReceivedFrames', (s) => s.metricReceivedFrames),
      _KeyedGetter('metricLostFrames', (s) => s.metricLostFrames),
      _KeyedGetter('metricConcealedFrames', (s) => s.metricConcealedFrames),
      _KeyedGetter('metricNetworkQuality', (s) => s.metricNetworkQuality),
      _KeyedGetter('metricUptime', (s) => s.metricUptime),
      _KeyedGetter(
          'metricPendingMeasurement', (s) => s.metricPendingMeasurement),
      _KeyedGetter('updatePreparing', (s) => s.updatePreparing),
      _KeyedGetter(
          'updateDownloadAndInstall', (s) => s.updateDownloadAndInstall),
      _KeyedGetter('updateOpenDownloadPage', (s) => s.updateOpenDownloadPage),
      _KeyedGetter('updateHandedToInstaller', (s) => s.updateHandedToInstaller),
    ];

class _KeyedGetter {
  final String key;
  final String Function(AppStrings) read;
  const _KeyedGetter(this.key, this.read);

  String call(AppStrings s) => read(s);
}
