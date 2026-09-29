import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/clock.dart';
import 'package:sunset_ripple/core/session/member.dart';
import 'package:sunset_ripple/core/session/presence_tracker.dart';

Member buildMember(
  int id, {
  bool speaking = false,
  DateTime? lastActiveAt,
}) =>
    Member(
      memberId: id,
      nickname: '成员$id',
      isSpeaking: speaking,
      lastActiveAt: lastActiveAt,
    );

void main() {
  late FakeClock clock;
  late PresenceTracker presence;

  setUp(() {
    clock = FakeClock(DateTime(2026, 1, 1, 12));
    presence = PresenceTracker(clock: clock);
  });

  group('说话指示灯的超时熄灭', () {
    test('超过 400ms 没有再收到音频才熄灯（边界不熄）', () {
      final speaker = buildMember(2, speaking: true);
      presence.markAudio(2);

      clock.advance(const Duration(milliseconds: 400));
      expect(
        presence.expireSpeaking(
          [speaker],
          selfMemberId: 1,
          fullDuplex: true,
        ),
        isFalse,
      );
      expect(speaker.isSpeaking, isTrue);

      clock.advance(const Duration(milliseconds: 1));
      expect(
        presence.expireSpeaking(
          [speaker],
          selfMemberId: 1,
          fullDuplex: true,
        ),
        isTrue,
      );
      expect(speaker.isSpeaking, isFalse);
    });

    test('从未送来音频却在说话的人立刻熄灯', () {
      final stranger = buildMember(3, speaking: true);

      expect(
        presence.expireSpeaking(
          [stranger],
          selfMemberId: 1,
          fullDuplex: true,
        ),
        isTrue,
      );
      expect(stranger.isSpeaking, isFalse);
    });

    test('音频仍在持续时不熄灯（时间戳被刷新）', () {
      final speaker = buildMember(2, speaking: true);
      presence.markAudio(2);

      clock.advance(const Duration(milliseconds: 300));
      presence.markAudio(2); // 又来了一帧
      clock.advance(const Duration(milliseconds: 300));

      expect(
        presence.expireSpeaking(
          [speaker],
          selfMemberId: 1,
          fullDuplex: true,
        ),
        isFalse,
      );
      expect(speaker.isSpeaking, isTrue);
    });

    test('PTT 模式不看音频超时，也不动自己的状态', () {
      final speaker = buildMember(2, speaking: true);
      final self = buildMember(1, speaking: true);
      clock.advance(const Duration(seconds: 5));

      expect(
        presence.expireSpeaking(
          [self, speaker],
          selfMemberId: 1,
          fullDuplex: false,
        ),
        isFalse,
      );
      expect(speaker.isSpeaking, isTrue);
      expect(self.isSpeaking, isTrue);
    });

    test('判定不会熄灭自己（本机由 pttState 驱动）', () {
      final self = buildMember(1, speaking: true);
      clock.advance(const Duration(seconds: 5));

      expect(
        presence.expireSpeaking(
          [self],
          selfMemberId: 1,
          fullDuplex: true,
        ),
        isFalse,
      );
      expect(self.isSpeaking, isTrue);
    });
  });

  group('心跳超时的成员清理', () {
    test('超过 10 秒没有心跳才判为失联（边界不算）', () {
      final quiet = buildMember(4, lastActiveAt: clock.now());

      clock.advance(const Duration(seconds: 10));
      expect(
        presence.staleMemberIds([quiet], selfMemberId: 1),
        isEmpty,
      );

      clock.advance(const Duration(milliseconds: 1));
      expect(
        presence.staleMemberIds([quiet], selfMemberId: 1),
        [4],
      );
    });

    test('刷新过心跳的成员不会被误清，房主自己也不在清理范围内', () {
      final quiet = buildMember(4, lastActiveAt: clock.now());
      final self = buildMember(1, lastActiveAt: DateTime(2000));

      clock.advance(const Duration(seconds: 9));
      presence.touch(quiet);
      clock.advance(const Duration(seconds: 9));

      expect(
        presence.staleMemberIds([self, quiet], selfMemberId: 1),
        isEmpty,
      );
    });
  });

  group('音频时间戳簿记', () {
    test('markAudio 用注入时钟记录，可从 lastAudioAtOf 读回', () {
      presence.markAudio(7);

      expect(presence.lastAudioAtOf(7), clock.now());
      expect(presence.trackedMemberIds, [7]);

      clock.advance(const Duration(seconds: 2));
      presence.markAudio(7);
      expect(presence.lastAudioAtOf(7), clock.now());
    });

    test('forgetAbsent 只丢弃已不在名单里的成员并返回它们', () {
      presence.markAudio(2);
      presence.markAudio(3);
      presence.markAudio(4);

      expect(presence.forgetAbsent({3}), [2, 4]);
      expect(presence.trackedMemberIds, [3]);
    });

    test('forget 与 clear 清空对应记录', () {
      presence.markAudio(2);
      presence.markAudio(3);

      presence.forget(2);
      expect(presence.lastAudioAtOf(2), isNull);
      expect(presence.lastAudioAtOf(3), isNotNull);

      presence.clear();
      expect(presence.trackedMemberIds, isEmpty);
    });
  });
}
