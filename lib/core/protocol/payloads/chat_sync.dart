import 'dart:convert';
import 'dart:typed_data';

/// Binary codec for syncing historical chat messages to newly joined room members.
///
/// Format:
/// [0]      : Target Member ID (1 byte, who should receive this history item, 0 = all)
/// [1]      : Sender Member ID (1 byte)
/// [2..5]   : Sender Code (4 bytes ASCII)
/// [6..13]  : Timestamp ms (8 bytes uint64 BE)
/// [14]     : Message ID length (1 byte)
/// [15..M]  : Message ID UTF-8
/// [M+1]    : Nickname length (1 byte)
/// [M+2..K] : Nickname UTF-8
/// [K+1..K+2]: Text length (2 bytes uint16 BE)
/// [K+3..N] : Text UTF-8
class ChatSyncPayload {
  static const int maxPayloadBytes = 512;
  static const int maxFieldBytes = 64;

  final int targetMemberId;
  final int senderId;
  final String senderCode;
  final int timestampMs;
  final String messageId;
  final String nickname;
  final String text;

  const ChatSyncPayload({
    required this.targetMemberId,
    required this.senderId,
    required this.senderCode,
    required this.timestampMs,
    required this.messageId,
    required this.nickname,
    required this.text,
  });

  Uint8List encode() {
    final msgIdBytes = utf8.encode(messageId);
    if (msgIdBytes.isEmpty || msgIdBytes.length > maxFieldBytes) {
      throw ArgumentError('messageId must contain 1 to $maxFieldBytes UTF-8 bytes.');
    }
    final msgIdLen = msgIdBytes.length;

    final nickBytes = utf8.encode(nickname);
    if (nickBytes.isEmpty || nickBytes.length > maxFieldBytes) {
      throw ArgumentError('nickname must contain 1 to $maxFieldBytes UTF-8 bytes.');
    }
    final nickLen = nickBytes.length;

    final maxAllowedText = maxPayloadBytes - (18 + msgIdLen + nickLen);
    final textBytes = utf8.encode(text);
    final textLen = textBytes.length;
    if (textBytes.isEmpty || textBytes.length > maxAllowedText) {
      throw ArgumentError('chat sync text exceeds the available UTF-8 payload budget.');
    }

    final codeBytes = ascii.encode(senderCode.padRight(4, ' ').substring(0, 4));

    final totalLen = 1 + 1 + 4 + 8 + 1 + msgIdLen + 1 + nickLen + 2 + textLen;
    final buffer = Uint8List(totalLen);
    final bd = ByteData.sublistView(buffer);

    buffer[0] = targetMemberId;
    buffer[1] = senderId;
    buffer.setRange(2, 6, codeBytes);
    bd.setUint64(6, timestampMs, Endian.big);

    int offset = 14;
    buffer[offset++] = msgIdLen;
    buffer.setRange(offset, offset + msgIdLen, msgIdBytes);
    offset += msgIdLen;

    buffer[offset++] = nickLen;
    buffer.setRange(offset, offset + nickLen, nickBytes);
    offset += nickLen;

    bd.setUint16(offset, textLen, Endian.big);
    offset += 2;
    buffer.setRange(offset, offset + textLen, textBytes);

    return buffer;
  }

  static ChatSyncPayload? decode(Uint8List data) {
    if (data.length < 18) return null;

    final targetMemberId = data[0];
    final senderId = data[1];
    final String senderCode;
    try {
      senderCode = ascii.decode(data.sublist(2, 6), allowInvalid: false).trim();
    } on FormatException {
      return null;
    }
    final timestampMs = ByteData.sublistView(data).getUint64(6, Endian.big);

    int offset = 14;
    final msgIdLen = data[offset++];
    if (offset + msgIdLen > data.length) return null;
    final String messageId;
    try {
      messageId = utf8.decode(
        data.sublist(offset, offset + msgIdLen),
        allowMalformed: false,
      );
    } on FormatException {
      return null;
    }
    offset += msgIdLen;

    if (offset >= data.length) return null;
    final nickLen = data[offset++];
    if (offset + nickLen > data.length) return null;
    final String nickname;
    try {
      nickname = utf8.decode(
        data.sublist(offset, offset + nickLen),
        allowMalformed: false,
      );
    } on FormatException {
      return null;
    }
    offset += nickLen;

    if (offset + 2 > data.length) return null;
    final textLen = ByteData.sublistView(data).getUint16(offset, Endian.big);
    offset += 2;
    if (textLen == 0 || offset + textLen != data.length) return null;
    final String text;
    try {
      text = utf8.decode(
        data.sublist(offset, offset + textLen),
        allowMalformed: false,
      );
    } on FormatException {
      return null;
    }

    return ChatSyncPayload(
      targetMemberId: targetMemberId,
      senderId: senderId,
      senderCode: senderCode,
      timestampMs: timestampMs,
      messageId: messageId,
      nickname: nickname,
      text: text,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatSyncPayload &&
          runtimeType == other.runtimeType &&
          targetMemberId == other.targetMemberId &&
          senderId == other.senderId &&
          senderCode == other.senderCode &&
          timestampMs == other.timestampMs &&
          messageId == other.messageId &&
          nickname == other.nickname &&
          text == other.text;

  @override
  int get hashCode =>
      targetMemberId.hashCode ^
      senderId.hashCode ^
      senderCode.hashCode ^
      timestampMs.hashCode ^
      messageId.hashCode ^
      nickname.hashCode ^
      text.hashCode;
}

