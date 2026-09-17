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
    if (nickBytes.isEmpty || nickBytes.length > 64) {
      throw ArgumentError('nickname must contain 1 to 64 UTF-8 bytes.');
    }
    if (sessionToken.length != 16) {
      throw ArgumentError('sessionToken must be exactly 16 bytes.');
    }

    final out = Uint8List(1 + nickBytes.length + 16);
    out[0] = nickBytes.length;
    out.setRange(1, 1 + nickBytes.length, nickBytes);
    out.setRange(1 + nickBytes.length, out.length, sessionToken);
    return out;
  }

  static JoinRequestPayload? decode(Uint8List bytes) {
    if (bytes.length < 17) return null;
    final nickLen = bytes[0];
    if (nickLen == 0 || nickLen > 64 || bytes.length != 1 + nickLen + 16) return null;

    final String nick;
    try {
      nick = utf8.decode(
        bytes.sublist(1, 1 + nickLen),
        allowMalformed: false,
      );
    } on FormatException {
      return null;
    }
    final token = Uint8List(16);
    token.setRange(0, 16, bytes.sublist(1 + nickLen, 1 + nickLen + 16));

    return JoinRequestPayload(nickname: nick, sessionToken: token);
  }
}
