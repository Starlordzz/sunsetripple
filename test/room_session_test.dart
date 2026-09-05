import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/ffi/native_core_ffi.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/chat_message.dart';
import 'package:sunset_ripple/core/protocol/payloads/roster.dart';
import 'package:sunset_ripple/core/session/chat_message.dart';
import 'package:sunset_ripple/core/session/host_transfer.dart';
import 'package:sunset_ripple/core/session/room_session.dart';

void main() {
  late MockAudioIo audio;
  late RoomSession session;
  late List<Frame> sent;

  /// 一帧 20ms / 16kHz / 24kbps 的 Opus 包大约 60 字节。
  Uint8List opusPacket([int size = 60]) => Uint8List(size);

  RoomSession build({RoomMode mode = RoomMode.wifiFullDuplex}) {
    audio = MockAudioIo();
    sent = <Frame>[];
    final s = RoomSession(
      audioIo: audio,
      selfNickname: '测试者',
      mode: mode,
    );
    s.onSendFrame = sent.add;
    return s;
  }

  tearDown(() async {
    await session.dispose();
  });

  group('房主生命周期', () {
    test('createRoom 进入房间并把自己登记为房主', () async {
      session = build();
      await session.createRoom();

      expect(session.state, RoomState.inRoom);
      expect(session.isHost, isTrue);
      expect(session.selfMemberId, 1);
      expect(session.members.length, 1);
      expect(session.members.single.nickname, '测试者');
    });

    test('leave 发出离开帧并回到 idle', () async {
      session = build();
      await session.createRoom();
      sent.clear();

      await session.leave();

      expect(session.state, RoomState.idle);
      expect(session.members, isEmpty);
      expect(sent.map((f) => f.type), contains(FrameType.leave));
    });

    test('dispose 不会往已关闭的 StreamController 写入', () async {
      // 回归测试：dispose 曾经同步调用 leave() 后立刻 close 三个 controller，
      // leave() 从 await 恢复后再写入就会抛 StateError。
      session = build();
      await session.createRoom();

      await expectLater(session.dispose(), completes);

      // tearDown 会再 dispose 一次，重复调用同样不能抛。
    });
  });

  group('客户端加入', () {
    test('joinRoom 发出 joinReq', () async {
      session = build();
      await session.joinRoom();

      expect(session.state, RoomState.connecting);
      expect(sent.first.type, FrameType.joinReq);
      expect(sent.first.senderId, 0);
    });

    test('收到名单后认领自己的成员号并进入房间', () async {
      session = build();
      await session.joinRoom();

      final roster = RosterPayload(
        hostId: 1,
        members: [
          RosterMember(memberId: 1, flags: 0x01, nickname: '房主'),
          RosterMember(memberId: 3, flags: 0x00, nickname: '测试者'),
        ],
      );
      session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: roster.encode(),
      ));

      expect(session.state, RoomState.inRoom);
      expect(session.selfMemberId, 3);
      expect(session.members.length, 2);
    });
  });

  Uint8List transferPayload({
    required int successorId,
    required List<HostTransferMember> members,
  }) =>
      HostTransferCodec.encode(HostTransferPlan(
        successorId: successorId,
        members: members,
      ));

  group('交接快照与交接帧', () {
    test('快照只缓存、不改变当前房主', () async {
      session = build();
      await session.joinRoom();

      session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 2,
        seq: 1,
        payload: RosterPayload(
          hostId: 2,
          members: [
            RosterMember(memberId: 2, flags: 0x01, nickname: '房主'),
            RosterMember(memberId: 3, flags: 0x00, nickname: '测试者'),
          ],
        ).encode(),
      ));

      await session.handleIncomingFrame(Frame(
        type: FrameType.hostAnnounce,
        senderId: 2,
        seq: 2,
        payload: transferPayload(
          successorId: 3,
          members: [
            const HostTransferMember(
              memberId: 3,
              joinOrder: 5,
              nickname: '测试者',
              endpoint: '10.0.0.3',
            ),
          ],
        ),
      ));

      expect(session.isHost, isFalse, reason: '快照绝不能把现任房主顶下去');
      expect(
        session.members.firstWhere((m) => m.isHost).memberId,
        2,
      );
    });

    test('joinOrder 更小的旧交接帧被丢弃', () async {
      session = build();
      await session.joinRoom();

      await session.handleIncomingFrame(Frame(
        type: FrameType.hostAnnounce,
        senderId: 2,
        seq: 1,
        payload: transferPayload(
          successorId: 4,
          members: [
            const HostTransferMember(
              memberId: 4,
              joinOrder: 9,
              nickname: '继任',
              endpoint: '10.0.0.4',
            ),
          ],
        ),
      ));

      // joinOrder 比已见过的小，不能让自己变成房主。
      await session.handleIncomingFrame(Frame(
        type: FrameType.hostHandover,
        senderId: 2,
        seq: 2,
        payload: transferPayload(
          successorId: 3,
          members: [
            const HostTransferMember(
              memberId: 3,
              joinOrder: 4,
              nickname: '测试者',
              endpoint: '10.0.0.3',
            ),
          ],
        ),
      ));

      expect(session.isHost, isFalse);
    });
  });

  group('说话状态', () {
    test('全双工模式下音频停流后说话指示会熄灭', () async {
      session = build();
      await session.joinRoom();

      session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: RosterPayload(
          hostId: 1,
          members: [
            RosterMember(memberId: 1, flags: 0x01, nickname: '房主'),
            RosterMember(memberId: 2, flags: 0x00, nickname: '测试者'),
          ],
        ).encode(),
      ));

      session.handleIncomingFrame(Frame(
        type: FrameType.audio,
        senderId: 1,
        seq: 2,
        payload: opusPacket(),
      ));

      expect(
        session.members.firstWhere((m) => m.memberId == 1).isSpeaking,
        isTrue,
      );
      expect(
        audio.submittedFrames,
        isNotEmpty,
        reason: '在册成员的音频必须被送进原生播放管线',
      );

      // 说话超时阈值 400ms，看门定时器 100ms 一次。
      await Future.delayed(const Duration(milliseconds: 700));

      expect(
        session.members.firstWhere((m) => m.memberId == 1).isSpeaking,
        isFalse,
        reason: '全双工没有 PTT 松手事件，必须靠音频停流熄灭指示灯',
      );
    });

    test('不在名单里的发送方不会进入播放管线', () async {
      session = build();
      await session.createRoom();

      session.handleIncomingFrame(Frame(
        type: FrameType.audio,
        senderId: 99,
        seq: 1,
        payload: opusPacket(),
      ));

      expect(session.members.length, 1);
      expect(
        audio.submittedFrames,
        isEmpty,
        reason: '陌生 senderId 不该在原生侧凭空建出解码器',
      );
    });
  });

  group('PTT 与静音', () {
    test('setPtt 发出 pttState 帧并标记自己在说话', () async {
      session = build(mode: RoomMode.bluetoothPtt);
      await session.createRoom();
      sent.clear();

      session.setPtt(true);

      expect(sent.single.type, FrameType.pttState);
      expect(session.members.single.isSpeaking, isTrue);

      session.setPtt(false);
      expect(session.members.single.isSpeaking, isFalse);
    });

    test('toggleMute 同时改动音频设备与自身状态', () async {
      session = build();
      await session.createRoom();

      session.toggleMute();

      expect(audio.isMuted, isTrue);
      expect(session.members.single.isMuted, isTrue);
    });
  });

  group('帧载荷上限', () {
    test('Opus 包能完整通过 Frame 编解码', () {
      final payload = opusPacket(80);
      for (int i = 0; i < payload.length; i++) {
        payload[i] = i & 0xFF;
      }

      final frame = Frame(
        type: FrameType.audio,
        senderId: 1,
        seq: 7,
        payload: payload,
      );

      expect(frame.payload.length, 80);

      final decoded = Frame.decode(frame.encode());
      expect(decoded, isNotNull);
      expect(decoded!.payload, equals(payload));
    });

    test('上限是 512，与已发布的 Kotlin 版一致', () {
      // 对方的 FrameStreamReader 会把超过 512 的帧当作流错位并断开连接，
      // 所以这个值不能再调大。
      expect(Frame.maxPayloadSize, 512);

      final decoded = Frame.decode(
        Frame(
          type: FrameType.audio,
          senderId: 1,
          seq: 1,
          payload: Uint8List(Frame.maxPayloadSize),
        ).encode(),
      );
      expect(decoded!.payload.length, Frame.maxPayloadSize);
    });
  });

  group('响度计算', () {
    test('静音返回 0', () {
      expect(NativeCoreFfi.calculateRms(Int16List(320)), 0.0);
    });

    test('满量程方波接近 1.0', () {
      final samples = Int16List(320);
      for (int i = 0; i < samples.length; i++) {
        samples[i] = i.isEven ? 32767 : -32767;
      }
      expect(NativeCoreFfi.calculateRms(samples), closeTo(1.0, 0.01));
    });

    test('轻声不会被顶到满格', () {
      // 回归测试：原实现漏了开方且只除了一次 32767，
      // 幅度 256（约 -42 dBFS）就会 clamp 到 1.0。
      final samples = Int16List(320);
      for (int i = 0; i < samples.length; i++) {
        samples[i] = i.isEven ? 256 : -256;
      }

      final rms = NativeCoreFfi.calculateRms(samples);
      expect(rms, closeTo(256 / 32768.0, 0.001));
      expect(rms, lessThan(0.05));
    });
  });

  group('文字聊天室业务逻辑与去重', () {
    test('未进房时 sendChat 抛出 StateError', () async {
      session = build();
      expect(() => session.sendChat('hello'), throwsStateError);
    });

    test('空文本或纯空白 sendChat 抛出 ArgumentError', () async {
      session = build();
      await session.createRoom();
      expect(() => session.sendChat(''), throwsArgumentError);
      expect(() => session.sendChat('   \n  '), throwsArgumentError);
    });

    test('房主与客户端 sendChat 均发出 FrameType.chat 帧并本地立即回显', () async {
      session = build();
      await session.createRoom();

      final streamHistory = <ChatMessage>[];
      final sub = session.chatStream.listen(streamHistory.add);

      await session.sendChat('你好房主测试');

      expect(sent.any((f) => f.type == FrameType.chat), isTrue);
      final chatFrame = sent.firstWhere((f) => f.type == FrameType.chat);
      expect(chatFrame.senderId, 1);
      expect(chatFrame.seq, greaterThan(0));

      final decoded = ChatMessagePayload.decode(chatFrame.payload);
      expect(decoded, isNotNull);
      expect(decoded!.text, '你好房主测试');

      // 本机立即回显
      expect(streamHistory.length, 1);
      expect(streamHistory.first.isLocal, isTrue);
      expect(streamHistory.first.text, '你好房主测试');
      expect(streamHistory.first.senderId, 1);
      expect(session.chatMessages.length, 1);
      expect(session.chatMessages.first.text, '你好房主测试');
      // 本地发送不增加未读数
      expect(session.unreadChatCount, 0);

      await sub.cancel();
    });

    test('收到在册成员合法聊天帧：进流、进历史、未读计数递增', () async {
      session = build();
      await session.createRoom();

      // 加入成员 #2
      session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 2,
        payload: RosterPayload(
          hostId: 1,
          members: [
            RosterMember(memberId: 1, flags: 0x01, nickname: '测试者'),
            RosterMember(memberId: 2, flags: 0x00, nickname: '远端伙伴'),
          ],
        ).encode(),
      ));

      final streamHistory = <ChatMessage>[];
      final unreadHistory = <int>[];
      final chatSub = session.chatStream.listen(streamHistory.add);
      final unreadSub = session.unreadChatStream.listen(unreadHistory.add);

      final payload = const ChatMessagePayload(text: '远端发来的消息').encode();
      await session.handleIncomingFrame(Frame(
        type: FrameType.chat,
        senderId: 2,
        seq: 10,
        payload: payload,
      ));

      expect(streamHistory.length, 1);
      expect(streamHistory.first.isLocal, isFalse);
      expect(streamHistory.first.senderId, 2);
      expect(streamHistory.first.senderNickname, '远端伙伴');
      expect(streamHistory.first.text, '远端发来的消息');

      expect(session.chatMessages.length, 1);
      expect(session.unreadChatCount, 1);
      expect(unreadHistory, [1]);

      // markChatRead 归零
      session.markChatRead();
      expect(session.unreadChatCount, 0);
      expect(unreadHistory, [1, 0]);

      await chatSub.cancel();
      await unreadSub.cancel();
    });

    test('收到本机 senderId 回环帧或未知 sender 帧直接丢弃', () async {
      session = build();
      await session.createRoom();

      final payload = const ChatMessagePayload(text: '回环与非法').encode();

      // 1. senderId == self (1)
      await session.handleIncomingFrame(Frame(
        type: FrameType.chat,
        senderId: 1,
        seq: 99,
        payload: payload,
      ));
      expect(session.chatMessages, isEmpty);
      expect(session.unreadChatCount, 0);

      // 2. senderId == 未在册成员 (99)
      await session.handleIncomingFrame(Frame(
        type: FrameType.chat,
        senderId: 99,
        seq: 100,
        payload: payload,
      ));
      expect(session.chatMessages, isEmpty);
      expect(session.unreadChatCount, 0);
    });

    test('重复 (senderId, seq) 消息被有界去重静默丢弃', () async {
      session = build();
      await session.createRoom();

      session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 2,
        payload: RosterPayload(
          hostId: 1,
          members: [
            RosterMember(memberId: 1, flags: 0x01, nickname: '测试者'),
            RosterMember(memberId: 2, flags: 0x00, nickname: '远端伙伴'),
          ],
        ).encode(),
      ));

      final payload = const ChatMessagePayload(text: '去重测试').encode();
      final frame = Frame(
        type: FrameType.chat,
        senderId: 2,
        seq: 50,
        payload: payload,
      );

      // 第一次接收
      await session.handleIncomingFrame(frame);
      expect(session.chatMessages.length, 1);
      expect(session.unreadChatCount, 1);

      // 第二次相同序号接收：应丢弃
      await session.handleIncomingFrame(frame);
      expect(session.chatMessages.length, 1);
      expect(session.unreadChatCount, 1);
    });

    test('内存历史上限为 100 条，超出时淘汰最旧消息', () async {
      session = build();
      await session.createRoom();

      for (int i = 0; i < 105; i++) {
        await session.sendChat('消息 #$i');
      }

      expect(session.chatMessages.length, 100);
      expect(session.chatMessages.first.text, '消息 #5');
      expect(session.chatMessages.last.text, '消息 #104');
    });

    test('leave 与 dispose 正确清空聊天状态与流', () async {
      session = build();
      await session.createRoom();
      await session.sendChat('即将清空的消息');
      expect(session.chatMessages.length, 1);

      await session.leave();
      expect(session.chatMessages, isEmpty);
      expect(session.unreadChatCount, 0);

      await session.dispose();
      expect(session.chatMessages, isEmpty);
    });
  });
}
