/// 可注入时钟。
///
/// 为什么要有它：`HostFailoverTracker` 把「房主失联 6 秒后接管」改成要求调用方
/// 注入 `now` 之后，这条规则才有了确定性测试；此前直接读 `DateTime.now()`，
/// 只能靠**真的等 6 秒**来验证，实测覆盖率长期为 0。凡是有超时/频率/时间戳
/// 语义的逻辑都应当走这里，测试里换成 [FakeClock] 就能把时间拨快。
///
/// `scripts/check-clock-injection.sh` 会拦住 `lib/core/` 下新增的直接调用；
/// 只允许在真正贴系统边界的少数地方调用，且必须写明 `clock-exempt` 理由。
abstract class Clock {
  const Clock();

  /// 当前时刻。
  DateTime now();
}

/// 生产用时钟：读取系统墙上时钟。
///
/// 全仓库只有这里（以及显式标注 `clock-exempt` 的协议/日志边界）允许直接
/// 调用 `DateTime.now()`。
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// 测试用时钟：时刻由测试显式推进，不随真实时间流逝。
class FakeClock implements Clock {
  FakeClock([DateTime? start])
      : value = start ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// 当前假时刻，可直接赋值。
  DateTime value;

  /// 把假时刻拨快 [delta]。
  void advance(Duration delta) => value = value.add(delta);

  @override
  DateTime now() => value;
}
