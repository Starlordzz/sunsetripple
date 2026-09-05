import 'dart:typed_data';
import 'package:flutter/material.dart';
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
import 'package:sunset_ripple/l10n/app_strings.dart';
import 'package:sunset_ripple/ui/widgets/avatar_frame.dart';
import 'package:sunset_ripple/ui/widgets/room_chat_sheet.dart';

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

      await hostSession.dispose();
      await clientSession.dispose();
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

      await session.dispose();
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
      expect(delPayload!.senderCode, DeviceCode.toNumeric('AAAA'));
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

      await session.dispose();
      await remoteSession.dispose();
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

    testWidgets('RoomChatSheet 气泡署名：同名冲突显隐与身份徽标', (tester) async {
      final session = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '探索者#${DeviceCode.current}',
      );
      await session.createRoom(startAudio: false);

      // 1. 本机发送的消息（探索者，房主）
      await session.sendChat('我是本地探索者');

      // 2. 远端同名探索者发送的消息
      const remoteExplorerCode = '327';
      session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: RosterPayload(
          hostId: 1,
          members: [
            RosterMember(memberId: 1, flags: 0x01, nickname: '探索者#${DeviceCode.current}'),
            RosterMember(memberId: 2, flags: 0x00, nickname: '探索者#$remoteExplorerCode'),
            RosterMember(memberId: 3, flags: 0x00, nickname: '阿彬#222'),
          ],
        ).encode(),
      ));

      await session.handleIncomingFrame(Frame(
        type: FrameType.chat,
        senderId: 2,
        seq: 2,
        payload: const ChatMessagePayload(
          text: '我是远端同名探索者',
          senderCode: remoteExplorerCode,
        ).encode(),
      ));

      // 3. 远端唯一昵称「阿彬」发送的消息
      await session.handleIncomingFrame(Frame(
        type: FrameType.chat,
        senderId: 3,
        seq: 3,
        payload: const ChatMessagePayload(
          text: '我是阿彬，我的名字独一无二',
          senderCode: '222',
        ).encode(),
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomChatSheet(
              session: session,
              isNight: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final s = AppStrings.of(tester.element(find.byType(RoomChatSheet)));
      // 验证身份徽标
      expect(find.text(s.chatSelfBadge), findsOneWidget);
      expect(find.text(s.hostRoleBadge), findsOneWidget);

      // 验证同名冲突智能显隐：
      // 同名为「探索者」的两位，均显式展示 3 位数字设备码
      expect(find.text('#${DeviceCode.current}'), findsOneWidget);
      expect(find.text('#327'), findsOneWidget);

      // 唯一命名的「阿彬」，设备码被智能隐藏
      expect(find.text('阿彬'), findsOneWidget);
      expect(find.text('#222'), findsNothing);

      await session.dispose();
    });

    testWidgets('平板宽屏软键盘弹起时零 Overflow 测试', (tester) async {
      final session = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '探索者#${DeviceCode.current}',
      );
      await session.createRoom(startAudio: false);

      // 塞入多条消息使列表有充分内容
      for (int i = 1; i <= 8; i++) {
        await session.sendChat('测试聊天消息行 $i');
      }

      // 设置平板横屏尺寸（1024 x 768）
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 模拟底部软键盘弹起 320px 的 viewInsets
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1024, 768),
            padding: EdgeInsets.only(top: 24),
            viewInsets: EdgeInsets.only(bottom: 320),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: RoomChatSheet(
                session: session,
                isNight: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 检查输入框和发送按钮正常可见
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);

      // 检查零 Flutter overflow 错误
      expect(tester.takeException(), isNull);

      await session.dispose();
    });
  });
}
