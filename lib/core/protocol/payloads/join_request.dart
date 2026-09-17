import 'dart:convert';
import 'dart:typed_data';

import '../../session/session_token.dart';

/// JOIN_REQ (0x02) Payload
/// Format: [1 byte nickname length][UTF-8 nickname][16 bytes session token]
class JoinRequestPayload {
  final String nickname;
  final Uint8List sessionToken;

  JoinRequestPayload({
    required this.nickname,
    required Uint8List sessionToken,
  }) : sessionToken = Uint8List.fromList(sessionToken) {
    if (!isValidSessionToken(sessionToken)) {
      throw ArgumentError(
        'sessionToken must be a non-zero $sessionTokenBytes-byte value.',
      );
    }
  }

  Uint8List encode() {
    final nickBytes = utf8.encode(nickname);
    if (nickBytes.isEmpty || nickBytes.length > 64) {
      throw ArgumentError('nickname must contain 1 to 64 UTF-8 bytes.');
    }
    if (!isValidSessionToken(sessionToken)) {
      throw ArgumentError(
        'sessionToken must be a non-zero $sessionTokenBytes-byte value.',
      );
    }

    final out = Uint8List(1 + nickBytes.length + sessionTokenBytes);
    out[0] = nickBytes.length;
    out.setRange(1, 1 + nickBytes.length, nickBytes);
    out.setRange(1 + nickBytes.length, out.length, sessionToken);
    return out;
  }

  static JoinRequestPayload? decode(Uint8List bytes) {
    if (bytes.length < 1 + sessionTokenBytes) return null;
    final nickLen = bytes[0];
    if (nickLen == 0 ||
        nickLen > 64 ||
        bytes.length != 1 + nickLen + sessionTokenBytes) {
      return null;
    }

    final String nick;
    try {
      nick = utf8.decode(
        bytes.sublist(1, 1 + nickLen),
        allowMalformed: false,
      );
    } on FormatException {
      return null;
    }
    final token = Uint8List(sessionTokenBytes);
    token.setRange(
      0,
      sessionTokenBytes,
      bytes.sublist(1 + nickLen, 1 + nickLen + sessionTokenBytes),
    );
    if (!isValidSessionToken(token)) return null;

    return JoinRequestPayload(nickname: nick, sessionToken: token);
  }
}
