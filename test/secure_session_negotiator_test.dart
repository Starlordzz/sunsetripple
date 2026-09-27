import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/security/secure_session_negotiator.dart';

/// 安全层此前是**完全不可达的死代码**：`lib/core/security/` 里实现齐全，
/// 但没有任何生产代码调用，`RoomSession` 对握手帧直接 `break`。
/// 这些用例锁住「握手真的能跑完并派生出一致的密钥」这条端到端路径。
void main() {
  Future<(SecureSessionNegotiator, SecureSessionNegotiator)> buildPair() async {
    final host = SecureSessionNegotiator(
      roomId: 'room-1',
      localRole: 'host',
      initiate: true,
    );
    final guest = SecureSessionNegotiator(
      roomId: 'room-1',
      localRole: 'client',
      initiate: false,
    );
    return (host, guest);
  }

  group('SecureSessionNegotiator 端到端', () {
    test('双方交换 Hello 后派生出同一个安全短码，且都被标记为已加密', () async {
      final (host, guest) = await buildPair();
      addTearDown(() async {
        await host.dispose();
        await guest.dispose();
      });

      // 房主发起
      final hostHello = await host.start();
      expect(hostHello, isNotNull);
      expect(hostHello!.type, FrameType.handshakeHello);
      expect(host.isEstablished, isFalse, reason: '只有自己一半时不该建立');

      // 成员收到 → 回自己的 Hello
      final guestReply = await guest.onHello(hostHello);
      expect(guestReply, isNotNull, reason: '响应方必须回一份 Hello');

      // 房主收到回包
      await host.onHello(guestReply!);

      expect(host.isEstablished, isTrue);
      expect(guest.isEstablished, isTrue);
      expect(host.safetyCode, isNotNull);
      expect(
        host.safetyCode,
        guest.safetyCode,
        reason: '短码必须一致，否则用户带外比对永远失败',
      );
      expect(host.safetyCode!.length, 6);
      expect(int.tryParse(host.safetyCode!), isNotNull);
    });

    test('派生的 codec 能双向加解密业务帧', () async {
      final (host, guest) = await buildPair();
      addTearDown(() async {
        await host.dispose();
        await guest.dispose();
      });

      final hostHello = await host.start();
      final guestReply = await guest.onHello(hostHello!);
      await host.onHello(guestReply!);

      final original = Frame(
        type: FrameType.chat,
        senderId: 2,
        seq: 7,
        payload: Uint8List.fromList(utf8.encode('机密消息')),
      );

      final sealed = await guest.codec!.seal(original);
      expect(sealed.type, FrameType.sealed);
      expect(
        sealed.payload,
        isNot(containsAllInOrder(utf8.encode('机密消息'))),
        reason: '密文里不该出现明文',
      );

      final opened = await host.codec!.open(sealed);
      expect(opened.type, FrameType.chat);
      expect(opened.senderId, 2);
      expect(opened.seq, 7);
      expect(utf8.decode(opened.payload), '机密消息');
    });

    test('start() 幂等：重复调用不会生成第二份 Hello', () async {
      final (host, _) = await buildPair();
      addTearDown(host.dispose);

      final first = await host.start();
      final second = await host.start();
      expect(first, isNotNull);
      expect(second, isNull, reason: '重复 start 必须返回 null 而不是新 Hello');
    });

    test('接收到畸形 Hello 不崩溃、不建立 codec', () async {
      final (host, _) = await buildPair();
      addTearDown(host.dispose);

      final garbage = Frame(
        type: FrameType.handshakeHello,
        senderId: 0,
        seq: 0,
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );
      expect(await host.onHello(garbage), isNull);
      expect(host.isEstablished, isFalse);
    });

    test('字段为空的 Hello 被拒绝（不把异常抛给调用方）', () async {
      final (host, _) = await buildPair();
      addTearDown(host.dispose);

      final empty = Frame(
        type: FrameType.handshakeHello,
        senderId: 0,
        seq: 0,
        payload: Uint8List.fromList(utf8.encode(jsonEncode({
          'publicKey': '',
          'nonce': 'abc',
          'signature': 'sig',
        }))),
      );
      expect(await host.onHello(empty), isNull);
      expect(host.isEstablished, isFalse);
    });

    test('房间上下文不同（roomId 不一致）导致验签失败，保持明文', () async {
      final a = SecureSessionNegotiator(
        roomId: 'room-A',
        localRole: 'host',
        initiate: true,
      );
      final b = SecureSessionNegotiator(
        roomId: 'room-B',
        localRole: 'client',
        initiate: false,
      );
      addTearDown(() async {
        await a.dispose();
        await b.dispose();
      });

      final aHello = await a.start();
      final bReply = await b.onHello(aHello!);
      await a.onHello(bReply!);

      expect(
        a.isEstablished,
        isFalse,
        reason: 'roomId 参与签名转录，不一致时签名必然验不过',
      );
      expect(b.isEstablished, isFalse);
    });
  });

  group('安全短码派生', () {
    test('与参数顺序无关（两侧算出的必须相同）', () {
      const keyA = 'AAA';
      const keyB = 'BBB';
      expect(
        SecureSessionState.deriveSafetyCode(keyA, keyB),
        SecureSessionState.deriveSafetyCode(keyB, keyA),
      );
    });

    test('不同公钥组合得到不同短码', () {
      final code1 = SecureSessionState.deriveSafetyCode('key-1', 'key-2');
      final code2 = SecureSessionState.deriveSafetyCode('key-1', 'key-3');
      expect(code1, isNot(code2));
    });

    test('始终是 6 位十进制（含前导零）', () {
      for (var i = 0; i < 50; i++) {
        final code = SecureSessionState.deriveSafetyCode('k$i', 'j$i');
        expect(code.length, 6);
        expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);
      }
    });
  });

  group('协商阶段状态', () {
    test('阶段推进：idle → helloSent → established → confirmed', () async {
      final (host, guest) = await buildPair();
      addTearDown(() async {
        await host.dispose();
        await guest.dispose();
      });

      final phases = <SecureSessionPhase>[];
      final sub = host.stateStream.listen((s) => phases.add(s.phase));
      addTearDown(sub.cancel);

      final hostHello = await host.start();
      final guestReply = await guest.onHello(hostHello!);
      await host.onHello(guestReply!);
      host.confirmByUser();
      await Future<void>.delayed(Duration.zero);

      expect(phases, contains(SecureSessionPhase.helloSent));
      expect(phases, contains(SecureSessionPhase.established));
      expect(phases.last, SecureSessionPhase.confirmed);
    });
  });
}
