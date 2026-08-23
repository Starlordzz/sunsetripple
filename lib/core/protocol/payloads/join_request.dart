import 'dart:convert';
import 'dart:typed_data';

/// JOIN_REQ (0x02) Payload
/// Format: [1 byte nickname length][UTF-8 nickname][16 bytes session token]
class JoinRequestPayload {
  final String nickname;
  final Uint8List sessionToken;

  JoinRequestPayload({
    required this.nickname,
    required this.sessionToken,
  });

  Uint8List encode() {
    final nickBytes = utf8.encode(nickname);
    final clampedNickLen = nickBytes.length.clamp(0, 64);
    final nickSub = nickBytes.sublist(0, clampedNickLen);
    
    final tokenBytes = Uint8List(16);
    final copyLen = sessionToken.length.clamp(0, 16);
    tokenBytes.setRange(0, copyLen, sessionToken);

    final out = Uint8List(1 + clampedNickLen + 16);
    out[0] = clampedNickLen;
    out.setRange(1, 1 + clampedNickLen, nickSub);
    out.setRange(1 + clampedNickLen, 1 + clampedNickLen + 16, tokenBytes);
    return out;
  }

  static JoinRequestPayload? decode(Uint8List bytes) {
    if (bytes.length < 17) return null;
    final nickLen = bytes[0];
    if (bytes.length < 1 + nickLen + 16) return null;

    final nick = utf8.decode(bytes.sublist(1, 1 + nickLen), allowMalformed: true);
    final token = Uint8List(16);
    token.setRange(0, 16, bytes.sublist(1 + nickLen, 1 + nickLen + 16));

    return JoinRequestPayload(nickname: nick, sessionToken: token);
  }
}
