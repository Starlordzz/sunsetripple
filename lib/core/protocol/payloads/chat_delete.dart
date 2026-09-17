import 'dart:convert';
import 'dart:typed_data';

/// Binary codec for deleting / recalling a chat message for all members.
///
/// Format:
/// [0]     : Version (1 byte, 0x01)
/// [1..4]  : Sender Code (4 bytes ASCII, author identity check)
/// [5]     : Message ID length (1 byte)
/// [6..N]  : Message ID UTF-8 bytes
class ChatDeletePayload {
  static const int currentVersion = 1;

  final int version;
  final String senderCode;
  final String messageId;

  const ChatDeletePayload({
    this.version = currentVersion,
    required this.senderCode,
    required this.messageId,
  });

  Uint8List encode() {
    final codeBytes = ascii.encode(senderCode.padRight(4, ' ').substring(0, 4));
    final msgIdBytes = utf8.encode(messageId);
    if (msgIdBytes.isEmpty || msgIdBytes.length > 64) {
      throw ArgumentError('messageId must contain 1 to 64 UTF-8 bytes.');
    }
    final msgIdLen = msgIdBytes.length;

    final buffer = Uint8List(1 + 4 + 1 + msgIdLen);
    buffer[0] = version;
    buffer.setRange(1, 5, codeBytes);
    buffer[5] = msgIdLen;
    buffer.setRange(6, 6 + msgIdLen, msgIdBytes);
    return buffer;
  }

  static ChatDeletePayload? decode(Uint8List data) {
    if (data.length < 6) return null;
    final version = data[0];
    if (version != currentVersion) return null;

    final String senderCode;
    try {
      senderCode = ascii.decode(data.sublist(1, 5), allowInvalid: false).trim();
    } on FormatException {
      return null;
    }
    final msgIdLen = data[5];
    if (msgIdLen == 0 || data.length != 6 + msgIdLen) return null;

    final String messageId;
    try {
      messageId = utf8.decode(
        data.sublist(6, 6 + msgIdLen),
        allowMalformed: false,
      );
    } on FormatException {
      return null;
    }
    return ChatDeletePayload(
      version: version,
      senderCode: senderCode,
      messageId: messageId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatDeletePayload &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          senderCode == other.senderCode &&
          messageId == other.messageId;

  @override
  int get hashCode => version.hashCode ^ senderCode.hashCode ^ messageId.hashCode;
}

