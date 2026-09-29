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
/// [15..N] : UTF-8 encoded text (1 ~ 420 bytes)
class ChatMessagePayload {
  static const int currentVersion = 2;

  /// chat 帧头部占用：1 版本 + 8 时间戳 + 4 设备码 + 2 文本长度。
  static const int headerBytes = 15;

  /// chatSync 帧文本之前的固定字段占用：1 目标成员 + 1 发送者 + 4 设备码
  /// + 8 时间戳 + 1 消息 ID 长度 + 1 昵称长度 + 2 文本长度。
  ///
  /// 历史同步会额外挤进「消息 ID + 昵称」两个变长字段，因此它比 live chat
  /// 可用文本更少。两条路径共用同一个预算上限，否则会出现
  /// 「sendChat 接受、chatSync 拒绝」的裂缝：一条 480 字节的合法消息
  /// 会让新成员的历史同步在循环中途整段中断。
  static const int chatSyncHeaderBytes = 18;

  /// 用于承载消息 ID 与昵称的预算上限（协议允许 1..64 字节）。
  static const int maxFieldBytes = 64;

  /// 设备码在 chat 载荷里占 4 个 ASCII 字节（`108` 会被右填空格到 4 字节）。
  static const int senderCodeBytes = 4;

  /// 安全信封在每个密封帧上的固定开销：12 字节 nonce + 16 字节 GCM tag。
  /// 与 `SecureFrameCodec.nonceBytes`/`tagBytes` 保持一致。
  static const int sealedOverheadBytes = 28;

  /// 消息 ID 的最坏形态：`<deviceCode>_<epochMillis>_<seq>`，
  /// 3 + 1 + 13 + 1 + 5 = 23 字节（seq 是 uint16，最大 65535）。
  static const int fixedMessageIdBytes = 23;

  /// 昵称在历史同步里最多占用的字节数。`JoinRequestPayload` 与 `RosterPayload`
  /// 都限制昵称不超过 64 字节，而 `chatSync` 明文里装的是去掉设备码后的基名，
  /// 因此 64 是上界。
  static const int maxNicknameBytes = 64;

  /// 单条消息文本的业务上限（UTF-8 字节）。live chat 与 chatSync **共享**，
  /// 由最紧的路径决定：
  ///
  ///   密封后的 chatSync（开启安全信封时最坏情况）
  ///     512 - 12 (nonce) - 16 (tag) - 18 (sync 头) - 23 (msgId) - 64 (昵称)
  ///     = 373
  ///
  /// 取 368 留 5 字节余量。任何被 [sendChat] 接受的消息都一定能被
  /// 历史同步与安全信封编码，不会再出现「发得出去、同步时抛错」的裂缝。
  static const int maxTextBytes = 368;

  /// chat 帧的完整载荷上限（15 字节头 + 文本），仅供测试与文档引用。
  static const int maxChatPayloadBytes = headerBytes + maxTextBytes;

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
  /// Throws [ArgumentError] if text is empty/whitespace or exceeds [maxTextBytes].
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
        'Chat message exceeds $maxTextBytes UTF-8 bytes (actual: ${textBytes.length}). '
        'This is the shared live-chat + history-sync budget.',
      );
    }

    final codeAscii = ascii.encode(senderCode
        .padRight(senderCodeBytes, ' ')
        .substring(0, senderCodeBytes));
    final buffer = Uint8List(15 + textBytes.length);
    final bd = ByteData.sublistView(buffer);
    buffer[0] = 2;
    bd.setUint64(
        1,
        timestampMs == 0
            ? DateTime.now().millisecondsSinceEpoch // clock-exempt: 线协议缺省时间戳
            : timestampMs,
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
