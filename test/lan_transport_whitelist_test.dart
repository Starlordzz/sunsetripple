import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/transport/lan_transport.dart';

/// 轮询直到 [probe] 为 true 或超时。真实回环 socket 的收发是异步的，
/// 固定 sleep 既慢又脆，轮询是单元测试里最稳的同步方式。
Future<void> pumpUntil(
  bool Function() probe, {
  Duration timeout = const Duration(seconds: 2),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (probe()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('pumpUntil 超时：${reason ?? '条件未满足'}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanTransport UDP 白名单', () {
    test('不在册 senderId 的帧不注册语音端点、不转发给其他成员', () async {
      final host = LanTransport();
      expect(
        await host.startHost(),
        isTrue,
        reason: '测试需要绑定 TCP 8988 / UDP 8989，端口被占用时先关掉正在运行的应用',
      );
      addTearDown(() => host.stop());

      // 名单由 RoomSession 的名单广播驱动，这里直接注入测试成员。
      host.updateKnownMemberIds({2, 3});

      final speaker = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final listener = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() {
        speaker.close();
        listener.close();
      });

      final received = <Frame>[];
      listener.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = listener.receive();
        if (datagram == null) return;
        final frame = Frame.decode(datagram.data);
        if (frame != null) received.add(frame);
      });

      Frame heartbeat(int id) => Frame(
            type: FrameType.heartbeat,
            senderId: id,
            seq: 0,
            payload: Uint8List(0),
          );

      // 成员 2、3 各自用 UDP 心跳在房主侧登记语音端点。
      speaker.send(
        heartbeat(2).encode(),
        InternetAddress.loopbackIPv4,
        LanTransport.audioPort,
      );
      await pumpUntil(
        () => host.peerEndpoints.containsKey(2),
        reason: '在册成员的心跳必须登记语音端点',
      );
      listener.send(
        heartbeat(3).encode(),
        InternetAddress.loopbackIPv4,
        LanTransport.audioPort,
      );
      await pumpUntil(
        () => host.peerEndpoints.containsKey(3),
        reason: '在册成员的心跳必须登记语音端点',
      );

      // 在册成员 2 说话 → 房主转发给成员 3。
      final audio = Frame(
        type: FrameType.audio,
        senderId: 2,
        seq: 1,
        payload: Uint8List(60),
      );
      speaker.send(
        audio.encode(),
        InternetAddress.loopbackIPv4,
        LanTransport.audioPort,
      );
      await pumpUntil(
        () => received.any((f) => f.type == FrameType.audio && f.senderId == 2),
        reason: '在册成员的音频必须被转发给其他成员',
      );

      // 局域网内伪造的 senderId 99 → 不登记端点、不转发。
      final forged = Frame(
        type: FrameType.audio,
        senderId: 99,
        seq: 2,
        payload: Uint8List(60),
      );
      speaker.send(
        forged.encode(),
        InternetAddress.loopbackIPv4,
        LanTransport.audioPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        received.where((f) => f.senderId == 99),
        isEmpty,
        reason: '不在册成员号的帧必须在传输层丢弃，不能借房主转发',
      );
      expect(host.peerEndpoints.containsKey(99), isFalse,
          reason: '伪造帧不能在房主侧凭空登记语音端点');
    });
  });
}
