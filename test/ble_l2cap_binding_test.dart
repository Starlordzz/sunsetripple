import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/join_request.dart';
import 'package:sunset_ripple/core/transport/ble_l2cap_transport.dart';

/// 蓝牙房的链路↔成员号绑定。
///
/// 为什么必须测：L2CAP 是链路寻址，客户端之间物理上无法直连，接收端没有
/// TCP 那样「按连接身份重写 senderId」的机会。房主若不绑定并重写，任何成员
/// 都能把帧头 senderId 填成别人的号——冒用身份发言、撤回、伪造 PTT 状态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('host.msknet.sunsetripple/ble_l2cap');
  const dataChannel = EventChannel('host.msknet.sunsetripple/ble_l2cap_data');

  late List<Map<String, Object?>> invoked;
  StreamController<dynamic>? dataEvents;

  setUp(() {
    invoked = <Map<String, Object?>>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      invoked.add({'method': call.method, 'args': call.arguments});
      switch (call.method) {
        case 'startAdvertising':
          return true;
        case 'stop':
        case 'bindMember':
        case 'unbindMember':
          return true;
        default:
          return null;
      }
    });

    dataEvents = StreamController<dynamic>.broadcast();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      dataChannel,
      MockStreamHandler.inline(
        onListen: (arguments, sink) => dataEvents!.stream.listen(sink.success),
      ),
    );
  });

  tearDown(() async {
    await dataEvents?.close();
    dataEvents = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(dataChannel, null);
  });

  Uint8List token(int seed) => Uint8List.fromList(
        List<int>.generate(16, (i) => (seed + i + 1) & 0xFF),
      );

  /// 模拟原生侧上抛一帧。
  Future<void> emitFromPeer(String peer, Frame frame) async {
    dataEvents!.add({
      'data': frame.encode(),
      'peerAddress': peer,
    });
    // 让广播流把事件投递到订阅者（transport 内部）。
    await Future<void>.delayed(Duration.zero);
  }

  group('BleL2capTransport 链路身份绑定', () {
    test('JOIN 到达后按会话令牌把成员号绑到正确链路', () async {
      final transport = BleL2capTransport();
      await transport.startHost(roomName: '蓝牙房');
      addTearDown(transport.dispose);

      final alpha = token(1);
      final beta = token(2);

      // 两条链路各自发 JOIN——如果不按 token 匹配，就会发生串号。
      await emitFromPeer(
          'AA:01',
          Frame(
            type: FrameType.joinReq,
            senderId: 0,
            seq: 1,
            payload:
                JoinRequestPayload(nickname: 'A', sessionToken: alpha).encode(),
          ));
      await emitFromPeer(
          'BB:02',
          Frame(
            type: FrameType.joinReq,
            senderId: 0,
            seq: 2,
            payload:
                JoinRequestPayload(nickname: 'B', sessionToken: beta).encode(),
          ));

      // RoomSession 逐个回绑：先 beta（成员号 3），再 alpha（成员号 2）。
      transport.bindMemberForSessionToken(beta, 3);
      transport.bindMemberForSessionToken(alpha, 2);
      await Future<void>.delayed(Duration.zero);

      final binds = invoked
          .where((c) => c['method'] == 'bindMember')
          .map((c) => c['args'] as Map)
          .toList();

      expect(binds.length, 2, reason: '两条链路都必须各绑定一次');
      expect(
        binds.firstWhere((a) => a['memberId'] == 3)['peerAddress'],
        'BB:02',
        reason: 'token beta 属于 BB:02，不能绑到 AA:01',
      );
      expect(
        binds.firstWhere((a) => a['memberId'] == 2)['peerAddress'],
        'AA:01',
        reason: 'token alpha 属于 AA:01，不能绑到 BB:02',
      );
    });

    test('removeMember 解绑对应链路', () async {
      final transport = BleL2capTransport();
      await transport.startHost(roomName: '蓝牙房');
      addTearDown(transport.dispose);

      final alpha = token(7);
      await emitFromPeer(
          'CC:03',
          Frame(
            type: FrameType.joinReq,
            senderId: 0,
            seq: 1,
            payload:
                JoinRequestPayload(nickname: 'C', sessionToken: alpha).encode(),
          ));
      transport.bindMemberForSessionToken(alpha, 4);
      await Future<void>.delayed(Duration.zero);

      transport.removeMember(4);
      await Future<void>.delayed(Duration.zero);

      final unbinds = invoked.where((c) => c['method'] == 'unbindMember');
      expect(unbinds.length, 1, reason: '成员离开必须解绑，否则链路复用时身份串台');
      expect((unbinds.single['args'] as Map)['memberId'], 4);
    });

    test('客户端角色不发起绑定（只有房主重写转发）', () async {
      final transport = BleL2capTransport();
      addTearDown(transport.dispose);

      // 未 startHost（角色仍是 idle/client）时不应把 bindMember 打到原生层。
      transport.bindMemberForSessionToken(token(9), 5);
      await Future<void>.delayed(Duration.zero);

      expect(
        invoked.where((c) => c['method'] == 'bindMember'),
        isEmpty,
        reason: '成员侧没有链路表，绑定是房主独有职责',
      );
    });

    test('stop() 清空绑定表，避免复用实例时串号', () async {
      final transport = BleL2capTransport();
      await transport.startHost(roomName: '蓝牙房');
      addTearDown(transport.dispose);

      final alpha = token(11);
      await emitFromPeer(
          'DD:04',
          Frame(
            type: FrameType.joinReq,
            senderId: 0,
            seq: 1,
            payload:
                JoinRequestPayload(nickname: 'D', sessionToken: alpha).encode(),
          ));
      transport.bindMemberForSessionToken(alpha, 6);
      await Future<void>.delayed(Duration.zero);
      invoked.clear();

      await transport.stop();
      await transport.startHost(roomName: '蓝牙房2');

      // 重新入房后同一个 token 必须重新绑定，不能复用上一轮的映射。
      await emitFromPeer(
          'EE:05',
          Frame(
            type: FrameType.joinReq,
            senderId: 0,
            seq: 2,
            payload:
                JoinRequestPayload(nickname: 'E', sessionToken: alpha).encode(),
          ));
      transport.bindMemberForSessionToken(alpha, 7);
      await Future<void>.delayed(Duration.zero);

      final bind = invoked.firstWhere((c) => c['method'] == 'bindMember');
      expect((bind['args'] as Map)['peerAddress'], 'EE:05');
      expect((bind['args'] as Map)['memberId'], 7);
    });
  });
}
