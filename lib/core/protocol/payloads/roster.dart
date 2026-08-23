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
  final int hostId;
  final List<RosterMember> members;

  RosterPayload({
    required this.hostId,
    required this.members,
  });

  Uint8List encode() {
    final bytesList = <int>[hostId, members.length];
    for (final m in members) {
      final nickBytes = utf8.encode(m.nickname);
      final nickLen = nickBytes.length.clamp(0, 64);
      bytesList.add(m.memberId);
      bytesList.add(m.flags);
      bytesList.add(nickLen);
      bytesList.addAll(nickBytes.sublist(0, nickLen));
    }
    return Uint8List.fromList(bytesList);
  }

  static RosterPayload? decode(Uint8List bytes) {
    if (bytes.length < 2) return null;
    final hostId = bytes[0];
    final count = bytes[1];
    final members = <RosterMember>[];

    int offset = 2;
    for (int i = 0; i < count; i++) {
      if (offset + 3 > bytes.length) break;
      final mId = bytes[offset++];
      final flags = bytes[offset++];
      final nickLen = bytes[offset++];
      if (offset + nickLen > bytes.length) break;
      final nick = utf8.decode(bytes.sublist(offset, offset + nickLen), allowMalformed: true);
      offset += nickLen;
      members.add(RosterMember(memberId: mId, flags: flags, nickname: nick));
    }

    return RosterPayload(hostId: hostId, members: members);
  }
}
