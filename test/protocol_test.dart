import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
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
  });
}
