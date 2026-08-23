import 'dart:collection';
import 'dart:typed_data';

/// Adaptive Jitter Buffer for VoIP Audio Playback.
///
/// Features:
/// - Sequence number reordering (handles uint16 sequence wrapping)
/// - Target latency prebuffering (minFrames = 3, maxFrames = 10)
/// - Packet loss concealment detection (returns null on missing frames)
class JitterBuffer {
  final int minFrames;
  final int maxFrames;

  final SplayTreeMap<int, Uint8List> _buffer = SplayTreeMap<int, Uint8List>(_compareSeq);
  int? _nextPlaySeq;
  bool _isPlaying = false;

  JitterBuffer({
    this.minFrames = 3,
    this.maxFrames = 10,
  });

  int get bufferedCount => _buffer.length;
  bool get isPlaying => _isPlaying;

  /// Put a received frame with sequence number [seq] and payload [data].
  void put(int seq, Uint8List data) {
    if (_nextPlaySeq != null) {
      final diff = _seqDiff(seq, _nextPlaySeq!);
      if (diff < 0) {
        // Packet arrived too late, drop it
        return;
      }
    }

    _buffer[seq] = data;

    // Discard oldest if exceeding max buffer capacity
    while (_buffer.length > maxFrames) {
      _buffer.remove(_buffer.firstKey());
    }

    if (!_isPlaying && _buffer.length >= minFrames) {
      _isPlaying = true;
      _nextPlaySeq = _buffer.firstKey();
    }
  }

  /// Get the next frame to decode and play.
  /// Returns [Uint8List] if frame is available, or `null` if lost (trigger PLC).
  Uint8List? pop() {
    if (!_isPlaying) return null;
    if (_buffer.isEmpty) {
      _isPlaying = false;
      return null;
    }

    final targetSeq = _nextPlaySeq ?? _buffer.firstKey()!;
    final frame = _buffer.remove(targetSeq);

    // Advance expected sequence number
    _nextPlaySeq = (targetSeq + 1) & 0xFFFF;
    return frame;
  }

  /// Clear the buffer and reset state.
  void reset() {
    _buffer.clear();
    _nextPlaySeq = null;
    _isPlaying = false;
  }

  /// Sequence number comparison with uint16 wrap-around handling
  static int _compareSeq(int a, int b) {
    final diff = _seqDiff(a, b);
    if (diff > 0) return 1;
    if (diff < 0) return -1;
    return 0;
  }

  static int _seqDiff(int a, int b) {
    int diff = a - b;
    if (diff > 32767) diff -= 65536;
    if (diff < -32768) diff += 65536;
    return diff;
  }
}
