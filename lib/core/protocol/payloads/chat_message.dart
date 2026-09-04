import 'dart:convert';
import 'dart:typed_data';

/// Binary codec for SunsetRipple chat message payload.
///
/// Format:
/// [0]     : Version (1 byte, currently 0x01)
/// [1..2]  : Text Length (2 bytes, Big-Endian uint16)
/// [3..N]  : UTF-8 encoded text (1 ~ 480 bytes)
class ChatMessagePayload {
  static const int currentVersion = 1;

  /// Business payload limit: 480 UTF-8 bytes.
  /// Together with 3-byte header, total payload is at most 483 bytes,
  /// well below Frame's 512-byte hard ceiling.
  static const int maxTextBytes = 480;

  final int version;
  final String text;

  const ChatMessagePayload({
    this.version = currentVersion,
    required this.text,
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

    final buffer = Uint8List(3 + textBytes.length);
    buffer[0] = version;
    ByteData.sublistView(buffer).setUint16(1, textBytes.length, Endian.big);
    buffer.setRange(3, 3 + textBytes.length, textBytes);
    return buffer;
  }

  /// Decodes raw payload bytes into [ChatMessagePayload].
  /// Returns null if format is invalid, version != 1, length mismatches,
  /// contains trailing bytes, or has malformed UTF-8.
  static ChatMessagePayload? decode(Uint8List data) {
    if (data.length < 3) return null;

    final version = data[0];
    if (version != currentVersion) return null;

    final textLength = ByteData.sublistView(data).getUint16(1, Endian.big);
    if (textLength == 0 || textLength > maxTextBytes) return null;

    // Strict length check: reject insufficient bytes or extra trailing bytes
    if (data.length != 3 + textLength) return null;

    try {
      final text = utf8.decode(
        data.sublist(3, 3 + textLength),
        allowMalformed: false,
      );
      if (text.trim().isEmpty) return null;
      return ChatMessagePayload(version: version, text: text);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessagePayload &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          text == other.text;

  @override
  int get hashCode => version.hashCode ^ text.hashCode;

  @override
  String toString() => 'ChatMessagePayload(v: $version, len: ${utf8.encode(text).length})';
}

