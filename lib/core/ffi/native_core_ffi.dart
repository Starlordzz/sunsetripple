import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import '../diagnostics/app_log.dart';

// Native C structs and function pointers
final class SunsetRingBufferOpaque extends ffi.Opaque {}

typedef SunsetRbCreateNative = ffi.Pointer<SunsetRingBufferOpaque> Function(ffi.Size capacity);
typedef SunsetRbCreateDart = ffi.Pointer<SunsetRingBufferOpaque> Function(int capacity);

typedef SunsetRbFreeNative = ffi.Void Function(ffi.Pointer<SunsetRingBufferOpaque> rb);
typedef SunsetRbFreeDart = void Function(ffi.Pointer<SunsetRingBufferOpaque> rb);

typedef SunsetRbWriteNative = ffi.Size Function(
  ffi.Pointer<SunsetRingBufferOpaque> rb,
  ffi.Pointer<ffi.Uint8> data,
  ffi.Size length,
);
typedef SunsetRbWriteDart = int Function(
  ffi.Pointer<SunsetRingBufferOpaque> rb,
  ffi.Pointer<ffi.Uint8> data,
  int length,
);

typedef SunsetRbReadNative = ffi.Size Function(
  ffi.Pointer<SunsetRingBufferOpaque> rb,
  ffi.Pointer<ffi.Uint8> outData,
  ffi.Size length,
);
typedef SunsetRbReadDart = int Function(
  ffi.Pointer<SunsetRingBufferOpaque> rb,
  ffi.Pointer<ffi.Uint8> outData,
  int length,
);

/// High-Performance C/C++ FFI Core Engine Wrapper with Pure Dart Fallback.
class NativeCoreFfi {
  static ffi.DynamicLibrary? _lib;
  static bool _isLoaded = false;

  static SunsetRbCreateDart? _rbCreate;
  static SunsetRbFreeDart? _rbFree;
  static SunsetRbWriteDart? _rbWrite;
  static SunsetRbReadDart? _rbRead;

  static bool get isNativeLoaded => _isLoaded;
  static ffi.DynamicLibrary? get lib => _lib;

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

      if (_lib != null) {
        _rbCreate = _lib!.lookupFunction<SunsetRbCreateNative, SunsetRbCreateDart>('sunset_ring_buffer_create');
        _rbFree = _lib!.lookupFunction<SunsetRbFreeNative, SunsetRbFreeDart>('sunset_ring_buffer_free');
        _rbWrite = _lib!.lookupFunction<SunsetRbWriteNative, SunsetRbWriteDart>('sunset_ring_buffer_write');
        _rbRead = _lib!.lookupFunction<SunsetRbReadNative, SunsetRbReadDart>('sunset_ring_buffer_read');
        _isLoaded = true;
      }
    } catch (e) {
      _isLoaded = false;
      AppLog.warn('FFI', '未能加载原生核心库，已退回纯 Dart 实现', e);
    }
  }

  /// Create a high-performance C++ SPSC lock-free ring buffer
  static ffi.Pointer<SunsetRingBufferOpaque>? createRingBuffer(int capacity) {
    if (!_isLoaded || _rbCreate == null) return null;
    return _rbCreate!(capacity);
  }

  static void freeRingBuffer(ffi.Pointer<SunsetRingBufferOpaque> rb) {
    if (!_isLoaded || _rbFree == null) return;
    _rbFree!(rb);
  }

  static int writeRingBuffer(ffi.Pointer<SunsetRingBufferOpaque> rb, ffi.Pointer<ffi.Uint8> data, int length) {
    if (!_isLoaded || _rbWrite == null) return 0;
    return _rbWrite!(rb, data, length);
  }

  static int readRingBuffer(ffi.Pointer<SunsetRingBufferOpaque> rb, ffi.Pointer<ffi.Uint8> outData, int length) {
    if (!_isLoaded || _rbRead == null) return 0;
    return _rbRead!(rb, outData, length);
  }

  /// 计算一帧 PCM 的归一化响度（0.0 ~ 1.0），用于界面上的波形/音量指示。
  static double calculateRms(Int16List pcmSamples) {
    if (pcmSamples.isEmpty) return 0.0;

    double sumSquares = 0.0;
    for (int i = 0; i < pcmSamples.length; i++) {
      final sample = pcmSamples[i].toDouble();
      sumSquares += sample * sample;
    }

    final rms = math.sqrt(sumSquares / pcmSamples.length);
    return (rms / 32768.0).clamp(0.0, 1.0);
  }
}
