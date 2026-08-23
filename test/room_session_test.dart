import 'dart:typed_data';
import 'package:test/test.dart';
import '../lib/core/audio/audio_io.dart';
import '../lib/core/protocol/frame.dart';
import '../lib/core/protocol/frame_type.dart';
import '../lib/core/protocol/payloads/ptt_state.dart';
import '../lib/core/session/room_session.dart';

void main() {
  group('RoomSession Lifecycle & State Machine Tests', () {
    late MockAudioIo hostAudio;
    late MockAudioIo clientAudio;
    late RoomSession hostSession;
    late RoomSession clientSession;

    setUp(() {
      hostAudio = MockAudioIo();
      clientAudio = MockAudioIo();
      hostSession = RoomSession(audioIo: hostAudio, selfNickname: "HostAlice");
      clientSession = RoomSession(audioIo: clientAudio, selfNickname: "ClientBob");

      // Connect network pipe between host and client
      hostSession.onSendFrame = (frame) {
        clientSession.handleIncomingFrame(frame);
      };
      clientSession.onSendFrame = (frame) {
        hostSession.handleIncomingFrame(frame);
      };
    });

    tearDown(() async {
      await hostSession.leave();
      await clientSession.leave();
    });

    test('Host creates room and initializes as member 1', () async {
      await hostSession.createRoom();
      expect(hostSession.state, RoomState.inRoom);
      expect(hostSession.isHost, isTrue);
      expect(hostSession.selfMemberId, 1);
      expect(hostSession.members.length, 1);
      expect(hostSession.members.first.nickname, "HostAlice");
    });

    test('Client joins room, host admits and broadcasts roster', () async {
      await hostSession.createRoom();
      await clientSession.joinRoom();

      // Host should now have 2 members (1 and 2)
      expect(hostSession.members.length, 2);

      // Client should have received Roster and entered RoomState.inRoom
      expect(clientSession.state, RoomState.inRoom);
      expect(clientSession.selfMemberId, 2);
      expect(clientSession.members.length, 2);
    });

    test('PTT pressing updates speaking status across room', () async {
      await hostSession.createRoom();
      await clientSession.joinRoom();

      // Client presses PTT
      clientSession.setPtt(true);
      expect(clientSession.isPttPressed, isTrue);

      // Host member list should reflect client is speaking
      final clientOnHost = hostSession.members.firstWhere((m) => m.memberId == 2);
      expect(clientOnHost.isSpeaking, isTrue);

      // Client releases PTT
      clientSession.setPtt(false);
      expect(clientOnHost.isSpeaking, isFalse);
    });

    test('Microphone mute toggling updates state', () async {
      await hostSession.createRoom();
      expect(hostSession.isMuted, isFalse);

      hostSession.toggleMute();
      expect(hostSession.isMuted, isTrue);

      hostSession.toggleMute();
      expect(hostSession.isMuted, isFalse);
    });

    test('Member leaving cleans up session state', () async {
      await hostSession.createRoom();
      await clientSession.joinRoom();
      expect(hostSession.members.length, 2);

      await clientSession.leave();
      expect(clientSession.state, RoomState.idle);
      expect(hostSession.members.length, 1);
    });
  });
}
