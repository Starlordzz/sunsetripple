import 'dart:async';
import 'package:flutter/services.dart';
import '../audio/audio_io.dart';
import '../diagnostics/app_log.dart';

const String _tag = '音频';

/// 硬件音频与回声消除（AEC）的统一平台通道。
///
/// 采集、Opus 编解码、抖动缓冲、混音、播放全部在原生侧完成，
/// 这里只搬运 Opus 包。详见 [AudioIo] 的说明。
///
/// 这里的每一次调用失败都必须留下痕迹：原先所有 `invokeMethod` 都被
/// `catch (_) {}` 吞掉，Android 侧没有实现时表现为「界面一切正常但没有声音」，
/// 是这个项目最难定位的一类问题。
class PlatformAudioChannel implements AudioIo {
  static const MethodChannel _methodChannel =
      MethodChannel('host.msknet.sunsetripple/audio');
  static const EventChannel _eventChannel =
      EventChannel('host.msknet.sunsetripple/audio_events');

  bool _isRecording = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _useBuiltinMic = false;

  /// 下行是 20ms 一次的热路径，失败只报第一次，恢复后重新武装。
  bool _submitErrorReported = false;

  StreamSubscription? _eventSubscription;
  OpusFrameCallback? _onFrameReady;

  @override
  bool get isRecording => _isRecording;
  @override
  bool get isMuted => _isMuted;
  @override
  bool get useBuiltinMic => _useBuiltinMic;
  bool get isSpeakerOn => _isSpeakerOn;

  @override
  void setMuted(bool muted) {
    _isMuted = muted;
    _invoke('setMuted', {'muted': muted}, '切换静音');
  }

  @override
  void setSpeakerphone(bool enabled) {
    _isSpeakerOn = enabled;
    _invoke('setSpeakerphone', {'enabled': enabled}, '切换外放/听筒');
  }

  @override
  void setUseBuiltinMic(bool useBuiltin) {
    _useBuiltinMic = useBuiltin;
    _invoke('setUseBuiltinMic', {'useBuiltinMic': useBuiltin}, '切换麦克风来源');
  }

  @override
  Future<void> setBitrate(int bitrateBps) =>
      _invoke('setBitrate', {'bitrate': bitrateBps}, '调整码率');

  @override
  Future<void> startCapture(
    OpusFrameCallback onFrameReady, {
    int bitrateBps = 24000,
  }) async {
    _isRecording = true;
    _onFrameReady = onFrameReady;
    _submitErrorReported = false;

    await _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) {
          AppLog.warn(_tag, '收到非预期的音频事件类型：${event.runtimeType}');
          return;
        }
        final packet = event['data'] as Uint8List?;
        if (packet == null) return;
        final level = (event['level'] as num?)?.toDouble() ?? 0.0;
        _onFrameReady?.call(packet, level);
      },
      onError: (Object e) {
        _isRecording = false;
        AppLog.error(_tag, '麦克风数据流中断，已停止采集', e);
      },
    );

    try {
      await _methodChannel.invokeMethod('startCapture', {
        'bitrate': bitrateBps,
      });
      AppLog.info(_tag, '麦克风已开启（Opus ${bitrateBps}bps）');
    } on PlatformException catch (e) {
      _isRecording = false;
      AppLog.error(_tag, _describe(e, '开启麦克风'), e);
    } on MissingPluginException catch (e) {
      _isRecording = false;
      AppLog.error(_tag, '当前平台没有实现音频通道，无法开启麦克风', e);
    }
  }

  @override
  Future<void> stopCapture() async {
    _isRecording = false;
    _onFrameReady = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _invoke('stopCapture', null, '关闭麦克风');
  }

  @override
  Future<void> submitRemoteFrame(Uint8List frameBytes) async {
    try {
      await _methodChannel.invokeMethod('submitRemoteFrame', {
        'data': frameBytes,
      });
      _submitErrorReported = false;
    } catch (e) {
      if (!_submitErrorReported) {
        _submitErrorReported = true;
        AppLog.error(_tag, '音频送入播放管线失败，将听不到对方的声音', e);
      }
    }
  }

  @override
  Future<void> removeRemoteMember(int memberId) =>
      _invoke('removeRemoteMember', {'memberId': memberId}, '移除成员音频流');

  @override
  Future<void> clearRemoteMembers() =>
      _invoke('clearRemoteMembers', null, '清空音频流');

  @override
  Future<void> stopPlayback() => _invoke('stopPlayback', null, '关闭扬声器');

  @override
  Future<void> dispose() async {
    await stopCapture();
    await stopPlayback();
  }

  Future<void> _invoke(
    String method,
    Map<String, dynamic>? args,
    String what,
  ) async {
    try {
      await _methodChannel.invokeMethod(method, args);
    } on PlatformException catch (e) {
      AppLog.error(_tag, _describe(e, what), e);
    } on MissingPluginException catch (e) {
      AppLog.error(_tag, '当前平台没有实现音频通道，$what 失败', e);
    }
  }

  String _describe(PlatformException e, String what) {
    switch (e.code) {
      case 'PERMISSION_DENIED':
        return '没有录音权限，$what 失败。请在系统设置里允许「落日后残波」使用麦克风';
      case 'CAPTURE_FAILED':
        return '麦克风被其他应用占用，$what 失败';
      case 'PLAYBACK_FAILED':
        return '扬声器初始化失败，$what 失败';
      default:
        return '$what 失败：${e.message ?? e.code}';
    }
  }
}
