import 'dart:convert';
import 'dart:typed_data';

class RosterMember {
  final int memberId;
  final int flags; // 0x01: isHost, 0x02: isMuted, 0x04: isSpeaking
  final String nickname;

  RosterMember({
    required this.memberId,
    this.flags = 0,
    required this.nickname,
  });

  bool get isHost => (flags & 0x01) != 0;
  bool get isMuted => (flags & 0x02) != 0;
  bool get isSpeaking => (flags & 0x04) != 0;
}

/// ROSTER (0x03) Payload
/// Format:
/// [0]     : Host Member ID (1 byte)
/// [1]     : Member Count (1 byte)
/// Repeat:
///   - memberId (1 byte)
///   - flags (1 byte)
///   - nickLength (1 byte)
///   - nickname (UTF-8 bytes)
class RosterPayload {
  static const int maxMembers = 6;
  static const int maxNicknameBytes = 64;
  static const int maxPayloadBytes = 512;

  final int hostId;
  final List<RosterMember> members;

  RosterPayload({
    required this.hostId,
    required this.members,
  });

  Uint8List encode() {
    if (hostId <= 0 || hostId > 255) {
      throw ArgumentError('hostId must fit in one byte and be non-zero.');
    }
    if (members.isEmpty || members.length > maxMembers) {
      throw ArgumentError('roster must contain 1 to $maxMembers members.');
    }
    final bytesList = <int>[hostId, members.length];
    final ids = <int>{};
    var hostFlags = 0;
    for (final m in members) {
      final nickBytes = utf8.encode(m.nickname);
      if (m.memberId <= 0 || m.memberId > 255 || !ids.add(m.memberId)) {
        throw ArgumentError('memberId must be unique, non-zero, and fit in one byte.');
      }
      if (nickBytes.length > maxNicknameBytes) {
        throw ArgumentError('nickname exceeds $maxNicknameBytes UTF-8 bytes.');
      }
      if (m.isHost) hostFlags++;
      final nickLen = nickBytes.length;
      bytesList.add(m.memberId);
      bytesList.add(m.flags);
      bytesList.add(nickLen);
      bytesList.addAll(nickBytes);
    }
    if (!ids.contains(hostId) || hostFlags != 1 || bytesList.length > maxPayloadBytes) {
      throw ArgumentError('roster host flags or payload length is invalid.');
    }
    return Uint8List.fromList(bytesList);
  }

  static RosterPayload? decode(Uint8List bytes) {
    if (bytes.length < 2) return null;
    final hostId = bytes[0];
    final count = bytes[1];
    if (hostId == 0 || count == 0 || count > maxMembers) return null;
    final members = <RosterMember>[];
    final ids = <int>{};
    var hostFlags = 0;

    int offset = 2;
    for (int i = 0; i < count; i++) {
      if (offset + 3 > bytes.length) return null;
      final mId = bytes[offset++];
      final flags = bytes[offset++];
      final nickLen = bytes[offset++];
      if (mId == 0 || !ids.add(mId) || offset + nickLen > bytes.length) return null;
      final nickBytes = bytes.sublist(offset, offset + nickLen);
      final String nick;
      try {
        nick = utf8.decode(nickBytes, allowMalformed: false);
      } on FormatException {
        return null;
      }
      offset += nickLen;
      if ((flags & 0x01) != 0) hostFlags++;
      members.add(RosterMember(memberId: mId, flags: flags, nickname: nick));
    }

    if (offset != bytes.length || !ids.contains(hostId) || hostFlags != 1) return null;
    return RosterPayload(hostId: hostId, members: members);
  }
}
