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
      expect(s.appSubheading, contains('夕阳已远'));
      expect(s.defaultNickname, '探索者');
      expect(s.scanRooms, '扫描房间');
      expect(s.nearbyRoomsTitle, '附近的对讲房间');
      expect(s.wifiRoom, 'WiFi 房');
      expect(s.bluetoothRoom, '蓝牙房');
      expect(s.joinRoom, '加入');
      expect(s.micMutedStatus, '麦克风已静音');
      expect(s.pttHoldingToTalk, '正在讲话');
      expect(s.pttHoldToTalk, '按住说话');
      expect(s.diagnosticsTitle, '网络与音质诊断');
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
      expect(s.appSubheading, contains('The sun has set'));
      expect(s.defaultNickname, 'Explorer');
      expect(s.scanRooms, 'Scan Rooms');
      expect(s.nearbyRoomsTitle, 'Nearby Voice Rooms');
      expect(s.wifiRoom, 'WiFi room');
      expect(s.bluetoothRoom, 'Bluetooth room');
      expect(s.joinRoom, 'Join');
      expect(s.micMutedStatus, 'Microphone muted');
      expect(s.pttHoldingToTalk, 'Speaking');
      expect(s.pttHoldToTalk, 'Hold to talk');
      expect(s.diagnosticsTitle, 'Network & Audio Diagnostics');
    });
  });
}
