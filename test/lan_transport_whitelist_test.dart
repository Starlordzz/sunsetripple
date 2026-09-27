import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/join_request.dart';
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
      // 端口 0 = 内核分配临时端口。固定端口会让并行运行的测试文件互相抢
      // 同一个 socket（原先用 shared:true 时两次 bind 都成功，连接却被内核
      // 随机分给其中一个），表现为随机失败。
      expect(await host.startHost(port: 0), isTrue, reason: '临时端口绑定失败');
      addTearDown(() => host.stop());
      final hostAudioPort = host.boundAudioPort;

      // 名单由 RoomSession 的名单广播驱动，这里直接注入测试成员。
      host.updateKnownMemberIds({2, 3});

      final speaker =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final listener =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
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
        hostAudioPort,
      );
      await pumpUntil(
        () => host.peerEndpoints.containsKey(2),
        reason: '在册成员的心跳必须登记语音端点',
      );
      listener.send(
        heartbeat(3).encode(),
        InternetAddress.loopbackIPv4,
        hostAudioPort,
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
        hostAudioPort,
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
        hostAudioPort,
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

  /// TCP 控制流的帧重组。半帧要留到下一次回调补齐，且只能交付一次；
  /// 同一段字节流不能因为缓冲容量不足而丢掉尾巴。
  ///
  /// 宿主测试里原生库不存在，走纯 Dart 分支；真机上原生环形缓冲可用。
  /// 环形缓冲的容量必须放得下 Dart 单次 socket 读取的上限（64 KiB），
  /// 否则 `sunset_ring_buffer_write` 会短写，剩下的字节就是丢掉的帧，
  /// 帧头从此失去对齐——实测 99000 字节的突发只交付了 992/1500 帧。
  group('TCP 控制流重组', () {
    final token = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));

    /// 起房主、连一个客户端，并等 JOIN 被处理完（成员号绑定成功）之后再
    /// 返回，这样后续突发的每一帧都已经有明确归属。
    Future<(LanTransport, Socket, List<Frame>)> startHostWithClient() async {
      final host = LanTransport();
      final received = <Frame>[];
      var bound = false;
      host.incoming.listen((frame) {
        received.add(frame);
        if (frame.type == FrameType.joinReq && !bound) {
          bound = true;
          host.bindMemberForSessionToken(token, 2);
        }
      });

      // 临时端口：固定 8988/8989 会与并行运行的其它测试文件抢同一个 socket。
      expect(await host.startHost(port: 0), isTrue, reason: '临时端口绑定失败');
      final client = await Socket.connect(
          InternetAddress.loopbackIPv4, host.boundControlPort);

      client.add(Uint8List.fromList(Frame(
        type: FrameType.joinReq,
        senderId: 0,
        seq: 0,
        payload:
            JoinRequestPayload(nickname: 'n', sessionToken: token).encode(),
      ).encode()));
      await client.flush();
      await pumpUntil(() => bound, reason: 'JOIN 必须先被处理');

      return (host, client, received);
    }

    test('半帧跨两次读取续传：不重复交付、不打乱顺序、载荷完整', () async {
      final (host, client, received) = await startHostWithClient();
      addTearDown(() => host.stop());
      addTearDown(() => client.destroy());

      final roster = Frame(
        type: FrameType.roster,
        senderId: 2,
        seq: 9,
        payload: Uint8List(200),
      ).encode();

      // 第一批只送出帧头的前 3 字节，等它被处理完之后再送剩下的部分，
      // 这样两批字节确实分属两次 socket 读取。
      client.add(Uint8List.fromList(roster.sublist(0, 3)));
      await client.flush();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      client.add(Uint8List.fromList(roster.sublist(3)));
      await client.flush();
      await pumpUntil(
        () => received.any((f) => f.type == FrameType.roster),
        reason: '半帧必须被补齐',
      );
      // 留出时间，确认没有多出来的重复帧。
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final rosters =
          received.where((f) => f.type == FrameType.roster).toList();
      expect(rosters.length, 1, reason: '同一帧不能被交付两次');
      expect(rosters.single.seq, 9);
      expect(rosters.single.payload.length, 200, reason: '载荷长度必须完整');
    });
  });
}
