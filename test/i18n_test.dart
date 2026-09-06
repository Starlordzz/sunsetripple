import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/l10n/app_strings.dart';

void main() {
  group('AppStrings i18n Tests', () {
    test('Chinese strings return non-empty localized texts', () {
      const s = AppStrings.zh;
      expect(s.appName, '落日后残波');
      expect(s.tagline, '和身边的人聊聊');
      expect(s.fullDuplex, '自由交谈');
      expect(s.pttMode, '按住说话');
      expect(s.transferHost, '更换房主');
      expect(s.phoneMic, '手机麦克风');
      expect(s.headsetMic, '耳机麦克风');
      expect(s.transferHostConfirm('Alice'), '把房主交给Alice？');
      expect(s.roomOnlineCount(3), '3 人在这里');
      expect(s.appSubheading, contains('越过地平线'));
      expect(s.defaultNickname, '探索者');
      expect(s.scanRooms, '看看附近');
      expect(s.nearbyRoomsTitle, '附近的聊天室');
      expect(s.wifiRoom, 'Wi-Fi 畅聊');
      expect(s.bluetoothRoom, '蓝牙对讲');
      expect(s.joinRoom, '加入聊天');
      expect(s.micMutedStatus, '麦克风已关闭');
      expect(s.pttHoldingToTalk, '正在说话');
      expect(s.pttHoldToTalk, '按住说话');
      expect(s.diagnosticsTitle, '连接与音质');
      expect(s.chatTitle, '消息');
      expect(s.chatSend, '发送');
      expect(s.chatEmptyHint, contains('还没人说第一句'));
      expect(s.chatMessageTooLong, contains('分成几条'));
      expect(s.chatFormerMember, '已离开');
      expect(s.tooltipChat, '打开消息');
      expect(s.chatButtonLabel, '消息');
      expect(s.chatCloseSheet, '关闭消息');
      expect(s.chatUnreadBadge(5), '5 条未读消息');
      expect(s.chatRecall, '撤回');
      expect(s.chatRecallConfirm, contains('要撤回这条消息吗'));
      expect(s.chatRecalledTip, '撤回请求已提交');
      expect(s.formerNameLabel('旧名字'), '之前叫旧名字');
      expect(s.hostRoleBadge, '房主');
      expect(s.chatSelfBadge, '我');
      expect(s.deviceCodeTooltip, '设备识别码');
    });

    test('English strings return non-empty localized texts', () {
      const s = AppStrings.en;
      expect(s.appName, 'SunsetRipple');
      expect(s.tagline, 'Chat with people nearby');
      expect(s.fullDuplex, 'Talk freely');
      expect(s.pttMode, 'Hold to talk');
      expect(s.transferHost, 'Change host');
      expect(s.phoneMic, 'Phone microphone');
      expect(s.headsetMic, 'Headset microphone');
      expect(s.transferHostConfirm('Alice'), 'Let Alice take over as host?');
      expect(s.roomOnlineCount(3), '3 people here');
      expect(s.appSubheading, contains('Never Meant'));
      expect(s.defaultNickname, 'Explorer');
      expect(s.scanRooms, 'Look nearby');
      expect(s.nearbyRoomsTitle, 'Chats nearby');
      expect(s.wifiRoom, 'Wi-Fi Chat');
      expect(s.bluetoothRoom, 'Bluetooth Talk');
      expect(s.joinRoom, 'Join chat');
      expect(s.micMutedStatus, 'Microphone is off');
      expect(s.pttHoldingToTalk, 'Speaking');
      expect(s.pttHoldToTalk, 'Hold to talk');
      expect(s.diagnosticsTitle, 'Connection & audio');
      expect(s.chatTitle, 'Messages');
      expect(s.chatSend, 'Send');
      expect(s.chatEmptyHint, contains('No one has said hello yet'));
      expect(s.chatMessageTooLong, contains('Split it'));
      expect(s.chatFormerMember, 'Left the chat');
      expect(s.tooltipChat, 'Open messages');
      expect(s.chatButtonLabel, 'Messages');
      expect(s.chatCloseSheet, 'Close messages');
      expect(s.chatUnreadBadge(5), '5 unread messages');
      expect(s.chatRecall, 'Recall');
      expect(s.chatRecallConfirm,
          contains('Would you like to recall this message'));
      expect(s.chatRecalledTip, 'Recall request submitted');
      expect(s.formerNameLabel('OldName'), 'Previously OldName');
      expect(s.hostRoleBadge, 'Host');
      expect(s.chatSelfBadge, 'Me');
      expect(s.deviceCodeTooltip, 'Device code');
    });
  });
}
