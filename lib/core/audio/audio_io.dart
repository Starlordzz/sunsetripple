import 'dart:typed_data';

typedef PcmCallback = void Function(Int16List pcmSamples);

/// Abstract interface for Platform Audio Input/Output with AEC.
abstract class AudioIo {
  bool get isRecording;
  bool get isPlaying;
  bool get isMuted;

  void setMuted(bool muted);
  void setSpeakerphone(bool enabled);

  Future<void> startCapture(PcmCallback onSampleReady);
  Future<void> stopCapture();

  Future<void> playPcm(Int16List pcmSamples);
  Future<void> stopPlayback();

  Future<void> dispose();
}

/// In-memory Mock AudioIO for pure unit tests & desktop simulation.
class MockAudioIo implements AudioIo {
  @override
  bool isRecording = false;
  @override
  bool isPlaying = false;
  @override
  bool isMuted = false;
  bool isSpeakerOn = true;

  final List<Int16List> playedBuffers = [];
  PcmCallback? _onSampleReady;

  @override
  void setMuted(bool muted) {
    isMuted = muted;
  }

  @override
  void setSpeakerphone(bool enabled) {
    isSpeakerOn = enabled;
  }

  @override
  Future<void> startCapture(PcmCallback onSampleReady) async {
    isRecording = true;
    _onSampleReady = onSampleReady;
  }

  @override
  Future<void> stopCapture() async {
    isRecording = false;
    _onSampleReady = null;
  }

  @override
  Future<void> playPcm(Int16List pcmSamples) async {
    isPlaying = true;
    playedBuffers.add(pcmSamples);
  }

  @override
  Future<void> stopPlayback() async {
    isPlaying = false;
  }

  @override
  Future<void> dispose() async {
    await stopCapture();
    await stopPlayback();
  }

  /// Simulate input PCM from microphone
  void emitMicrophoneFrame(Int16List samples) {
    if (isRecording && !isMuted) {
      _onSampleReady?.call(samples);
    }
  }
}
