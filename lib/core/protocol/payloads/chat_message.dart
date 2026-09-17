import 'dart:convert';
import 'dart:typed_data';
import '../../diagnostics/app_log.dart';

/// Binary codec for SunsetRipple chat message payload.
///
/// Current format:
/// [0]     : Version (1 byte, 0x02)
/// [1..8]  : Timestamp in ms (8 bytes, Big-Endian uint64)
/// [9..12] : Sender Code (4 bytes ASCII, e.g. "3F7A")
/// [13..14]: Text Length (2 bytes, Big-Endian uint16)
/// [15..N] : UTF-8 encoded text (1 ~ 480 bytes)
class ChatMessagePayload {
  static const int currentVersion = 2;

  /// Business payload limit: 480 UTF-8 bytes.
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
    if (version != currentVersion) {
      throw ArgumentError('Unsupported chat payload version: $version.');
    }
    if (text.trim().isEmpty) {
      throw ArgumentError(
          'Chat message text cannot be empty or whitespace-only.');
    }

    final textBytes = utf8.encode(text);
    if (textBytes.length > maxTextBytes) {
      throw ArgumentError(
        'Chat message exceeds $maxTextBytes UTF-8 bytes (actual: ${textBytes.length}).',
      );
    }

    final codeAscii = ascii.encode(senderCode.padRight(4, ' ').substring(0, 4));
    final buffer = Uint8List(15 + textBytes.length);
    final bd = ByteData.sublistView(buffer);
    buffer[0] = 2;
    bd.setUint64(
        1,
        timestampMs == 0 ? DateTime.now().millisecondsSinceEpoch : timestampMs,
        Endian.big);
    buffer.setRange(9, 13, codeAscii);
    bd.setUint16(13, textBytes.length, Endian.big);
    buffer.setRange(15, 15 + textBytes.length, textBytes);
    return buffer;
  }

  /// Decodes raw payload bytes into [ChatMessagePayload].
  /// Only the current v2 format is accepted.
  static ChatMessagePayload? decode(Uint8List data) {
    if (data.length < 15) return null;
    final version = data[0];
    if (version != currentVersion) return null;

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
        version: currentVersion,
        text: text,
        timestampMs: timestamp,
        senderCode: code,
      );
    } catch (e) {
      AppLog.warn('ChatMessage', '消息文本 UTF-8 解码失败', e);
      return null;
    }
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
