import 'dart:typed_data';
import 'package:test/test.dart';
import '../lib/core/audio/jitter_buffer.dart';

void main() {
  group('JitterBuffer Tests', () {
    test('Buffers until minFrames threshold then outputs in order', () {
      final jb = JitterBuffer(minFrames: 3, maxFrames: 10);
      final frame1 = Uint8List.fromList([1]);
      final frame2 = Uint8List.fromList([2]);
      final frame3 = Uint8List.fromList([3]);

      jb.put(1, frame1);
      expect(jb.isPlaying, isFalse);
      expect(jb.pop(), isNull);

      jb.put(2, frame2);
      expect(jb.isPlaying, isFalse);

      jb.put(3, frame3);
      expect(jb.isPlaying, isTrue);

      expect(jb.pop(), equals(frame1));
      expect(jb.pop(), equals(frame2));
      expect(jb.pop(), equals(frame3));
      expect(jb.pop(), isNull);
    });

    test('Reorders out-of-order packets correctly', () {
      final jb = JitterBuffer(minFrames: 3, maxFrames: 10);
      jb.put(3, Uint8List.fromList([3]));
      jb.put(1, Uint8List.fromList([1]));
      jb.put(2, Uint8List.fromList([2]));

      expect(jb.isPlaying, isTrue);
      expect(jb.pop(), equals(Uint8List.fromList([1])));
      expect(jb.pop(), equals(Uint8List.fromList([2])));
      expect(jb.pop(), equals(Uint8List.fromList([3])));
    });

    test('Discards old late frames', () {
      final jb = JitterBuffer(minFrames: 1, maxFrames: 5);
      jb.put(10, Uint8List.fromList([10]));
      jb.pop(); // advanced nextPlaySeq to 11

      jb.put(5, Uint8List.fromList([5])); // late frame, should be discarded
      expect(jb.bufferedCount, 0);
    });
  });
}

