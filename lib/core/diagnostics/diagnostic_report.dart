import 'dart:convert';
import 'dart:io';

class DiagnosticSanitizer {
  static final RegExp _macAddress =
      RegExp(r'\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b', caseSensitive: false);
  static final RegExp _ipv4Address = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
  static final RegExp _longToken = RegExp(r'\b[A-Za-z0-9+/=_-]{24,}\b');

  static String sanitize(String input) {
    var out = input.replaceAll(_macAddress, '[redacted-address]');
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
  final bool connected;
  final int memberCount;
  final int receivedFrames;
  final int concealedFrames;
  final String networkQuality;
  final List<String> recentErrors;

  DiagnosticReport({
    this.schemaVersion = 1,
    required this.appVersion,
    required this.deviceModel,
    required this.osVersion,
    required this.roomType,
    required this.connected,
    required this.memberCount,
    required this.receivedFrames,
    required this.concealedFrames,
    required this.networkQuality,
    required this.recentErrors,
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
  }) {
    final sanitizedErrors = recentErrors
        .map((e) => DiagnosticSanitizer.sanitize(e))
        .toList();

    return DiagnosticReport(
      appVersion: appVersion,
      deviceModel: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      roomType: roomType,
      connected: connected,
      memberCount: memberCount,
      receivedFrames: receivedFrames,
      concealedFrames: concealedFrames,
      networkQuality: networkQuality,
      recentErrors: sanitizedErrors,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'deviceModel': deviceModel,
        'osVersion': osVersion,
        'roomType': roomType,
        'connected': connected,
        'memberCount': memberCount,
        'receivedFrames': receivedFrames,
        'concealedFrames': concealedFrames,
        'networkQuality': networkQuality,
        'recentErrors': recentErrors,
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  String issueSummary() {
    final buffer = StringBuffer();
    buffer.writeln('### Diagnostic Summary');
    buffer.writeln('- App: $appVersion');
    buffer.writeln('- OS: $deviceModel ($osVersion)');
    buffer.writeln('- Room Type: $roomType');
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
