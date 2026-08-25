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
