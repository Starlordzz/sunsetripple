import 'dart:typed_data';

/// 采集回调：[opusPacket] 是编码后的 Opus 包，[level] 是这一帧的归一化响度（0~1），
/// 用于界面上的波形/音量显示。
typedef OpusFrameCallback = void Function(Uint8List opusPacket, double level);

/// 平台音频接口。
///
/// 整条管线（采集、Opus 编解码、抖动缓冲、混音、播放）都在原生侧，
/// 这里只负责搬运 Opus 包：上行拿到编码结果发出去，下行把收到的帧丢回原生。
///
/// 这样安排的原因：抖动缓冲和混音必须跟着音频时钟走，Dart 的 Timer 有调度漂移；
/// 而且每帧搬 PCM（640 字节）比搬 Opus 包（约 60 字节）贵一个数量级。
abstract class AudioIo {
  bool get isRecording;
  bool get isMuted;
  bool get useBuiltinMic;

  void setMuted(bool muted);
  void setSpeakerphone(bool enabled);
  void setUseBuiltinMic(bool useBuiltin);

  /// 调整上行码率。WiFi 房 24000，蓝牙房 16000（BLE 带宽有限）。
  Future<void> setBitrate(int bitrateBps);

  Future<void> startCapture(
    OpusFrameCallback onFrameReady, {
    int bitrateBps,
  });
  Future<void> stopCapture();

  /// 把收到的**整帧**（含 6 字节帧头）交给原生播放管线。
  /// 原生侧从帧头解析发送方与序号，分流进各自的抖动缓冲。
  Future<void> submitRemoteFrame(Uint8List frameBytes);

  /// 成员离开时清掉它的抖动缓冲与解码器。
  Future<void> removeRemoteMember(int memberId);

  /// 清空所有远端流（换房、重连时用）。
  Future<void> clearRemoteMembers();

  Future<void> stopPlayback();

  Future<void> dispose();
}

/// 纯内存实现，供单元测试与桌面端占位使用。
class MockAudioIo implements AudioIo {
  @override
  bool isRecording = false;
  @override
  bool isMuted = false;
  @override
  bool useBuiltinMic = false;

  bool isSpeakerOn = true;
  int bitrate = 24000;

  /// 被交给「原生播放」的整帧，测试里用来断言下行链路。
  final List<Uint8List> submittedFrames = [];
  final List<int> removedMembers = [];

  OpusFrameCallback? _onFrameReady;

  @override
  void setMuted(bool muted) => isMuted = muted;

  @override
  void setSpeakerphone(bool enabled) => isSpeakerOn = enabled;

  @override
  void setUseBuiltinMic(bool useBuiltin) => useBuiltinMic = useBuiltin;

  @override
  Future<void> setBitrate(int bitrateBps) async => bitrate = bitrateBps;

  @override
  Future<void> startCapture(
    OpusFrameCallback onFrameReady, {
    int bitrateBps = 24000,
  }) async {
    isRecording = true;
    bitrate = bitrateBps;
    _onFrameReady = onFrameReady;
  }

  @override
  Future<void> stopCapture() async {
    isRecording = false;
    _onFrameReady = null;
  }

  @override
  Future<void> submitRemoteFrame(Uint8List frameBytes) async {
    submittedFrames.add(frameBytes);
  }

  @override
  Future<void> removeRemoteMember(int memberId) async {
    removedMembers.add(memberId);
  }

  @override
  Future<void> clearRemoteMembers() async {
    submittedFrames.clear();
    removedMembers.clear();
  }

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {
    await stopCapture();
    await stopPlayback();
  }

  /// 模拟麦克风送上来一个 Opus 包。
  void emitEncodedFrame(Uint8List packet, {double level = 0.5}) {
    if (isRecording && !isMuted) {
      _onFrameReady?.call(packet, level);
    }
  }
}
