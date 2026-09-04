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
    final codeBytes = ascii.encode(senderCode.padRight(4, '0').substring(0, 4));
    final msgIdBytes = utf8.encode(messageId);
    final msgIdLen = msgIdBytes.length.clamp(0, 64);

    final buffer = Uint8List(1 + 4 + 1 + msgIdLen);
    buffer[0] = version;
    buffer.setRange(1, 5, codeBytes);
    buffer[5] = msgIdLen;
    buffer.setRange(6, 6 + msgIdLen, msgIdBytes.sublist(0, msgIdLen));
    return buffer;
  }

  static ChatDeletePayload? decode(Uint8List data) {
    if (data.length < 6) return null;
    final version = data[0];
    if (version != currentVersion) return null;

    final senderCode = ascii.decode(data.sublist(1, 5), allowInvalid: true);
    final msgIdLen = data[5];
    if (data.length != 6 + msgIdLen) return null;

    final messageId = utf8.decode(data.sublist(6, 6 + msgIdLen), allowMalformed: true);
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

