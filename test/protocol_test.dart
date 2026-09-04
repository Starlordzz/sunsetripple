import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/chat_message.dart';
import 'package:sunset_ripple/core/protocol/payloads/join_request.dart';
import 'package:sunset_ripple/core/protocol/payloads/leave.dart';
import 'package:sunset_ripple/core/protocol/payloads/ptt_state.dart';
import 'package:sunset_ripple/core/protocol/payloads/roster.dart';

void main() {
  group('SunsetRipple Binary Protocol Tests', () {
    test('Frame encode and decode roundtrip', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final original = Frame(
        type: FrameType.audio,
        senderId: 2,
        seq: 1024,
        payload: payload,
      );

      final encoded = original.encode();
      expect(encoded.length, Frame.headerSize + 5);

      final decoded = Frame.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.type, FrameType.audio);
      expect(decoded.senderId, 2);
      expect(decoded.seq, 1024);
      expect(decoded.payload, equals(payload));
    });

    test('JoinRequestPayload encode and decode', () {
      final token = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        token[i] = i;
      }

      final payload = JoinRequestPayload(
        nickname: "落日测试员",
        sessionToken: token,
      );

      final encoded = payload.encode();
      final decoded = JoinRequestPayload.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.nickname, "落日测试员");
      expect(decoded.sessionToken, equals(token));
    });

    test('RosterPayload encode and decode', () {
      final members = [
        RosterMember(memberId: 1, flags: 0x01, nickname: "房主"),
        RosterMember(memberId: 2, flags: 0x04, nickname: "讲话者"),
        RosterMember(memberId: 3, flags: 0x02, nickname: "静音者"),
      ];

      final payload = RosterPayload(hostId: 1, members: members);
      final encoded = payload.encode();
      final decoded = RosterPayload.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.hostId, 1);
      expect(decoded.members.length, 3);
      expect(decoded.members[0].isHost, isTrue);
      expect(decoded.members[1].isSpeaking, isTrue);
      expect(decoded.members[2].isMuted, isTrue);
      expect(decoded.members[1].nickname, "讲话者");
    });

    test('PttStatePayload encode and decode', () {
      final pttOn = PttStatePayload(isPressed: true);
      final decodedOn = PttStatePayload.decode(pttOn.encode());
      expect(decodedOn!.isPressed, isTrue);

      final pttOff = PttStatePayload(isPressed: false);
      final decodedOff = PttStatePayload.decode(pttOff.encode());
      expect(decodedOff!.isPressed, isFalse);
    });

    test('LeavePayload encode and decode', () {
      final leave = LeavePayload(reason: 1);
      final decoded = LeavePayload.decode(leave.encode());
      expect(decoded!.reason, 1);
    });

    test('FrameType.chat has value 0x0c and existing types are preserved', () {
      expect(FrameType.chat.value, 0x0c);
      expect(FrameType.fromValue(0x0c), FrameType.chat);
      expect(FrameType.audio.value, 0x01);
      expect(FrameType.sealed.value, 0x0b);
      expect(FrameType.fromValue(0x99), isNull);
    });

    group('ChatMessagePayload Tests', () {
      test('Chat payload roundtrip with ASCII, Chinese, and Emoji', () {
        const sample = '你好 SunsetRipple 🌅 👨‍👩‍👧‍👦 测试消息 123!';
        const payload = ChatMessagePayload(text: sample);
        final encoded = payload.encode();

        expect(encoded[0], 1); // version
        final len = ByteData.sublistView(encoded).getUint16(1, Endian.big);
        expect(len, encoded.length - 3);

        final decoded = ChatMessagePayload.decode(encoded);
        expect(decoded, isNotNull);
        expect(decoded!.version, 1);
        expect(decoded.text, sample);
        expect(decoded, equals(payload));
      });

      test('Empty or whitespace text throws ArgumentError on encode', () {
        expect(() => const ChatMessagePayload(text: '').encode(), throwsArgumentError);
        expect(() => const ChatMessagePayload(text: '   \n\t  ').encode(), throwsArgumentError);
      });

      test('Boundary: exactly 480 UTF-8 bytes succeeds, 481 throws ArgumentError', () {
        // 480 ASCII bytes
        final validText = 'A' * 480;
        final payload = ChatMessagePayload(text: validText);
        final encoded = payload.encode();
        expect(encoded.length, 483);
        final decoded = ChatMessagePayload.decode(encoded);
        expect(decoded!.text, validText);

        // 481 ASCII bytes
        final invalidText = 'A' * 481;
        expect(
          () => ChatMessagePayload(text: invalidText).encode(),
          throwsArgumentError,
        );

        // Multi-byte boundary: 160 Chinese characters = 160 * 3 = 480 bytes
        final validChinese = '中' * 160;
        expect(ChatMessagePayload(text: validChinese).encode().length, 483);

        // 160 Chinese + 1 byte = 481 bytes
        expect(
          () => ChatMessagePayload(text: '${validChinese}a').encode(),
          throwsArgumentError,
        );
      });

      test('Decode rejects invalid version, wrong length, trailing bytes, or malformed UTF-8', () {
        // Less than 3 bytes
        expect(ChatMessagePayload.decode(Uint8List.fromList([1, 0])), isNull);

        // Wrong version (e.g. 2)
        final valid = const ChatMessagePayload(text: 'Hello').encode();
        final wrongVer = Uint8List.fromList(valid);
        wrongVer[0] = 2;
        expect(ChatMessagePayload.decode(wrongVer), isNull);

        // Length mismatch (header says 10, actual data has 5)
        final badLen = Uint8List.fromList(valid);
        ByteData.sublistView(badLen).setUint16(1, 10, Endian.big);
        expect(ChatMessagePayload.decode(badLen), isNull);

        // Trailing extra bytes
        final trailing = Uint8List.fromList([...valid, 99, 99]);
        expect(ChatMessagePayload.decode(trailing), isNull);

        // Malformed UTF-8 sequence
        final malformed = Uint8List.fromList([1, 0, 2, 0xFF, 0xFF]);
        expect(ChatMessagePayload.decode(malformed), isNull);
      });

      test('Frame with FrameType.chat encode and decode roundtrip within 512 bytes limit', () {
        const chatPayload = ChatMessagePayload(text: '落日后残波近场聊天测试');
        final rawPayload = chatPayload.encode();
        expect(rawPayload.length, lessThanOrEqualTo(Frame.maxPayloadSize));

        final frame = Frame(
          type: FrameType.chat,
          senderId: 3,
          seq: 42,
          payload: rawPayload,
        );

        final frameBytes = frame.encode();
        expect(frameBytes.length, Frame.headerSize + rawPayload.length);

        final decodedFrame = Frame.decode(frameBytes);
        expect(decodedFrame, isNotNull);
        expect(decodedFrame!.type, FrameType.chat);
        expect(decodedFrame.senderId, 3);
        expect(decodedFrame.seq, 42);

        final decodedChat = ChatMessagePayload.decode(decodedFrame.payload);
        expect(decodedChat, isNotNull);
        expect(decodedChat!.text, '落日后残波近场聊天测试');
      });
    });
  });
}
