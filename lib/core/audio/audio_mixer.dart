import 'dart:typed_data';
import 'audio_params.dart';

/// Software Linear 16-bit PCM Audio Mixer with Saturation Clamping.
class AudioMixer {
  /// Mixes multiple 16-bit PCM streams into a single 16-bit PCM output stream.
  /// Each input is a [Int16List] or [Uint8List] representing 16-bit little/big endian PCM.
  static Int16List mixPcmStreams(List<Int16List> streams) {
    if (streams.isEmpty) {
      return Int16List(AudioParams.samplesPerFrame);
    }
    if (streams.length == 1) {
      return streams.first;
    }

    final sampleCount = streams.map((s) => s.length).reduce((a, b) => a < b ? a : b);
    final output = Int16List(sampleCount);

    for (int i = 0; i < sampleCount; i++) {
      int sum = 0;
      for (int s = 0; s < streams.length; s++) {
        sum += streams[s][i];
      }
      // Saturating clamping to 16-bit signed range [-32768, 32767]
      if (sum > 32767) {
        output[i] = 32767;
      } else if (sum < -32768) {
        output[i] = -32768;
      } else {
        output[i] = sum;
      }
    }
    return output;
  }

  /// Helper to convert 16-bit PCM bytes (Little Endian) to Int16List
  static Int16List bytesToInt16List(Uint8List bytes) {
    final length = bytes.length ~/ 2;
    final int16s = Int16List(length);
    final bd = ByteData.sublistView(bytes);
    for (int i = 0; i < length; i++) {
      int16s[i] = bd.getInt16(i * 2, Endian.little);
    }
    return int16s;
  }

  /// Helper to convert Int16List to 16-bit PCM bytes (Little Endian)
  static Uint8List int16ListToBytes(Int16List int16s) {
    final bytes = Uint8List(int16s.length * 2);
    final bd = ByteData.sublistView(bytes);
    for (int i = 0; i < int16s.length; i++) {
      bd.setInt16(i * 2, int16s[i], Endian.little);
    }
    return bytes;
  }
}
