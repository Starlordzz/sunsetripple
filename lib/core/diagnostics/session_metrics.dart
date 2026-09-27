/// 网络质量分级。`unknown` 表示这次会话还没有任何可用样本。
enum NetworkQuality { good, fair, poor, unknown }

/// 一次会话的结构化指标快照。
///
/// 以前诊断面板只有一个 `roundTripTimeMs`，其余数字散在 `RoomSession` 的
/// 各个 getter 里，导出报告时又只能拼字符串。这里把面板要展示、报告要导出的
/// 字段收敛成一个不可变值对象，并提供 [toJson]（机器可读）与 [toLine]
/// （单行 key=value，日志/面板都能直接用）。
///
/// 刻意不依赖 `RoomSession`：调用方按 getter 逐项喂进来，避免 diagnostics
/// 与 session 两个包相互 import。
class SessionMetrics {
  /// 本轮会话收到的帧数（不含本机发送的回显）。
  final int receivedFrames;

  /// 按各发送方序号缺口估算出的丢失帧数。
  final int lostFrames;

  /// 丢包率（0~100 的整数百分比）。无样本时为 0；由两个帧计数派生。
  final int lossPercent;

  /// 实测往返延迟（毫秒）。房主或尚未测到时为 null。
  final int? roundTripTimeMs;

  /// 被音频管线隐藏（丢包补偿）的帧数。
  final int concealedFrames;

  /// 网络质量分级，由丢包率与延迟共同决定。
  final NetworkQuality networkQuality;

  /// 当前在册成员数（含本机）。
  final int memberCount;

  /// 本次会话已持续的秒数。
  final int uptimeSeconds;

  /// 「良好」的丢包率上限（严格小于）。恰好等于 2% 不算良好。
  static const int goodLossPercent = 2;

  /// 「良好」的延迟上限（严格小于，毫秒）。恰好 150ms 不算良好。
  static const int goodRttMs = 150;

  /// 「一般」的丢包率上限（严格小于）。恰好 8% 不算一般。
  static const int fairLossPercent = 8;

  /// 「一般」的延迟上限（严格小于，毫秒）。恰好 400ms 不算一般。
  static const int fairRttMs = 400;

  SessionMetrics({
    required this.receivedFrames,
    required this.lostFrames,
    this.concealedFrames = 0,
    this.memberCount = 0,
    this.uptimeSeconds = 0,
    this.roundTripTimeMs,
  })  : assert(receivedFrames >= 0, '收到的帧数不可能是负数'),
        assert(lostFrames >= 0, '丢失的帧数不可能是负数'),
        lossPercent = lossPercentOf(receivedFrames, lostFrames),
        networkQuality = classifyQuality(
          receivedFrames: receivedFrames,
          lostFrames: lostFrames,
          roundTripTimeMs: roundTripTimeMs,
        );

  /// 丢包率（0~100 的整数百分比）。
  ///
  /// 没有任何样本（两个计数都是 0）时返回 0，而不是 NaN 或除零异常——
  /// 面板在没有通话数据时展示 0%，语义上等于「还没丢过包」。
  static int lossPercentOf(int receivedFrames, int lostFrames) {
    final total = receivedFrames + lostFrames;
    if (total <= 0) return 0;
    return ((lostFrames * 100) / total).round().clamp(0, 100);
  }

  /// 按丢包率与延迟分级。
  ///
  /// 规则（边界取严格小于，避免「刚好卡在阈值上」被判成更好的一档）：
  ///   - [NetworkQuality.unknown]：既没收到/丢过帧，也没测到延迟 → 无从判断；
  ///   - [NetworkQuality.good]：丢包 < 2% **且** 延迟 < 150ms（两条都要有样本）；
  ///   - [NetworkQuality.fair]：丢包 < 8% **或** 延迟 < 400ms；
  ///   - [NetworkQuality.poor]：两条都超出上面的范围。
  ///
  /// 房主侧测不到 RTT（[roundTripTimeMs] 为 null），因此最多只能判到 fair。
  static NetworkQuality classifyQuality({
    required int receivedFrames,
    required int lostFrames,
    int? roundTripTimeMs,
  }) {
    if (receivedFrames + lostFrames == 0 && roundTripTimeMs == null) {
      return NetworkQuality.unknown;
    }

    final loss = lossPercentOf(receivedFrames, lostFrames);
    if (loss < goodLossPercent &&
        roundTripTimeMs != null &&
        roundTripTimeMs < goodRttMs) {
      return NetworkQuality.good;
    }
    if (loss < fairLossPercent ||
        (roundTripTimeMs != null && roundTripTimeMs < fairRttMs)) {
      return NetworkQuality.fair;
    }
    return NetworkQuality.poor;
  }

  /// 机器可读的导出结构，字段与 [SessionMetrics] 一一对应。
  Map<String, dynamic> toJson() => {
        'receivedFrames': receivedFrames,
        'lostFrames': lostFrames,
        'lossPercent': lossPercent,
        'roundTripTimeMs': roundTripTimeMs,
        'concealedFrames': concealedFrames,
        'networkQuality': networkQuality.name,
        'memberCount': memberCount,
        'uptimeSeconds': uptimeSeconds,
      };

  /// 单行 key=value，方便塞进日志或面板的一行文本。
  String toLine() => 'received=$receivedFrames lost=$lostFrames '
      'loss=$lossPercent% rtt=${roundTripTimeMs ?? '-'}ms '
      'concealed=$concealedFrames quality=${networkQuality.name} '
      'members=$memberCount uptime=${uptimeSeconds}s';

  @override
  String toString() => 'SessionMetrics(${toLine()})';
}
