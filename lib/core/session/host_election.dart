import 'member.dart';

/// Deterministic Host Election & Succession Algorithm.
///
/// When the current host disconnects:
/// 1. Prioritize senior members who joined earliest (earliest [Member.joinedAt]).
/// 2. Tie-break using lowest [Member.memberId].
class HostElection {
  /// Elects the next host among remaining active members.
  /// Returns `null` if no candidate is available.
  static Member? electNextHost(List<Member> candidates, {int? excludedHostId}) {
    final eligible = candidates
        .where((m) => excludedHostId == null || m.memberId != excludedHostId)
        .toList();

    if (eligible.isEmpty) return null;

    eligible.sort((a, b) {
      final timeComp = a.joinedAt.compareTo(b.joinedAt);
      if (timeComp != 0) return timeComp;
      return a.memberId.compareTo(b.memberId);
    });

    return eligible.first;
  }
}
