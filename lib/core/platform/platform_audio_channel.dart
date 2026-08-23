import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../audio/audio_io.dart';

/// Unified Platform Channel Contract for Hardware Audio & Acoustic Echo Cancellation (AEC).
class PlatformAudioChannel implements AudioIo {
  static const MethodChannel _methodChannel =
      MethodChannel('host.msknet.sunsetripple/audio');
  static const EventChannel _eventChannel =
      EventChannel('host.msknet.sunsetripple/audio_events');

  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  StreamSubscription? _eventSubscription;
  PcmCallback? _onPcmReady;

  @override
  bool get isRecording => _isRecording;
  @override
  bool get isPlaying => _isPlaying;
  @override
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;

  @override
  void setMuted(bool muted) {
    _isMuted = muted;
    _methodChannel.invokeMethod('setMuted', {'muted': muted}).catchError((_) {});
  }

  @override
  void setSpeakerphone(bool enabled) {
    _isSpeakerOn = enabled;
    _methodChannel.invokeMethod('setSpeakerphone', {'enabled': enabled}).catchError((_) {});
  }

  @override
  Future<void> startCapture(PcmCallback onSampleReady) async {
    _isRecording = true;
    _onPcmReady = onSampleReady;

    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Uint8List) {
        final pcmList = Int16List.view(event.buffer, event.offsetInBytes, event.lengthInBytes ~/ 2);
        _onPcmReady?.call(pcmList);
      }
    }, onError: (_) {});

    try {
      await _methodChannel.invokeMethod('startCapture', {
        'sampleRate': 16000,
        'channels': 1,
        'frameDurationMs': 20,
      });
    } catch (_) {}
  }

  @override
  Future<void> stopCapture() async {
    _isRecording = false;
    _onPcmReady = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await _methodChannel.invokeMethod('stopCapture');
    } catch (_) {}
  }

  @override
  Future<void> playPcm(Int16List pcmSamples) async {
    _isPlaying = true;
    final uint8Bytes = pcmSamples.buffer.asUint8List(
      pcmSamples.offsetInBytes,
      pcmSamples.lengthInBytes,
    );
    try {
      await _methodChannel.invokeMethod('playPcm', {'data': uint8Bytes});
    } catch (_) {}
  }

  @override
  Future<void> stopPlayback() async {
    _isPlaying = false;
    try {
      await _methodChannel.invokeMethod('stopPlayback');
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stopCapture();
    await stopPlayback();
  }
}

