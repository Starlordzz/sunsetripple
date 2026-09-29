import '../clock.dart';
import '../protocol/frame.dart';

/// 会话遥测：帧计数、丢包估算与入房往返时延。
///
/// 从 `RoomSession` 外提。诊断面板过去展示的是写死的默认值，后来改成真实统计，
/// 但统计逻辑和会话状态机混在一起：谁都可能不小心在心跳路径上重置计数器，
/// 而丢包算法本身（uint16 序号回绕、迟到帧不算丢包）值得单独测。
///
/// 职责边界：
///   - 只做**计数与估算**，不持有帧队列、不发帧、不做鉴权
///   - 不依赖任何平台能力，纯计算，可直接单测
class SessionTelemetry {
  SessionTelemetry({this.clock = const SystemClock()});

  /// 用于结算入房往返时延的时钟，可注入。
  ///
  /// 注入而不是直接读系统时间：「JOIN→首份名单」的时延是**规则**（只有会话
  /// 首次入房才计时），不是环境，用假时钟才能确定性断言。
  final Clock clock;

  /// 各发送方最近一次收到的帧序号，用于估算丢包。
  final Map<int, int> _lastSeqBySender = <int, int>{};

  int _receivedFrameCount = 0;
  int _lostFrameCount = 0;

  /// 客户端从发出 JOIN 到收到第一份名单的往返耗时；房主或尚未测量时为 null。
  int? _roundTripTimeMs;

  /// 会话级入房时发出 JOIN 的时刻。
  ///
  /// 房主转移后的重连与断线重连都只是重新 JOIN 一次，那一次的「往返」
  /// 往往在同一批回调里就完成了，报给用户是错的——所以只有会话首次入房才计时。
  DateTime? _joinSentAt;

  int get receivedFrameCount => _receivedFrameCount;
  int get lostFrameCount => _lostFrameCount;
  int? get roundTripTimeMs => _roundTripTimeMs;

  /// 丢包率（0~100 的整数）。没有样本时返回 0。
  int get lossPercent {
    final total = _receivedFrameCount + _lostFrameCount;
    if (total <= 0) return 0;
    return ((_lostFrameCount * 100) / total).round().clamp(0, 100);
  }

  /// 开始计时一次入房往返。仅在会话首次入房时调用。
  void beginJoinRoundTrip() {
    _joinSentAt = clock.now();
  }

  /// 用「发出 JOIN 到现在」结算往返时延。没有在计时时保持原值。
  void captureRoundTrip() {
    final sentAt = _joinSentAt;
    if (sentAt == null) return;
    _roundTripTimeMs = clock.now().difference(sentAt).inMilliseconds;
    _joinSentAt = null;
  }

  /// 用各发送方的序号缺口估算丢包。
  ///
  /// 序号按发送方单调递增、溢出回绕；可靠（TCP）与不可靠（UDP 语音）通道共用
  /// 同一计数器，因此缺口主要来自丢掉的语音帧。迟到或重排的旧帧不计入丢失，
  /// 避免把抖动当成丢包。
  ///
  /// `selfMemberId` 的帧不计入——那是本机回送/中继，不代表网络质量。
  void recordFrame(Frame frame, {required int selfMemberId}) {
    if (frame.senderId == selfMemberId) return;
    _receivedFrameCount++;

    final last = _lastSeqBySender[frame.senderId];
    if (last == null) {
      _lastSeqBySender[frame.senderId] = frame.seq;
      return;
    }

    final diff = (frame.seq - last) & 0xFFFF;
    if (diff == 0) return; // 重复帧
    if (diff < 0x8000) {
      // 前向推进：中间缺的即丢失
      _lostFrameCount += diff - 1;
      _lastSeqBySender[frame.senderId] = frame.seq;
    }
    // diff >= 0x8000 视为迟到/重排的旧帧，不推进游标也不计丢包
  }

  /// 清零全部统计。入房与离房各调一次。
  void reset() {
    _lastSeqBySender.clear();
    _receivedFrameCount = 0;
    _lostFrameCount = 0;
    _roundTripTimeMs = null;
    _joinSentAt = null;
  }
}
