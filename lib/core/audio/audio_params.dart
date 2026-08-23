/// SunsetRipple Standard Audio Parameters
class AudioParams {
  static const int sampleRate = 16000; // 16 kHz
  static const int channels = 1;       // Mono
  static const int frameDurationMs = 20; // 20 ms
  static const int samplesPerFrame = (sampleRate * frameDurationMs) ~/ 1000; // 320 samples
  static const int bytesPerSample = 2; // 16-bit PCM = 2 bytes
  static const int bytesPerFrame = samplesPerFrame * bytesPerSample; // 640 bytes
}
