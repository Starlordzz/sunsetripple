import 'package:test/test.dart';
import '../lib/core/session/host_election.dart';
import '../lib/core/session/member.dart';

void main() {
  group('HostElection Tests', () {
    test('Elects earliest joined member as new host', () {
      final now = DateTime.now();
      final m1 = Member(memberId: 1, nickname: "Host", joinedAt: now.subtract(const Duration(minutes: 10)), isHost: true);
      final m2 = Member(memberId: 2, nickname: "Senior", joinedAt: now.subtract(const Duration(minutes: 5)));
      final m3 = Member(memberId: 3, nickname: "Junior", joinedAt: now.subtract(const Duration(minutes: 1)));

      final nextHost = HostElection.electNextHost([m1, m2, m3], excludedHostId: 1);
      expect(nextHost, isNotNull);
      expect(nextHost!.memberId, 2);
      expect(nextHost.nickname, "Senior");
    });

    test('Tie breaks using lowest memberId if joinedAt is identical', () {
      final now = DateTime.now();
      final m2 = Member(memberId: 2, nickname: "Member2", joinedAt: now);
      final m3 = Member(memberId: 3, nickname: "Member3", joinedAt: now);

      final nextHost = HostElection.electNextHost([m2, m3]);
      expect(nextHost, isNotNull);
      expect(nextHost!.memberId, 2);
    });

    test('Returns null when no eligible candidates exist', () {
      final m1 = Member(memberId: 1, nickname: "Host", isHost: true);
      final nextHost = HostElection.electNextHost([m1], excludedHostId: 1);
      expect(nextHost, isNull);
    });
  });
}

