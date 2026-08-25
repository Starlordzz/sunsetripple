import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/update/update_service.dart';

void main() {
  group('UpdateService SemVer Comparison Tests', () {
    test('Older pre-release (alpha.7) is NOT newer than current (alpha.8)', () {
      expect(UpdateService.isNewer('0.1.0-alpha.7', '0.1.0-alpha.8'), isFalse);
      expect(UpdateService.isNewer('v0.1.0-alpha.7', '0.1.0-alpha.8'), isFalse);
    });

    test('Identical version is NOT newer', () {
      expect(UpdateService.isNewer('0.1.0-alpha.8', '0.1.0-alpha.8'), isFalse);
      expect(UpdateService.isNewer('v0.1.0-alpha.8', '0.1.0-alpha.8'), isFalse);
    });

    test('Newer pre-release or channel (alpha.9, beta.1, rc.1) IS newer than alpha.8', () {
      expect(UpdateService.isNewer('0.1.0-alpha.9', '0.1.0-alpha.8'), isTrue);
      expect(UpdateService.isNewer('v0.1.0-alpha.9', '0.1.0-alpha.8'), isTrue);
      expect(UpdateService.isNewer('0.1.0-beta.1', '0.1.0-alpha.8'), isTrue);
      expect(UpdateService.isNewer('0.1.0-rc.1', '0.1.0-alpha.8'), isTrue);
    });

    test('Formal release 0.1.0 is newer than pre-release 0.1.0-alpha.8', () {
      expect(UpdateService.isNewer('0.1.0', '0.1.0-alpha.8'), isTrue);
      expect(UpdateService.isNewer('v0.1.0', '0.1.0-alpha.8'), isTrue);
    });

    test('Major and minor version bumps are newer', () {
      expect(UpdateService.isNewer('0.2.0-alpha.1', '0.1.0-alpha.8'), isTrue);
      expect(UpdateService.isNewer('1.0.0', '0.1.0-alpha.8'), isTrue);
      expect(UpdateService.isNewer('0.0.9', '0.1.0-alpha.8'), isFalse);
    });

    test('Build metadata (+...) is handled correctly', () {
      expect(UpdateService.isNewer('0.1.0-alpha.8+10', '0.1.0-alpha.8+9'), isFalse);
      expect(UpdateService.isNewer('0.1.0-alpha.9+1', '0.1.0-alpha.8+9'), isTrue);
    });
  });
}
