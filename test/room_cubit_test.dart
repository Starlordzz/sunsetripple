import 'package:test/test.dart';
import '../lib/core/audio/audio_io.dart';
import '../lib/core/session/room_session.dart';
import '../lib/logic/room_cubit.dart';

void main() {
  group('RoomCubit Business Logic Layer Tests', () {
    late MockAudioIo mockAudio;
    late RoomCubit cubit;

    setUp(() {
      mockAudio = MockAudioIo();
      cubit = RoomCubit(audioIo: mockAudio);
    });

    tearDown(() {
      cubit.dispose();
    });

    test('Initial state is idle and muted=false, speaker=true', () {
      expect(cubit.state.status, RoomState.idle);
      expect(cubit.state.isMuted, isFalse);
      expect(cubit.state.isSpeakerOn, isTrue);
      expect(cubit.state.isPttPressed, isFalse);
    });

    test('createRoom transitions state to inRoom and sets isHost=true', () async {
      await cubit.createRoom(nickname: "测试房主", roomName: "测试落日房");

      expect(cubit.state.status, RoomState.inRoom);
      expect(cubit.state.isHost, isTrue);
      expect(cubit.state.nickname, "测试房主");
      expect(cubit.state.roomName, "测试落日房");
      expect(cubit.state.members.length, 1);
    });

    test('PTT and Mute actions update state immutably', () async {
      await cubit.createRoom(nickname: "测试房主");

      cubit.setPtt(true);
      expect(cubit.state.isPttPressed, isTrue);

      cubit.setPtt(false);
      expect(cubit.state.isPttPressed, isFalse);

      cubit.toggleMute();
      expect(cubit.state.isMuted, isTrue);

      cubit.toggleSpeaker();
      expect(cubit.state.isSpeakerOn, isFalse);
    });

    test('leaveRoom resets state back to idle', () async {
      await cubit.createRoom(nickname: "测试房主");
      expect(cubit.state.status, RoomState.inRoom);

      await cubit.leaveRoom();
      expect(cubit.state.status, RoomState.idle);
      expect(cubit.state.members.isEmpty, isTrue);
    });
  });
}
