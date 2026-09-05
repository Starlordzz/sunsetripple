import 'dart:convert';
import 'dart:typed_data';

/// Binary codec for SunsetRipple chat message payload.
///
/// Format v1 (legacy):
/// [0]     : Version (1 byte, 0x01)
/// [1..2]  : Text Length (2 bytes, Big-Endian uint16)
/// [3..N]  : UTF-8 encoded text (1 ~ 480 bytes)
///
/// Format v2 (enhanced):
/// [0]     : Version (1 byte, 0x02)
/// [1..8]  : Timestamp in ms (8 bytes, Big-Endian uint64)
/// [9..12] : Sender Code (4 bytes ASCII, e.g. "3F7A")
/// [13..14]: Text Length (2 bytes, Big-Endian uint16)
/// [15..N] : UTF-8 encoded text (1 ~ 480 bytes)
class ChatMessagePayload {
  static const int currentVersion = 2;

  /// Business payload limit: 480 UTF-8 bytes.
  /// Together with 15-byte header, total payload is at most 495 bytes,
  /// well below Frame's 512-byte hard ceiling.
  static const int maxTextBytes = 480;

  final int version;
  final String text;
  final int timestampMs;
  final String senderCode;

  const ChatMessagePayload({
    this.version = currentVersion,
    required this.text,
    this.timestampMs = 0,
    this.senderCode = '0000',
  });

  /// Encodes this payload into raw bytes.
  /// Throws [ArgumentError] if text is empty/whitespace or exceeds 480 UTF-8 bytes.
  Uint8List encode() {
    if (text.trim().isEmpty) {
      throw ArgumentError('Chat message text cannot be empty or whitespace-only.');
    }

    final textBytes = utf8.encode(text);
    if (textBytes.length > maxTextBytes) {
      throw ArgumentError(
        'Chat message exceeds $maxTextBytes UTF-8 bytes (actual: ${textBytes.length}).',
      );
    }

    if (version == 1) {
      final buffer = Uint8List(3 + textBytes.length);
      buffer[0] = 1;
      ByteData.sublistView(buffer).setUint16(1, textBytes.length, Endian.big);
      buffer.setRange(3, 3 + textBytes.length, textBytes);
      return buffer;
    }

    // Version 2
    final codeAscii = ascii.encode(senderCode.padRight(4, ' ').substring(0, 4));
    final buffer = Uint8List(15 + textBytes.length);
    final bd = ByteData.sublistView(buffer);
    buffer[0] = 2;
    bd.setUint64(1, timestampMs == 0 ? DateTime.now().millisecondsSinceEpoch : timestampMs, Endian.big);
    buffer.setRange(9, 13, codeAscii);
    bd.setUint16(13, textBytes.length, Endian.big);
    buffer.setRange(15, 15 + textBytes.length, textBytes);
    return buffer;
  }

  /// Decodes raw payload bytes into [ChatMessagePayload].
  /// Supports both v1 and v2 formats.
  static ChatMessagePayload? decode(Uint8List data) {
    if (data.length < 3) return null;
    final version = data[0];

    if (version == 1) {
      final textLength = ByteData.sublistView(data).getUint16(1, Endian.big);
      if (textLength == 0 || textLength > maxTextBytes) return null;
      if (data.length != 3 + textLength) return null;

      try {
        final text = utf8.decode(
          data.sublist(3, 3 + textLength),
          allowMalformed: false,
        );
        if (text.trim().isEmpty) return null;
        return ChatMessagePayload(
          version: 1,
          text: text,
          timestampMs: 0,
          senderCode: '0000',
        );
      } catch (_) {
        return null;
      }
    } else if (version == 2) {
      if (data.length < 15) return null;
      final bd = ByteData.sublistView(data);
      final timestamp = bd.getUint64(1, Endian.big);
      final code = ascii.decode(data.sublist(9, 13), allowInvalid: true).trim();
      final textLength = bd.getUint16(13, Endian.big);
      if (textLength == 0 || textLength > maxTextBytes) return null;
      if (data.length != 15 + textLength) return null;

      try {
        final text = utf8.decode(
          data.sublist(15, 15 + textLength),
          allowMalformed: false,
        );
        if (text.trim().isEmpty) return null;
        return ChatMessagePayload(
          version: 2,
          text: text,
          timestampMs: timestamp,
          senderCode: code,
        );
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessagePayload &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          text == other.text &&
          timestampMs == other.timestampMs &&
          senderCode == other.senderCode;

  @override
  int get hashCode =>
      version.hashCode ^
      text.hashCode ^
      timestampMs.hashCode ^
      senderCode.hashCode;

  @override
  String toString() =>
      'ChatMessagePayload(v: $version, code: $senderCode, len: ${utf8.encode(text).length})';
}
