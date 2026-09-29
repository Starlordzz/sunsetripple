import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/clock.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/chat_delete.dart';
import 'package:sunset_ripple/core/protocol/payloads/chat_message.dart';
import 'package:sunset_ripple/core/protocol/payloads/chat_sync.dart';
import 'package:sunset_ripple/core/session/chat_message.dart';
import 'package:sunset_ripple/core/session/member.dart';
import 'package:sunset_ripple/core/session/session_chat_hub.dart';
import 'package:sunset_ripple/core/session/session_chat_service.dart';

/// 只搭聊天服务需要的那点上下文：成员表用查表函数、发帧用记录器，
/// 这样帧层规则可以脱离 RoomSession 单测。
class _ChatHarness {
  _ChatHarness() {
    service = SessionChatService(
      hub: hub,
      selfNickname: selfNickname,
      clock: clock,
      selfMemberId: () => selfId,
      isHost: () => host,
      isInRoom: () => inRoom,
      acceptsHistorySync: () => acceptsSync,
      memberOf: (memberId) => members[memberId],
      nextSeq: nextSeq,
      send: (frame) async => sent.add(frame),
    );
  }

  final SessionChatHub hub = SessionChatHub();
  final FakeClock clock = FakeClock(DateTime(2026, 1, 1, 10));
  final List<Frame> sent = <Frame>[];
  final Map<int, Member> members = <int, Member>{};

  /// 本机昵称带设备短码：聊天帧的身份判定依赖 `<昵称>#<三位码>` 这个形态。
  final String selfNickname = '测试者#123';

  late final SessionChatService service;

  int selfId = 1;
  bool host = true;
  bool inRoom = true;
  bool acceptsSync = true;

  int _seq = 0;
  int nextSeq() => ++_seq;

  Member addMember(int id, String nickname, {bool isHost = false}) =>
      members[id] = Member(
        memberId: id,
        nickname: nickname,
        isHost: isHost,
      );

  Frame chatFrame({
    required int senderId,
    required int seq,
    required String text,
    int timestampMs = 0,
    String senderCode = '0000',
  }) =>
      Frame(
        type: FrameType.chat,
        senderId: senderId,
        seq: seq,
        payload: ChatMessagePayload(
          text: text,
          timestampMs: timestampMs,
          senderCode: senderCode,
        ).encode(),
      );

  Future<void> dispose() => hub.dispose();
}

void main() {
  late _ChatHarness h;

  setUp(() => h = _ChatHarness());
  tearDown(() => h.dispose());

  group('sendText', () {
    test('未进房时抛 StateError', () async {
      h.inRoom = false;

      await expectLater(h.service.sendText('你好'), throwsStateError);
      expect(h.sent, isEmpty);
    });

    test('空文本或纯空白抛 ArgumentError', () async {
      await expectLater(h.service.sendText('   '), throwsArgumentError);
      expect(h.sent, isEmpty);
    });

    test('发帧 + 本地回显，时间戳取自注入时钟', () async {
      h.addMember(1, '测试者#123', isHost: true);
      h.host = true;

      await h.service.sendText('  大家好  ');

      expect(h.sent.single.type, FrameType.chat);
      expect(h.sent.single.senderId, 1);
      expect(h.sent.single.seq, 1);

      final message = h.hub.messages.single;
      expect(message.text, '大家好');
      expect(message.isLocal, isTrue);
      expect(message.isHost, isTrue);
      expect(message.timestamp, h.clock.now());
      expect(
          message.messageId,
          '''

123_${h.clock.now().millisecondsSinceEpoch}_1'''
              .trim());
    });

    test('本机发送键被登记，广播回送不会重复追加', () async {
      h.addMember(1, '测试者#123');

      await h.service.sendText('你好');
      h.service.handleChatFrame(h.chatFrame(senderId: 1, seq: 1, text: '你好'));

      expect(h.hub.messages.length, 1);
    });
  });

  group('handleChatFrame 鉴权与去重', () {
    test('未在册成员的聊天帧被丢弃', () {
      h.addMember(1, '测试者#123');

      h.service
          .handleChatFrame(h.chatFrame(senderId: 9, seq: 1, text: '陌生人来访'));

      expect(h.hub.messages, isEmpty);
    });

    test('未进房时整帧丢弃', () {
      h.addMember(3, '小蓝#321');
      h.inRoom = false;

      h.service.handleChatFrame(h.chatFrame(senderId: 3, seq: 1, text: '在吗'));

      expect(h.hub.messages, isEmpty);
    });

    test('在册成员的合法帧进历史并计入未读', () {
      h.addMember(1, '测试者#123');
      h.addMember(3, '小蓝#321');

      h.service.handleChatFrame(h.chatFrame(
        senderId: 3,
        seq: 5,
        text: '大家好',
        senderCode: '321',
        timestampMs: 1700000000000,
      ));

      final message = h.hub.messages.single;
      expect(message.text, '大家好');
      expect(message.senderId, 3);
      expect(message.senderCode, '321');
      expect(message.isLocal, isFalse);
      expect(message.timestamp.millisecondsSinceEpoch, 1700000000000);
      expect(h.hub.unreadCount, 1);
    });

    test('重复的 (senderId, seq) 被有界去重静默丢弃', () {
      h.addMember(3, '小蓝#321');

      h.service.handleChatFrame(h.chatFrame(senderId: 3, seq: 5, text: '第一条'));
      h.service.handleChatFrame(h.chatFrame(senderId: 3, seq: 5, text: '重放'));

      expect(h.hub.messages.length, 1);
      expect(h.hub.messages.single.text, '第一条');
    });

    test('载荷 timestampMs 为 0 时用注入时钟补齐', () {
      h.addMember(3, '小蓝#321');

      // 直接构造一帧时间戳为 0 的载荷：encode 会把 0 换成真实时间，
      // 所以这里手工把那 8 个字节清零。
      final bytes = const ChatMessagePayload(text: '无时间戳').encode();
      final patched = Uint8List.fromList(bytes);
      for (var i = 1; i <= 8; i++) {
        patched[i] = 0;
      }

      h.service.handleChatFrame(Frame(
        type: FrameType.chat,
        senderId: 3,
        seq: 1,
        payload: patched,
      ));

      expect(h.hub.messages.single.timestamp, h.clock.now());
    });
  });

  group('历史同步', () {
    void seedHistory(String text, {String messageId = 'm1'}) {
      h.hub.append(
        ChatMessage(
          messageId: messageId,
          senderId: 1,
          senderCode: '123',
          senderNickname: '测试者',
          seq: 1,
          text: text,
          timestamp: DateTime(2026, 1, 1, 9),
          isLocal: true,
          isHost: true,
        ),
        isIncoming: false,
      );
    }

    test('只有房主会补发历史', () {
      seedHistory('历史消息');
      h.host = false;

      h.service.syncHistoryTo(4);
      expect(h.sent, isEmpty);

      h.host = true;
      h.service.syncHistoryTo(4);
      expect(h.sent.single.type, FrameType.chatSync);
    });

    test('非房主发来的历史同步帧被拒绝', () {
      h.addMember(2, '冒名者#222', isHost: false);

      h.service.handleChatSyncFrame(Frame(
        type: FrameType.chatSync,
        senderId: 2,
        seq: 1,
        payload: const ChatSyncPayload(
          targetMemberId: 0,
          senderId: 1,
          senderCode: '123',
          timestampMs: 1700000000000,
          messageId: 'forged',
          nickname: '测试者',
          text: '伪造的历史',
        ).encode(),
      ));

      expect(h.hub.messages, isEmpty);
    });

    test('房主的历史同步帧落库，重复 messageId 只收一次，且不计未读', () {
      h.addMember(1, '房主#111', isHost: true);

      Frame syncFrame() => Frame(
            type: FrameType.chatSync,
            senderId: 1,
            seq: 2,
            payload: const ChatSyncPayload(
              targetMemberId: 0,
              senderId: 1,
              senderCode: '111',
              timestampMs: 1700000000000,
              messageId: 'history-1',
              nickname: '房主',
              text: '进房前的消息',
            ).encode(),
          );

      h.service.handleChatSyncFrame(syncFrame());
      h.service.handleChatSyncFrame(syncFrame());

      expect(h.hub.messages.length, 1);
      expect(h.hub.unreadCount, 0);
    });

    test('定向给他人的历史同步帧不落库', () {
      h.addMember(1, '房主#111', isHost: true);

      h.service.handleChatSyncFrame(Frame(
        type: FrameType.chatSync,
        senderId: 1,
        seq: 2,
        payload: const ChatSyncPayload(
          targetMemberId: 4,
          senderId: 1,
          senderCode: '111',
          timestampMs: 1700000000000,
          messageId: 'history-2',
          nickname: '房主',
          text: '只发给 4 号',
        ).encode(),
      ));

      expect(h.hub.messages, isEmpty);
    });
  });

  group('撤回', () {
    void seedMessage({
      required int senderId,
      required String code,
      required String messageId,
      bool isLocal = false,
    }) {
      h.hub.append(
        ChatMessage(
          messageId: messageId,
          senderId: senderId,
          senderCode: code,
          senderNickname: '成员$senderId',
          seq: 1,
          text: '内容',
          timestamp: DateTime(2026, 1, 1, 9),
          isLocal: isLocal,
          isHost: false,
        ),
        isIncoming: false,
      );
    }

    test('删自己的消息会发撤回帧并移除本地记录', () async {
      h.addMember(1, '测试者#123');
      seedMessage(senderId: 1, code: '123', messageId: 'm1', isLocal: true);

      await h.service.recall('m1');

      expect(h.hub.messages, isEmpty);
      expect(h.sent.single.type, FrameType.chatDelete);
    });

    test('删别人的消息抛 StateError 且不动历史', () async {
      h.addMember(1, '测试者#123');
      seedMessage(senderId: 3, code: '321', messageId: 'm2');

      await expectLater(h.service.recall('m2'), throwsStateError);
      expect(h.hub.messages.length, 1);
      expect(h.sent, isEmpty);
    });

    test('撤回不存在的消息是空操作', () async {
      await h.service.recall('missing');

      expect(h.sent, isEmpty);
    });

    test('冒用他人短码的撤回请求无效，本人撤回有效', () {
      h.addMember(2, '甲#222');
      h.addMember(3, '乙#333');
      seedMessage(senderId: 3, code: '333', messageId: 'm3');

      // 2 号声称自己是 333（乙）——设备码在界面可见，谁都能冒填。
      h.service.handleChatDeleteFrame(Frame(
        type: FrameType.chatDelete,
        senderId: 2,
        seq: 9,
        payload: const ChatDeletePayload(senderCode: '333', messageId: 'm3')
            .encode(),
      ));
      expect(h.hub.messages.length, 1);

      h.service.handleChatDeleteFrame(Frame(
        type: FrameType.chatDelete,
        senderId: 3,
        seq: 10,
        payload: const ChatDeletePayload(senderCode: '999', messageId: 'm3')
            .encode(),
      ));
      expect(h.hub.messages, isEmpty);
    });

    test('不在册成员的撤回请求被忽略', () {
      h.addMember(3, '乙#333');
      seedMessage(senderId: 3, code: '333', messageId: 'm4');

      h.service.handleChatDeleteFrame(Frame(
        type: FrameType.chatDelete,
        senderId: 8,
        seq: 1,
        payload: const ChatDeletePayload(senderCode: '333', messageId: 'm4')
            .encode(),
      ));

      expect(h.hub.messages.length, 1);
    });
  });
}
