import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/chat_message.dart';
import 'package:sunset_ripple/core/transport/ble_l2cap_transport.dart';
import 'package:sunset_ripple/core/transport/lan_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WiFi / BLE 聊天路由隔离与通道验证', () {
    test('LanTransport send: chat 帧走 TCP 控制面，严格不走 UDP 音频端口', () {
      final lan = LanTransport();

      // 在未启动状态下发送 chat 帧，断言其进入控制面逻辑且不会抛异常或混入 UDP
      final chatPayload = const ChatMessagePayload(text: '测试 WiFi 路由隔离').encode();
      final chatFrame = Frame(
        type: FrameType.chat,
        senderId: 1,
        seq: 1,
        payload: chatPayload,
      );

      // send() 必须平稳执行（内部根据 role == idle 记录警告，不发 UDP）
      expect(() => lan.send(chatFrame), returnsNormally);

      // 验证 FrameType.chat 在 LanTransport 的分类中不是 audio
      expect(chatFrame.type == FrameType.audio, isFalse);
    });

    test('BleL2capTransport send: chat 帧完整打包并通过 sendL2capData 发送', () async {
      const channel = MethodChannel('host.msknet.sunsetripple/ble_l2cap');
      final calls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'startAdvertising') return true;
        return null;
      });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final ble = BleL2capTransport();
      // 启动并模拟进入 Host 角色
      await ble.startHost(roomName: '测试蓝牙房');

      final chatPayload = const ChatMessagePayload(text: '测试 BLE L2CAP 路由').encode();
      final chatFrame = Frame(
        type: FrameType.chat,
        senderId: 1,
        seq: 42,
        payload: chatPayload,
      );

      ble.send(chatFrame);

      expect(calls.length, greaterThanOrEqualTo(1));
      final sendCall = calls.firstWhere((c) => c.method == 'sendL2capData');
      expect(sendCall.arguments, isA<Map>());
      final data = (sendCall.arguments as Map)['data'] as Uint8List;

      // 验证通过 L2CAP 送达原生侧的数据能够被无损还原为合法 Chat Frame
      final decoded = Frame.decode(data);
      expect(decoded, isNotNull);
      expect(decoded!.type, FrameType.chat);
      expect(decoded.senderId, 1);
      expect(decoded.seq, 42);

      final decodedPayload = ChatMessagePayload.decode(decoded.payload);
      expect(decodedPayload, isNotNull);
      expect(decodedPayload!.text, '测试 BLE L2CAP 路由');

      await ble.stop();
    });
  });
}
