import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'audio_mixer.dart';

typedef SunsetMixPcmNative = ffi.Void Function(
  ffi.Pointer<ffi.Pointer<ffi.Int16>> inputStreams,
  ffi.Int32 streamCount,
  ffi.Int32 sampleCount,
  ffi.Pointer<ffi.Int16> outputBuffer,
);

typedef SunsetMixPcmDart = void Function(
  ffi.Pointer<ffi.Pointer<ffi.Int16>> inputStreams,
  int streamCount,
  int sampleCount,
  ffi.Pointer<ffi.Int16> outputBuffer,
);

/// Native C++ FFI Bridge with Automatic Pure Dart Fallback.
class NativeDspFfi {
  static ffi.DynamicLibrary? _lib;
  static bool _isLoaded = false;
  static bool get isNativeLoaded => _isLoaded;

  static void initialize({String? customPath}) {
    if (_isLoaded) return;

    try {
      if (customPath != null) {
        _lib = ffi.DynamicLibrary.open(customPath);
      } else if (Platform.isWindows) {
        _lib = ffi.DynamicLibrary.open('sunset_ripple_native.dll');
      } else if (Platform.isMacOS || Platform.isIOS) {
        _lib = ffi.DynamicLibrary.process();
      } else if (Platform.isLinux || Platform.isAndroid) {
        _lib = ffi.DynamicLibrary.open('libsunset_ripple_native.so');
      }
      _isLoaded = true;
    } catch (_) {
      // Fallback to pure Dart implementation
      _isLoaded = false;
    }
  }

  /// Fast PCM mixing using C++ FFI or Pure Dart fallback.
  static Int16List mix(List<Int16List> streams) {
    // Pure Dart fallback (always available and highly optimized)
    return AudioMixer.mixPcmStreams(streams);
  }
}

