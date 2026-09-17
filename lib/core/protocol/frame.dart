import 'dart:typed_data';
import 'frame_type.dart';

/// SunsetRipple 6-byte Header Binary Frame.
///
/// Format:
/// [0]     : FrameType (1 byte)
/// [1]     : Sender ID (1 byte)
/// [2..3]  : Sequence Number (2 bytes, Big-Endian uint16)
/// [4..5]  : Payload Length (2 bytes, Big-Endian uint16)
/// [6..N]  : Payload (0 ~ 512 bytes)
class Frame {
  static const int headerSize = 6;

  /// 当前跨平台实现的安全上限。音频走 Opus 编码后一帧只有几十字节，
  /// 512 足以覆盖控制帧和聊天帧，同时限制单帧内存占用。
  static const int maxPayloadSize = 512;
  static const int maxTotalSize = headerSize + maxPayloadSize;

  final FrameType type;
  final int senderId;
  final int seq;
  final Uint8List payload;

  Frame({
    required this.type,
    required this.senderId,
    required this.seq,
    required Uint8List payload,
  }) : payload = _capPayload(type, payload);

  /// 超长载荷不能截断：截断后的帧仍然合法，但接收端会得到一个
  /// 不完整对象，严重时还会把后续 TCP 字节解释成下一帧。
  static Uint8List _capPayload(FrameType type, Uint8List payload) {
    if (payload.length <= maxPayloadSize) return payload;
    throw ArgumentError(
      '${type.name} frame payload exceeds $maxPayloadSize bytes '
      '(actual: ${payload.length}).',
    );
  }

  /// Encodes this Frame into a raw byte buffer.
  Uint8List encode() {
    final length = payload.length;
    final buffer = Uint8List(headerSize + length);
    final byteData = ByteData.sublistView(buffer);

    byteData.setUint8(0, type.value);
    byteData.setUint8(1, senderId);
    byteData.setUint16(2, seq, Endian.big);
    byteData.setUint16(4, length, Endian.big);

    if (length > 0) {
      buffer.setRange(headerSize, headerSize + length, payload);
    }
    return buffer;
  }

  /// Decodes a Frame from raw bytes. Returns null if invalid.
  static Frame? decode(Uint8List data) {
    if (data.length < headerSize) return null;

    final byteData = ByteData.sublistView(data);
    final typeValue = byteData.getUint8(0);
    final type = FrameType.fromValue(typeValue);
    if (type == null) return null;

    final senderId = byteData.getUint8(1);
    final seq = byteData.getUint16(2, Endian.big);
    final length = byteData.getUint16(4, Endian.big);

    if (length > maxPayloadSize || data.length != headerSize + length) {
      return null;
    }

    final payload = Uint8List(length);
    if (length > 0) {
      payload.setRange(0, length, data, headerSize);
    }

    return Frame(
      type: type,
      senderId: senderId,
      seq: seq,
      payload: payload,
    );
  }

  @override
  String toString() =>
      'Frame(type: ${type.name}, sender: $senderId, seq: $seq, len: ${payload.length})';
}
