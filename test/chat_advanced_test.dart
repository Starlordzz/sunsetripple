import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/chat_delete.dart';
import 'package:sunset_ripple/core/protocol/payloads/chat_message.dart';
import 'package:sunset_ripple/core/protocol/payloads/join_request.dart';
import 'package:sunset_ripple/core/protocol/payloads/roster.dart';
import 'package:sunset_ripple/core/session/device_code.dart';
import 'package:sunset_ripple/core/session/room_session.dart';
import 'package:sunset_ripple/ui/widgets/avatar_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('近场聊天全生命周期、同人识别、头像框与全员撤回测试', () {
    test('Host 在新成员进房时自动补发全量历史聊天帧 (Chat History Sync)', () async {
      final hostSentFrames = <Frame>[];
      final hostSession = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '房主小明#1111',
      );
      hostSession.onSendFrame = (frame) => hostSentFrames.add(frame);
      await hostSession.createRoom(startAudio: false);

      // 房主在只有自己时发送 2 条消息
      await hostSession.sendChat('第一条开房公告');
      await hostSession.sendChat('第二条房间规则');
      expect(hostSession.chatMessages.length, 2);

      hostSentFrames.clear();

      // 新成员 Client 加入房间
      final joinReq = Frame(
        type: FrameType.joinReq,
        senderId: 0,
        seq: 1,
        payload: JoinRequestPayload(
          nickname: '新伙伴#2222',
          sessionToken: Uint8List(16),
        ).encode(),
      );
      hostSession.handleIncomingFrame(joinReq);

      // 验证 Host 发出了 chatSync 历史补发帧
      final syncFrames = hostSentFrames.where((f) => f.type == FrameType.chatSync).toList();
      expect(syncFrames.length, 2);

      // 模拟 Client 端接收这些 chatSync 帧
      final clientSession = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '新伙伴#2222',
      );
      // 模拟 Client 收到 Roster 并确认 selfMemberId = 2
      clientSession.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 2,
        payload: RosterPayload(
          hostId: 1,
          members: [
            RosterMember(memberId: 1, flags: 0x01, nickname: '房主小明#1111'),
            RosterMember(memberId: 2, flags: 0x00, nickname: '新伙伴#2222'),
          ],
        ).encode(),
      ));

      // Client 接收 2 个同步帧
      for (final sf in syncFrames) {
        clientSession.handleIncomingFrame(sf);
      }

      // 验证新加入成员成功看到了进房之前的所有历史消息
      expect(clientSession.chatMessages.length, 2);
      expect(clientSession.chatMessages[0].text, '第一条开房公告');
      expect(clientSession.chatMessages[1].text, '第二条房间规则');
    });

    test('跨退出改名识别：同一设备短码改名重入后正确识别同人并关联曾用名', () async {
      final session = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '房主#0000',
      );
      await session.createRoom(startAudio: false);

      // 1. 成员以原名「探索者#3F7A」发消息
      session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: RosterPayload(
          hostId: 1,
          members: [
            RosterMember(memberId: 1, flags: 0x01, nickname: '房主#0000'),
            RosterMember(memberId: 2, flags: 0x00, nickname: '探索者#3F7A'),
          ],
        ).encode(),
      ));

      await session.handleIncomingFrame(Frame(
        type: FrameType.chat,
        senderId: 2,
        seq: 10,
        payload: const ChatMessagePayload(
          text: '我是探索者，大家好！',
          senderCode: '3F7A',
        ).encode(),
      ));

      expect(session.chatMessages.first.senderNickname, '探索者');
      expect(session.chatMessages.first.previousNickname, isNull);

      // 2. 该成员退房后改名为「银河旅行家#3F7A」，携带相同短码重新进房
      session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 2,
        payload: RosterPayload(
          hostId: 1,
          members: [
            RosterMember(memberId: 1, flags: 0x01, nickname: '房主#0000'),
            RosterMember(memberId: 2, flags: 0x00, nickname: '银河旅行家#3F7A'),
          ],
        ).encode(),
      ));

      // 验证：历史消息的昵称同步更新，并标注曾用名「探索者」
      expect(session.chatMessages.first.senderNickname, '银河旅行家');
      expect(session.chatMessages.first.previousNickname, '探索者');

      // 3. 该成员再次发送新消息
      await session.handleIncomingFrame(Frame(
        type: FrameType.chat,
        senderId: 2,
        seq: 11,
        payload: const ChatMessagePayload(
          text: '我改名了，现在叫银河旅行家',
          senderCode: '3F7A',
        ).encode(),
      ));

      expect(session.chatMessages.length, 2);
      expect(session.chatMessages.last.senderNickname, '银河旅行家');
      expect(session.chatMessages.last.previousNickname, '探索者');
    });

    test('全员撤回与删除消息：本人可撤回，他人无法伪造撤回，各端同步移除', () async {
      final sentFrames = <Frame>[];
      final session = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '探索者#AAAA',
      );
      session.onSendFrame = (frame) => sentFrames.add(frame);
      await session.createRoom(startAudio: false);

      // 本机发送消息
      await session.sendChat('这是一条发错的消息，准备撤回');
      expect(session.chatMessages.length, 1);
      final myMsg = session.chatMessages.first;

      // 撤回自己的消息
      await session.recallMessage(myMsg.messageId);

      // 验证：本地消息已被移除
      expect(session.chatMessages, isEmpty);

      // 验证：广播了 FrameType.chatDelete 帧
      final delFrame = sentFrames.firstWhere((f) => f.type == FrameType.chatDelete);
      expect(delFrame, isNotNull);
      final delPayload = ChatDeletePayload.decode(delFrame.payload);
      expect(delPayload!.senderCode, DeviceCode.current);
      expect(delPayload.messageId, myMsg.messageId);

      // 模拟远端收到该 chatDelete 帧并在远端移除
      final remoteSession = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '伙伴#BBBB',
      );
      await remoteSession.createRoom(startAudio: false);

      // 远端先收到并保存了这条消息
      remoteSession.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: RosterPayload(
          hostId: 1,
          members: [
            RosterMember(memberId: 1, flags: 0x01, nickname: '伙伴#BBBB'),
            RosterMember(memberId: 2, flags: 0x00, nickname: '探索者#AAAA'),
          ],
        ).encode(),
      ));
      await remoteSession.handleIncomingFrame(Frame(
        type: FrameType.chat,
        senderId: 2,
        seq: 5,
        payload: const ChatMessagePayload(
          text: '远端收到的一条消息',
          senderCode: 'AAAA',
          timestampMs: 1725450000000,
        ).encode(),
      ));
      expect(remoteSession.chatMessages.length, 1);
      final remoteMsgId = remoteSession.chatMessages.first.messageId;

      // 攻击场景：有人试图伪造身份 BBBB 去撤回 AAAA 的消息，应被校验拒绝
      remoteSession.handleIncomingFrame(Frame(
        type: FrameType.chatDelete,
        senderId: 3,
        seq: 6,
        payload: const ChatDeletePayload(
          senderCode: 'FAKE',
          messageId: 'AAAA_1725450000000_5',
        ).encode(),
      ));
      expect(remoteSession.chatMessages.length, 1); // 未被删除

      // 合法撤回：作者 AAAA 撤回
      remoteSession.handleIncomingFrame(Frame(
        type: FrameType.chatDelete,
        senderId: 2,
        seq: 7,
        payload: ChatDeletePayload(
          senderCode: 'AAAA',
          messageId: remoteMsgId,
        ).encode(),
      ));
      expect(remoteSession.chatMessages, isEmpty); // 成功被移除
    });

    test('确定性系统头像框：不可自定义，房主专属金辉，成员算法恒定映射', () {
      final hostTheme = AvatarFrameTheme.fromCode('1111', isHost: true);
      expect(hostTheme.name, 'HostCrown');

      // 同一短码始终映射到同一主题
      final themeA1 = AvatarFrameTheme.fromCode('3F7A');
      final themeA2 = AvatarFrameTheme.fromCode('3F7A');
      expect(themeA1.name, themeA2.name);

      // 无论大小写均恒定
      final themeLower = AvatarFrameTheme.fromCode('3f7a');
      expect(themeLower.name, themeA1.name);

      // 房主不受普通短码影响
      final host1 = AvatarFrameTheme.fromCode('AAAA', isHost: true);
      final host2 = AvatarFrameTheme.fromCode('BBBB', isHost: true);
      expect(host1.name, 'HostCrown');
      expect(host2.name, 'HostCrown');
    });
  });
}
