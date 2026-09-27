import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../diagnostics/app_log.dart';

// Native C structs and function pointers
final class SunsetRingBufferOpaque extends ffi.Opaque {}

/// 与 native/src/protocol_frame.h 的 `SunsetNativeFrame` 二进制布局一致。
final class SunsetNativeFrame extends ffi.Struct {
  @ffi.Uint8()
  external int type;

  @ffi.Uint8()
  external int senderId;

  @ffi.Uint16()
  external int seq;

  @ffi.Uint16()
  external int payloadLen;

  @ffi.Array(512)
  external ffi.Array<ffi.Uint8> payload;
}

typedef SunsetRbCreateNative = ffi.Pointer<SunsetRingBufferOpaque> Function(
    ffi.Size capacity);
typedef SunsetRbCreateDart = ffi.Pointer<SunsetRingBufferOpaque> Function(
    int capacity);

typedef SunsetRbFreeNative = ffi.Void Function(
    ffi.Pointer<SunsetRingBufferOpaque> rb);
typedef SunsetRbFreeDart = void Function(
    ffi.Pointer<SunsetRingBufferOpaque> rb);

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

typedef SunsetRbAvailableReadNative = ffi.Size Function(
    ffi.Pointer<SunsetRingBufferOpaque> rb);
typedef SunsetRbAvailableReadDart = int Function(
    ffi.Pointer<SunsetRingBufferOpaque> rb);

typedef SunsetRbAvailableWriteNative = ffi.Size Function(
    ffi.Pointer<SunsetRingBufferOpaque> rb);
typedef SunsetRbAvailableWriteDart = int Function(
    ffi.Pointer<SunsetRingBufferOpaque> rb);

typedef SunsetRbClearNative = ffi.Void Function(
    ffi.Pointer<SunsetRingBufferOpaque> rb);
typedef SunsetRbClearDart = void Function(
    ffi.Pointer<SunsetRingBufferOpaque> rb);

typedef SunsetCalculateRmsNative = ffi.Float Function(
  ffi.Pointer<ffi.Int16> samples,
  ffi.Int32 sampleCount,
);
typedef SunsetCalculateRmsDart = double Function(
  ffi.Pointer<ffi.Int16> samples,
  int sampleCount,
);

typedef SunsetMixPcmStreamsNative = ffi.Void Function(
  ffi.Pointer<ffi.Pointer<ffi.Int16>> inputStreams,
  ffi.Int32 streamCount,
  ffi.Int32 sampleCount,
  ffi.Pointer<ffi.Int16> outputBuffer,
);
typedef SunsetMixPcmStreamsDart = void Function(
  ffi.Pointer<ffi.Pointer<ffi.Int16>> inputStreams,
  int streamCount,
  int sampleCount,
  ffi.Pointer<ffi.Int16> outputBuffer,
);

typedef SunsetFrameEncodeNative = ffi.Int32 Function(
  ffi.Uint8 type,
  ffi.Uint8 senderId,
  ffi.Uint16 seq,
  ffi.Pointer<ffi.Uint8> payload,
  ffi.Uint16 payloadLen,
  ffi.Pointer<ffi.Uint8> outBuffer,
  ffi.Size outCapacity,
);
typedef SunsetFrameEncodeDart = int Function(
  int type,
  int senderId,
  int seq,
  ffi.Pointer<ffi.Uint8> payload,
  int payloadLen,
  ffi.Pointer<ffi.Uint8> outBuffer,
  int outCapacity,
);

typedef SunsetFrameDecodeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> inBuffer,
  ffi.Size inLen,
  ffi.Pointer<SunsetNativeFrame> outFrame,
);
typedef SunsetFrameDecodeDart = int Function(
  ffi.Pointer<ffi.Uint8> inBuffer,
  int inLen,
  ffi.Pointer<SunsetNativeFrame> outFrame,
);

/// 规范化的 PCM 满量程分母。四端（C / Kotlin / Swift / Dart）必须一致：
/// int16 的负半轴能到 -32768，取 32768 才不会让满量程响度溢出。
const double pcmFullScale = 32768.0;

/// High-Performance C/C++ FFI Core Engine Wrapper with Pure Dart Fallback.
class NativeCoreFfi {
  static ffi.DynamicLibrary? _lib;
  static bool _isLoaded = false;

  static SunsetRbCreateDart? _rbCreate;
  static SunsetRbFreeDart? _rbFree;
  static SunsetRbWriteDart? _rbWrite;
  static SunsetRbReadDart? _rbRead;
  static SunsetRbAvailableReadDart? _rbAvailableRead;
  static SunsetRbAvailableWriteDart? _rbAvailableWrite;
  static SunsetRbClearDart? _rbClear;

  static SunsetCalculateRmsDart? _calculateRms;
  static SunsetMixPcmStreamsDart? _mixPcmStreams;
  static SunsetFrameEncodeDart? _frameEncode;
  static SunsetFrameDecodeDart? _frameDecode;

  static bool get isNativeLoaded => _isLoaded;
  static ffi.DynamicLibrary? get lib => _lib;

  /// 原生混音器是否可用（否则调用方应自行用 Dart 实现）。
  static bool get hasMixer => _isLoaded && _mixPcmStreams != null;

  /// 原生帧编解码是否可用。
  static bool get hasFrameCodec =>
      _isLoaded && _frameEncode != null && _frameDecode != null;

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
        // 每个符号独立绑定：某个符号在旧产物里缺失时，其余能力仍可用。
        final lib = _lib!;
        _rbCreate = _lookup(() =>
            lib.lookupFunction<SunsetRbCreateNative, SunsetRbCreateDart>(
                'sunset_ring_buffer_create'));
        _rbFree = _lookup(() =>
            lib.lookupFunction<SunsetRbFreeNative, SunsetRbFreeDart>(
                'sunset_ring_buffer_free'));
        _rbWrite = _lookup(() =>
            lib.lookupFunction<SunsetRbWriteNative, SunsetRbWriteDart>(
                'sunset_ring_buffer_write'));
        _rbRead = _lookup(() =>
            lib.lookupFunction<SunsetRbReadNative, SunsetRbReadDart>(
                'sunset_ring_buffer_read'));
        _rbAvailableRead = _lookup(() => lib.lookupFunction<
            SunsetRbAvailableReadNative,
            SunsetRbAvailableReadDart>('sunset_ring_buffer_available_read'));
        _rbAvailableWrite = _lookup(() => lib.lookupFunction<
            SunsetRbAvailableWriteNative,
            SunsetRbAvailableWriteDart>('sunset_ring_buffer_available_write'));
        _rbClear = _lookup(() =>
            lib.lookupFunction<SunsetRbClearNative, SunsetRbClearDart>(
                'sunset_ring_buffer_clear'));
        _calculateRms = _lookup(() => lib.lookupFunction<
            SunsetCalculateRmsNative,
            SunsetCalculateRmsDart>('sunset_calculate_rms'));
        _mixPcmStreams = _lookup(() => lib.lookupFunction<
            SunsetMixPcmStreamsNative,
            SunsetMixPcmStreamsDart>('sunset_mix_pcm_streams'));
        _frameEncode = _lookup(() =>
            lib.lookupFunction<SunsetFrameEncodeNative, SunsetFrameEncodeDart>(
                'sunset_frame_encode'));
        _frameDecode = _lookup(() =>
            lib.lookupFunction<SunsetFrameDecodeNative, SunsetFrameDecodeDart>(
                'sunset_frame_decode'));
        _isLoaded = _rbCreate != null;
      }
    } catch (e) {
      _isLoaded = false;
      AppLog.warn('FFI', '未能加载原生核心库，已退回纯 Dart 实现', e);
    }
  }

  /// 查不到的符号返回 null，而不是让整个原生库初始化失败。
  /// 闭包负责在调用点给出具体的 native / Dart typedef（泛型无法直接传给
  /// `lookupFunction`）。
  static T? _lookup<T>(T Function() body) {
    try {
      return body();
    } catch (_) {
      return null;
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

  static int writeRingBuffer(ffi.Pointer<SunsetRingBufferOpaque> rb,
      ffi.Pointer<ffi.Uint8> data, int length) {
    if (!_isLoaded || _rbWrite == null) return 0;
    return _rbWrite!(rb, data, length);
  }

  static int readRingBuffer(ffi.Pointer<SunsetRingBufferOpaque> rb,
      ffi.Pointer<ffi.Uint8> outData, int length) {
    if (!_isLoaded || _rbRead == null) return 0;
    return _rbRead!(rb, outData, length);
  }

  static int availableRead(ffi.Pointer<SunsetRingBufferOpaque> rb) {
    if (!_isLoaded || _rbAvailableRead == null) return 0;
    return _rbAvailableRead!(rb);
  }

  static int availableWrite(ffi.Pointer<SunsetRingBufferOpaque> rb) {
    if (!_isLoaded || _rbAvailableWrite == null) return 0;
    return _rbAvailableWrite!(rb);
  }

  static void clearRingBuffer(ffi.Pointer<SunsetRingBufferOpaque> rb) {
    if (!_isLoaded || _rbClear == null) return;
    _rbClear!(rb);
  }

  /// 把一段 Dart 字节写进环形缓冲。返回实际写入长度。
  static int writeRingBufferBytes(
      ffi.Pointer<SunsetRingBufferOpaque> rb, Uint8List data) {
    if (!_isLoaded || _rbWrite == null || data.isEmpty) return 0;
    final ptr = malloc<ffi.Uint8>(data.length);
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      return _rbWrite!(rb, ptr, data.length);
    } finally {
      malloc.free(ptr);
    }
  }

  /// 读出当前可读的全部字节。
  static Uint8List readRingBufferBytes(ffi.Pointer<SunsetRingBufferOpaque> rb) {
    final available = availableRead(rb);
    if (available <= 0 || _rbRead == null) return Uint8List(0);
    final ptr = malloc<ffi.Uint8>(available);
    try {
      final read = _rbRead!(rb, ptr, available);
      if (read <= 0) return Uint8List(0);
      return Uint8List.fromList(ptr.asTypedList(read));
    } finally {
      malloc.free(ptr);
    }
  }

  /// 计算一帧 PCM 的归一化响度（0.0 ~ 1.0），用于界面上的波形/音量指示。
  ///
  /// 优先调用 C 实现；原生库不可用时退回等价的 Dart 实现。两者的满量程
  /// 分母同为 [pcmFullScale]，保证各端读数一致。
  static double calculateRms(Int16List pcmSamples) {
    if (pcmSamples.isEmpty) return 0.0;

    final nativeRms = _calculateRms;
    if (_isLoaded && nativeRms != null) {
      final ptr = malloc<ffi.Int16>(pcmSamples.length);
      try {
        ptr.asTypedList(pcmSamples.length).setAll(0, pcmSamples);
        final value = nativeRms(ptr, pcmSamples.length);
        return value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
      } finally {
        malloc.free(ptr);
      }
    }

    double sumSquares = 0.0;
    for (int i = 0; i < pcmSamples.length; i++) {
      final sample = pcmSamples[i].toDouble();
      sumSquares += sample * sample;
    }

    final rms = math.sqrt(sumSquares / pcmSamples.length);
    return (rms / pcmFullScale).clamp(0.0, 1.0);
  }

  /// 多路 16-bit PCM 线性混音（带饱和截断）。原生库不可用时返回 null，
  /// 调用方应退回 Dart 实现。见 native/src/audio_dsp.cpp 的 sunset_mix_pcm_streams。
  static Int16List? mixPcmStreams(List<Int16List> streams, int sampleCount) {
    if (!_isLoaded || _mixPcmStreams == null || streams.isEmpty) return null;
    if (sampleCount <= 0) return Int16List(0);

    final out = malloc<ffi.Int16>(sampleCount);
    final streamPtrsLen = streams.length;
    final streamPtrs = malloc<ffi.Pointer<ffi.Int16>>(streamPtrsLen);
    final buffers = <ffi.Pointer<ffi.Int16>>[];
    try {
      for (var i = 0; i < streamPtrsLen; i++) {
        final buffer = malloc<ffi.Int16>(sampleCount);
        final copy =
            streams[i].length < sampleCount ? streams[i].length : sampleCount;
        buffer.asTypedList(sampleCount).fillRange(0, sampleCount, 0);
        buffer.asTypedList(copy).setAll(0, streams[i].sublist(0, copy));
        buffers.add(buffer);
        streamPtrs[i] = buffer;
      }
      _mixPcmStreams!(streamPtrs, streamPtrsLen, sampleCount, out);
      return Int16List.fromList(out.asTypedList(sampleCount));
    } finally {
      malloc.free(out);
      malloc.free(streamPtrs);
      for (final buffer in buffers) {
        malloc.free(buffer);
      }
    }
  }

  /// 用 C 实现编码一帧协议帧。原生库不可用或参数非法时返回 null。
  static Uint8List? encodeFrame(
      int type, int senderId, int seq, Uint8List payload) {
    if (!_isLoaded || _frameEncode == null) return null;
    if (payload.length > 512) return null;

    final outCapacity = 6 + payload.length;
    final out = malloc<ffi.Uint8>(outCapacity);
    final payloadPtr = malloc<ffi.Uint8>(payload.isEmpty ? 1 : payload.length);
    try {
      if (payload.isNotEmpty) {
        payloadPtr.asTypedList(payload.length).setAll(0, payload);
      }
      final written = _frameEncode!(type, senderId, seq & 0xFFFF, payloadPtr,
          payload.length, out, outCapacity);
      if (written <= 0) return null;
      return Uint8List.fromList(out.asTypedList(written));
    } finally {
      malloc.free(out);
      malloc.free(payloadPtr);
    }
  }

  /// 用 C 实现解码一帧协议帧。原生库不可用或帧非法时返回 null。
  static ({int type, int senderId, int seq, Uint8List payload})? decodeFrame(
      Uint8List data) {
    if (!_isLoaded || _frameDecode == null) return null;

    final inPtr = malloc<ffi.Uint8>(data.isEmpty ? 1 : data.length);
    final framePtr = calloc<SunsetNativeFrame>();
    try {
      if (data.isNotEmpty) {
        inPtr.asTypedList(data.length).setAll(0, data);
      }
      final status = _frameDecode!(inPtr, data.length, framePtr);
      if (status != 0) return null;
      final ref = framePtr.ref;
      final length = ref.payloadLen;
      final payload = Uint8List(length);
      for (var i = 0; i < length; i++) {
        payload[i] = ref.payload[i];
      }
      return (
        type: ref.type,
        senderId: ref.senderId,
        seq: ref.seq,
        payload: payload,
      );
    } finally {
      malloc.free(inPtr);
      calloc.free(framePtr);
    }
  }
}

/// 对 C++ 无锁环形缓冲的 Dart 封装。原生库不可用时 [NativeRingBuffer.create]
/// 返回 null，调用方退回纯 Dart 缓冲。
class NativeRingBuffer {
  final ffi.Pointer<SunsetRingBufferOpaque> _ptr;

  NativeRingBuffer._(this._ptr);

  static NativeRingBuffer? create(int capacity) {
    if (!NativeCoreFfi.isNativeLoaded) return null;
    final ptr = NativeCoreFfi.createRingBuffer(capacity);
    if (ptr == null || ptr == ffi.nullptr) return null;
    return NativeRingBuffer._(ptr);
  }

  int get availableRead => NativeCoreFfi.availableRead(_ptr);
  int get availableWrite => NativeCoreFfi.availableWrite(_ptr);

  int write(Uint8List data) => NativeCoreFfi.writeRingBufferBytes(_ptr, data);

  Uint8List readAll() => NativeCoreFfi.readRingBufferBytes(_ptr);

  void clear() => NativeCoreFfi.clearRingBuffer(_ptr);

  void dispose() => NativeCoreFfi.freeRingBuffer(_ptr);
}
