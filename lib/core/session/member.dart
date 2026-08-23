import 'dart:typed_data';

/// Represents a member in the intercom room.
class Member {
  final int memberId;
  final String nickname;
  final Uint8List? sessionToken;
  final DateTime joinedAt;
  
  bool isHost;
  bool isMuted;
  bool isSpeaking;
  DateTime lastActiveAt;

  Member({
    required this.memberId,
    required this.nickname,
    this.sessionToken,
    DateTime? joinedAt,
    this.isHost = false,
    this.isMuted = false,
    this.isSpeaking = false,
    DateTime? lastActiveAt,
  })  : joinedAt = joinedAt ?? DateTime.now(),
        lastActiveAt = lastActiveAt ?? DateTime.now();

  Member copyWith({
    int? memberId,
    String? nickname,
    Uint8List? sessionToken,
    bool? isHost,
    bool? isMuted,
    bool? isSpeaking,
  }) {
    return Member(
      memberId: memberId ?? this.memberId,
      nickname: nickname ?? this.nickname,
      sessionToken: sessionToken ?? this.sessionToken,
      joinedAt: joinedAt,
      isHost: isHost ?? this.isHost,
      isMuted: isMuted ?? this.isMuted,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      lastActiveAt: lastActiveAt,
    );
  }

  @override
  String toString() =>
      'Member(id: $memberId, name: $nickname, host: $isHost, muted: $isMuted, speaking: $isSpeaking)';
}
