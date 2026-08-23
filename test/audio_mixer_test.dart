import 'dart:typed_data';
import 'package:test/test.dart';
import '../lib/core/audio/audio_mixer.dart';

void main() {
  group('AudioMixer Tests', () {
    test('Mixes two streams with summing', () {
      final s1 = Int16List.fromList([1000, 2000, -3000]);
      final s2 = Int16List.fromList([500, -1000, 1000]);

      final mixed = AudioMixer.mixPcmStreams([s1, s2]);
      expect(mixed, equals(Int16List.fromList([1500, 1000, -2000])));
    });

    test('Clamps on positive and negative saturation overflow', () {
      final s1 = Int16List.fromList([30000, -30000]);
      final s2 = Int16List.fromList([10000, -10000]);

      final mixed = AudioMixer.mixPcmStreams([s1, s2]);
      expect(mixed[0], 32767);   // Clamped to max int16
      expect(mixed[1], -32768);  // Clamped to min int16
    });

    test('Byte conversion roundtrip', () {
      final original = Int16List.fromList([1234, -5678, 32767, -32768]);
      final bytes = AudioMixer.int16ListToBytes(original);
      final decoded = AudioMixer.bytesToInt16List(bytes);

      expect(decoded, equals(original));
    });
  });
}

