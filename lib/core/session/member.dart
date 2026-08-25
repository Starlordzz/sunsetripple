import 'dart:typed_data';

/// Represents a member in the intercom room.
class Member {
  final int memberId;
  final String nickname;
  final Uint8List? sessionToken;
  final DateTime joinedAt;

  /// 入房顺序，房主分配的单调递增整数，房主转移时按它选继任者。
  ///
  /// 不用 [joinedAt] 排序：设备时钟回拨会让「谁更资深」发生翻转，
  /// 而选举结果必须在所有成员上算出同一个答案。
  int joinOrder;

  /// 重连端点。WiFi 房是对端 IP，蓝牙房是 MAC；房主从传输层学到后填进来。
  /// 空串表示还不知道，这样的成员不能作为继任者。
  String endpoint;

  bool isHost;
  bool isMuted;
  bool isSpeaking;
  DateTime lastActiveAt;

  Member({
    required this.memberId,
    required this.nickname,
    this.sessionToken,
    DateTime? joinedAt,
    this.joinOrder = 0,
    this.endpoint = '',
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
    int? joinOrder,
    String? endpoint,
    bool? isHost,
    bool? isMuted,
    bool? isSpeaking,
  }) {
    return Member(
      memberId: memberId ?? this.memberId,
      nickname: nickname ?? this.nickname,
      sessionToken: sessionToken ?? this.sessionToken,
      joinedAt: joinedAt,
      joinOrder: joinOrder ?? this.joinOrder,
      endpoint: endpoint ?? this.endpoint,
      isHost: isHost ?? this.isHost,
      isMuted: isMuted ?? this.isMuted,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      lastActiveAt: lastActiveAt,
    );
  }

  @override
  String toString() =>
      'Member(id: $memberId, order: $joinOrder, name: $nickname, host: $isHost, muted: $isMuted, speaking: $isSpeaking)';
}
