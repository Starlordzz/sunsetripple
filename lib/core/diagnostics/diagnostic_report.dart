import 'dart:convert';
import 'dart:io';

import 'trace.dart';

class DiagnosticSanitizer {
  static final RegExp _macAddress =
      RegExp(r'\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b', caseSensitive: false);
  static final RegExp _ipv4Address = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');

  /// IPv6 的 RFC 4291 全形态：未压缩 8 组、`::` 压缩、带 zone id（`%wlan0`）。
  ///
  /// 只脱敏 IPv4 会让纯 IPv6 网络下的导出报告带着完整对端地址出门；
  /// 而用「≥2 个冒号段」这种宽松规则又会误伤 `12:34:56` 这类时间戳，
  /// 所以这里按 IPv6 的合法段数枚举，MAC（6 段十六进制、无 `::`）与
  /// 时间戳（十进制段）都不会命中。
  static final RegExp _ipv6Address = RegExp(
    r'(?<![\w:])('
    r'([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}'
    r'|([0-9a-fA-F]{1,4}:){1,7}:'
    r'|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}'
    r'|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}'
    r'|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}'
    r'|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}'
    r'|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}'
    r'|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})'
    r'|:((:[0-9a-fA-F]{1,4}){1,7}|:)'
    r')(?:%\w+)?(?![\w:])',
  );

  /// 长度 ≥24 的连续 token 形态（base64/hex/密钥串）。
  static final RegExp _longToken = RegExp(r'\b[A-Za-z0-9+/=_-]{24,}\b');

  static String sanitize(String input) {
    var out = input.replaceAll(_macAddress, '[redacted-address]');
    out = out.replaceAll(_ipv6Address, '[redacted-address]');
    out = out.replaceAll(_ipv4Address, '[redacted-address]');
    out = out.replaceAll(_longToken, '[redacted-token]');
    return out;
  }
}

class DiagnosticReport {
  final int schemaVersion;
  final String appVersion;
  final String deviceModel;
  final String osVersion;
  final String roomType;

  /// 生成报告时所在会话的 traceId；不在会话里时为 null。
  /// 有了它，用户贴出来的一行日志和这份快照才对得上同一次会话。
  final String? traceId;
  final bool connected;
  final int memberCount;
  final int receivedFrames;
  final int concealedFrames;
  final String networkQuality;
  final List<String> recentErrors;
  final List<String> environmentNotes;

  DiagnosticReport({
    this.schemaVersion = 1,
    required this.appVersion,
    required this.deviceModel,
    required this.osVersion,
    required this.roomType,
    this.traceId,
    required this.connected,
    required this.memberCount,
    required this.receivedFrames,
    required this.concealedFrames,
    required this.networkQuality,
    required this.recentErrors,
    this.environmentNotes = const [],
  });

  factory DiagnosticReport.create({
    required String appVersion,
    required String roomType,
    bool connected = false,
    int memberCount = 0,
    int receivedFrames = 0,
    int concealedFrames = 0,
    String networkQuality = 'Unknown',
    List<String> recentErrors = const [],

    /// 会话 traceId。默认取当前的 [TraceId.current]（不在会话里则为 null），
    /// 这样调用方不必自己传，导出的报告也能和日志行对上。
    String? traceId,

    /// 额外的原始日志行（例如宿主版本、平台信息）。会与 [recentErrors]
    /// 一样逐行脱敏后才进入报告。
    List<String> environmentNotes = const [],
  }) {
    final sanitizedErrors =
        recentErrors.map((e) => DiagnosticSanitizer.sanitize(e)).toList();
    final sanitizedNotes =
        environmentNotes.map((e) => DiagnosticSanitizer.sanitize(e)).toList();

    return DiagnosticReport(
      appVersion: appVersion,
      deviceModel: Platform.operatingSystem,
      osVersion: DiagnosticSanitizer.sanitize(Platform.operatingSystemVersion),
      roomType: roomType,
      traceId: traceId ?? TraceId.current,
      connected: connected,
      memberCount: memberCount,
      receivedFrames: receivedFrames,
      concealedFrames: concealedFrames,
      networkQuality: networkQuality,
      recentErrors: sanitizedErrors,
      environmentNotes: sanitizedNotes,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'deviceModel': deviceModel,
        'osVersion': osVersion,
        'roomType': roomType,
        // 固定出现：消费端可以直接 json['traceId']，不必先判断键是否存在；
        // 不在会话里时为 null。
        'traceId': traceId,
        'connected': connected,
        'memberCount': memberCount,
        'receivedFrames': receivedFrames,
        'concealedFrames': concealedFrames,
        'networkQuality': networkQuality,
        'recentErrors': recentErrors,
        if (environmentNotes.isNotEmpty) 'environment': environmentNotes,
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  String issueSummary() {
    final buffer = StringBuffer();
    buffer.writeln('### Diagnostic Summary');
    buffer.writeln('- App: $appVersion');
    buffer.writeln('- OS: $deviceModel ($osVersion)');
    buffer.writeln('- Room Type: $roomType');
    buffer.writeln('- Trace: ${traceId ?? '-'}');
    buffer.writeln('- Network: $networkQuality');
    buffer.writeln('- Concealed Frames: $concealedFrames / $receivedFrames');
    if (recentErrors.isNotEmpty) {
      buffer.writeln('- Recent Errors:');
      for (final err in recentErrors.take(5)) {
        buffer.writeln('  - $err');
      }
    }
    return buffer.toString();
  }
}
