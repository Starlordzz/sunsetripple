import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/diagnostics/diagnostic_report.dart';

void main() {
  group('Diagnostics Tests', () {
    test('DiagnosticSanitizer strips IP, MAC, and long tokens', () {
      const input =
          'Error connecting to 192.168.1.50 with MAC AA:BB:CC:DD:EE:FF and token secret_token_abcdef12345678901234567890';
      final sanitized = DiagnosticSanitizer.sanitize(input);
      expect(sanitized.contains('192.168.1.50'), isFalse);
      expect(sanitized.contains('AA:BB:CC:DD:EE:FF'), isFalse);
      expect(sanitized.contains('[redacted-address]'), isTrue);
      expect(sanitized.contains('[redacted-token]'), isTrue);
    });

    test('DiagnosticSanitizer strips IPv6 (compressed, full, zone id)', () {
      // 只脱敏 IPv4 会让纯 IPv6 网络下的导出报告带着完整对端地址出门。
      const input = 'peer fe80::1c2d:3e4f:5a6b:7c8d '
          'global 2001:db8::1 '
          'zoned fe80::1%wlan0 '
          'loopback ::1';
      final sanitized = DiagnosticSanitizer.sanitize(input);

      expect(sanitized.contains('fe80::1c2d:3e4f:5a6b:7c8d'), isFalse);
      expect(sanitized.contains('2001:db8::1'), isFalse);
      expect(sanitized.contains('fe80::1%wlan0'), isFalse);
      expect(sanitized.contains('::1'), isFalse);
      expect(sanitized.contains('[redacted-address]'), isTrue);
    });

    test('DiagnosticReport redacts environment notes and osVersion', () {
      final report = DiagnosticReport.create(
        appVersion: '0.1.0-alpha.13',
        roomType: 'Idle / Standby',
        recentErrors: const ['连接 10.0.0.7:8988 失败'],
        environmentNotes: const ['host fe80::abcd', 'plain note'],
      );

      final encoded = report.encode();
      expect(encoded.contains('10.0.0.7'), isFalse);
      expect(encoded.contains('fe80::abcd'), isFalse);
      expect(encoded.contains('plain note'), isTrue);

      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['environment'], isA<List<dynamic>>());
    });

    test('DiagnosticReport creates valid JSON and issue summary', () {
      final report = DiagnosticReport.create(
        appVersion: '0.1.0-alpha.8',
        roomType: 'WiFi Full Duplex',
        connected: true,
        memberCount: 3,
        receivedFrames: 500,
        concealedFrames: 5,
        networkQuality: 'Good',
        recentErrors: ['Failed to send frame to 10.0.0.5: timeout'],
      );

      final encoded = report.encode();
      expect(encoded.isNotEmpty, isTrue);

      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 1);
      expect(decoded['appVersion'], '0.1.0-alpha.8');
      expect(decoded['memberCount'], 3);
      expect(decoded['receivedFrames'], 500);

      final summary = report.issueSummary();
      expect(summary.contains('App: 0.1.0-alpha.8'), isTrue);
      expect(summary.contains('Network: Good'), isTrue);
      expect(summary.contains('10.0.0.5'), isFalse);
    });
  });
}
