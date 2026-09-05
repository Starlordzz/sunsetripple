import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/chat_message.dart';
import 'package:sunset_ripple/core/security/session_crypto.dart';
import 'package:sunset_ripple/core/security/session_handshake.dart';
import 'package:sunset_ripple/core/session/room_session.dart';

void main() {
  group('SessionCrypto Tests', () {
    test('DeviceIdentity generates valid fingerprint, shortCode, and signs payloads', () async {
      final identity = await DeviceIdentity.generate();
      expect(identity.publicKeyBase64.isNotEmpty, isTrue);
      expect(identity.fingerprint.split(':').length, 32);
      expect(RegExp(r'^\d{3} \d{3}$').hasMatch(identity.shortCode), isTrue);

      final message = Uint8List.fromList(utf8.encode('Hello SunsetRipple'));
      final signature = await identity.sign(message);
      expect(signature.isNotEmpty, isTrue);

      final isValid = await verifyDeviceSignature(
        identity.publicKeyBase64,
        message,
        signature,
      );
      expect(isValid, isTrue);

      final tampered = Uint8List.fromList(utf8.encode('Hello Tampered'));
      final isTamperedValid = await verifyDeviceSignature(
        identity.publicKeyBase64,
        tampered,
        signature,
      );
      expect(isTamperedValid, isFalse);
    });

    test('SessionCipher roundtrip encryption and decryption with AAD', () async {
      final keyBytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        keyBytes[i] = i + 1;
      }
      final cipher = await SessionCipher.fromKey(keyBytes);

      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final aad = Uint8List.fromList([0xAA, 0xBB]);

      final packet = await cipher.encrypt(plaintext, associatedData: aad);
      expect(packet.nonce.length, SessionCipher.nonceBytes);
      expect(packet.ciphertext.length, plaintext.length + SessionCipher.tagBytes);

      final decrypted = await cipher.decrypt(packet, associatedData: aad);
      expect(decrypted, equals(plaintext));
    });

    test('SessionCipher rejects corrupted ciphertext or wrong tag', () async {
      final keyBytes = Uint8List(32);
      final cipher = await SessionCipher.fromKey(keyBytes);

      final plaintext = Uint8List.fromList([10, 20, 30]);
      final packet = await cipher.encrypt(plaintext);

      // Tamper ciphertext
      final corruptedCt = Uint8List.fromList(packet.ciphertext);
      corruptedCt[0] ^= 0xFF;
      final corruptedPacket = EncryptedPacket(
        nonce: packet.nonce,
        ciphertext: corruptedCt,
      );

      expect(
        () async => await cipher.decrypt(corruptedPacket),
        throwsA(isA<Exception>()),
      );
    });

    test('SessionCipher rejects replayed nonces', () async {
      final keyBytes = Uint8List(32);
      final cipher = await SessionCipher.fromKey(keyBytes);

      final plaintext = Uint8List.fromList([1, 2, 3]);
      final packet = await cipher.encrypt(plaintext);

      final dec1 = await cipher.decrypt(packet);
      expect(dec1, equals(plaintext));

      // Second decryption of the same packet with identical nonce must throw StateError
      expect(
        () async => await cipher.decrypt(packet),
        throwsStateError,
      );
    });
  });

  group('SessionHandshake & SecureFrameCodec Tests', () {
    test('Handshake establishes matching ciphers and seals/opens frames', () async {
      final host = await DeviceIdentity.generate();
      final guest = await DeviceIdentity.generate();
      const roomId = 'sunset-test-room-101';

      final hostHello = await SessionHandshake.create(
        identity: host,
        roomId: roomId,
        role: 'host',
      );
      final guestHello = await SessionHandshake.create(
        identity: guest,
        roomId: roomId,
        role: 'guest',
      );

      final hostCipher = await SessionHandshake.establish(
        localIdentity: host,
        localHello: hostHello,
        remoteHello: guestHello,
        remoteRole: 'guest',
        roomId: roomId,
      );

      final guestCipher = await SessionHandshake.establish(
        localIdentity: guest,
        localHello: guestHello,
        remoteHello: hostHello,
        remoteRole: 'host',
        roomId: roomId,
      );

      final hostCodec = SecureFrameCodec(hostCipher);
      final guestCodec = SecureFrameCodec(guestCipher);

      final originalFrame = Frame(
        type: FrameType.audio,
        senderId: 2,
        seq: 42,
        payload: Uint8List.fromList([0x12, 0x34, 0x56, 0x78]),
      );

      // Host seals -> guest opens
      final sealedFrame = await hostCodec.seal(originalFrame);
      expect(sealedFrame.type, FrameType.sealed);
      expect(sealedFrame.senderId, originalFrame.senderId);
      expect(sealedFrame.seq, originalFrame.seq);

      final openedFrame = await guestCodec.open(sealedFrame);
      expect(openedFrame.type, originalFrame.type);
      expect(openedFrame.senderId, originalFrame.senderId);
      expect(openedFrame.seq, originalFrame.seq);
      expect(openedFrame.payload, equals(originalFrame.payload));
    });

    test('Handshake fails when remote signature is invalid', () async {
      final host = await DeviceIdentity.generate();
      final guest = await DeviceIdentity.generate();
      const roomId = 'sunset-test-room-102';

      final hostHello = await SessionHandshake.create(
        identity: host,
        roomId: roomId,
        role: 'host',
      );
      final guestHello = await SessionHandshake.create(
        identity: guest,
        roomId: roomId,
        role: 'guest',
      );

      // Tamper guest signature
      final tamperedGuestHello = SignedHello(
        publicKeyBase64: guestHello.publicKeyBase64,
        nonceBase64: guestHello.nonceBase64,
        signatureBase64: base64.encode(Uint8List(64)),
      );

      expect(
        () async => await SessionHandshake.establish(
          localIdentity: host,
          localHello: hostHello,
          remoteHello: tamperedGuestHello,
          remoteRole: 'guest',
          roomId: roomId,
        ),
        throwsStateError,
      );
    });

    test('SecureFrameCodec rejects already sealed frame or mismatched header', () async {
      final keyBytes = Uint8List(32);
      final cipher = await SessionCipher.fromKey(keyBytes);
      final codec = SecureFrameCodec(cipher);

      final frame = Frame(
        type: FrameType.sealed,
        senderId: 1,
        seq: 1,
        payload: Uint8List(30),
      );

      expect(() async => await codec.seal(frame), throwsArgumentError);
    });

    test('RoomSession chat sealing pipeline: unsealed by default, sealed when secureCodec is set', () async {
      final sent = <Frame>[];
      final session = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '加密测试者',
      );
      session.onSendFrame = sent.add;
      await session.createRoom();

      // 1. Default production state (secureCodec == null): sends plain FrameType.chat
      expect(session.secureCodec, isNull);
      await session.sendChat('明文兼容消息');
      expect(sent.last.type, FrameType.chat);

      // 2. When secureCodec is configured: automatically seals to FrameType.sealed
      final keyBytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        keyBytes[i] = i + 1;
      }
      final cipher = await SessionCipher.fromKey(keyBytes);
      final codec = SecureFrameCodec(cipher);
      session.secureCodec = codec;

      await session.sendChat('机密聊天消息');
      final sealedFrame = sent.last;
      expect(sealedFrame.type, FrameType.sealed);

      // 3. Opening the sealed frame restores the original FrameType.chat and text
      final openedFrame = await codec.open(sealedFrame);
      expect(openedFrame.type, FrameType.chat);
      expect(openedFrame.senderId, session.selfMemberId);

      final payload = ChatMessagePayload.decode(openedFrame.payload);
      expect(payload, isNotNull);
      expect(payload!.text, '机密聊天消息');

      await session.dispose();
    });
  });
}

