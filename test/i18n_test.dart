import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/l10n/app_strings.dart';

void main() {
  group('AppStrings i18n Tests', () {
    test('Chinese strings return non-empty localized texts', () {
      const s = AppStrings.zh;
      expect(s.appName, '落日后残波');
      expect(s.tagline, '近场语音房');
      expect(s.fullDuplex, '全双工');
      expect(s.pttMode, '对讲模式');
      expect(s.transferHost, '转移房主');
      expect(s.phoneMic, '手机麦');
      expect(s.headsetMic, '耳机麦');
      expect(s.transferHostConfirm('Alice'), '确定将房主身份转移给 Alice？');
      expect(s.roomOnlineCount(3), '3 人在线');
    });

    test('English strings return non-empty localized texts', () {
      const s = AppStrings.en;
      expect(s.appName, 'SunsetRipple');
      expect(s.tagline, 'Nearby voice rooms');
      expect(s.fullDuplex, 'Full duplex');
      expect(s.pttMode, 'PTT mode');
      expect(s.transferHost, 'Transfer Host');
      expect(s.phoneMic, 'Phone Mic');
      expect(s.headsetMic, 'Headset Mic');
      expect(s.transferHostConfirm('Alice'), 'Transfer host role to Alice?');
      expect(s.roomOnlineCount(3), '3 online');
    });
  });
}
