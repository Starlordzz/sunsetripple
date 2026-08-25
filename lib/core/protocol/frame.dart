import 'dart:typed_data';
import '../diagnostics/app_log.dart';
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

  /// 与已发布的 Kotlin 版 alpha.7 一致（`Frame.MAX_PAYLOAD = 512`）。
  /// 音频走 Opus 编码后一帧只有几十字节，512 绰绰有余；
  /// 对方的 `FrameStreamReader` 会把超过 512 的帧当作流错位并断开连接，
  /// 所以这个值**不能**再调大。
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

  /// 超长载荷仍然截断（否则 16 位长度字段会溢出），但不再静默——
  /// 截断意味着音频/名单数据已经损坏，必须留下痕迹。
  static Uint8List _capPayload(FrameType type, Uint8List payload) {
    if (payload.length <= maxPayloadSize) return payload;
    AppLog.error(
      'Frame',
      '${type.name} 帧载荷 ${payload.length} 字节超过上限 $maxPayloadSize，已截断（数据将损坏）',
    );
    return payload.sublist(0, maxPayloadSize);
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

    if (data.length < headerSize + length || length > maxPayloadSize) {
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
