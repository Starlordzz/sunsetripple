import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/update/update_service.dart';

void main() {
  group('UpdateService SemVer Comparison Tests', () {
    test('Older pre-release (alpha.9) is NOT newer than current (alpha.10)', () {
      expect(UpdateService.isNewer('0.1.0-alpha.9', '0.1.0-alpha.10'), isFalse);
      expect(UpdateService.isNewer('v0.1.0-alpha.9', '0.1.0-alpha.10'), isFalse);
    });

    test('Identical version is NOT newer', () {
      expect(UpdateService.isNewer('0.1.0-alpha.10', '0.1.0-alpha.10'), isFalse);
      expect(UpdateService.isNewer('v0.1.0-alpha.10', '0.1.0-alpha.10'), isFalse);
    });

    test('Newer pre-release or channel (alpha.11, beta.1, rc.1) IS newer than alpha.10', () {
      expect(UpdateService.isNewer('0.1.0-alpha.11', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('v0.1.0-alpha.11', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('0.1.0-beta.1', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('0.1.0-rc.1', '0.1.0-alpha.10'), isTrue);
    });

    test('Formal release 0.1.0 is newer than pre-release 0.1.0-alpha.10', () {
      expect(UpdateService.isNewer('0.1.0', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('v0.1.0', '0.1.0-alpha.10'), isTrue);
    });

    test('Major and minor version bumps are newer', () {
      expect(UpdateService.isNewer('0.2.0-alpha.1', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('1.0.0', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('0.0.9', '0.1.0-alpha.10'), isFalse);
    });

    test('Build metadata (+...) is handled correctly', () {
    });
  });
}
