import 'dart:math';

import '../diagnostics/app_log.dart';
import 'host_transfer.dart';
import 'member.dart';

/// `checkHostFailover` 的**判定结果**。
///
/// 用 sealed class 而不是可空的 `HostTransferPlan?`：原先「房主还活着」、
/// 「名单里还没有房主」、「正在迁移」和「没有快照只能散会」这四种情况全都
/// 走 `return`（其中一种是改状态），调用方无法区分，日志里也看不出到底
/// 为什么没迁移——排障时只能靠猜。
sealed class FailoverVerdict {
  const FailoverVerdict();
}

/// 保持现状。`reason` 用于日志与测试断言。
class FailoverIdle extends FailoverVerdict {
  final FailoverIdleReason reason;
  const FailoverIdle(this.reason);

  @override
  String toString() => 'FailoverIdle(${reason.name})';
}

/// 房主失联且本机没有可用快照——无从得知谁该接任、别人在哪，只能散会。
class FailoverDissolve extends FailoverVerdict {
  const FailoverDissolve();

  @override
  String toString() => 'FailoverDissolve()';
}

/// 应当按 [plan] 迁移。
class FailoverProceed extends FailoverVerdict {
  final HostTransferPlan plan;
  const FailoverProceed(this.plan);

  @override
  String toString() => 'FailoverProceed(successor #${plan.successorId})';
}

/// [FailoverIdle] 的具体原因。写成枚举是为了让测试能断言「为什么没迁移」，
/// 而不是只断言「没迁移」——后者在判定逻辑写错时会假通过。
enum FailoverIdleReason {
  /// 名单里还没标出房主（刚进房、名单帧未到）。
  hostUnknown,

  /// 房主的心跳还在有效窗口内。
  hostAlive,
}

/// 房主故障转移的决策状态。
///
/// 从 `RoomSession` 外提的**纯逻辑**：它不碰传输层、不碰 Stream、**不读时钟**——
/// [evaluate] 要求调用方把 `now` 传进来。这一点很关键：原来的实现直接调
/// `DateTime.now()`，导致「房主失联 6 秒后应当接管」这条规则只能靠**真的等 6 秒**
/// 来验证，于是它多年来一次都没被测过（实测覆盖率 0%）。
///
/// 职责边界：
///   - 持有「最近见过的 joinOrder」（防重放）、「缓存的交接快照」、「是否正在迁移」
///   - 判定「现在该不该迁移、迁给谁」
///   - **不**执行迁移（起监听、重连、广播名单都由会话层做）
class HostFailoverTracker {
  /// 房主心跳失效阈值。
  ///
  /// 比 `PresenceTracker.memberTimeout`（10 秒）**短**是有意的：房主是星型拓扑的单点，
  /// 它失联后整个房间的音频中继与控制面都停了。等 10 秒才接管，用户会先经历
  /// 一段「还在房间里但谁也听不见」的空白期。6 秒 = 3 个心跳周期，足够容忍
  /// 偶发丢包又不会让空白期过长。
  static const Duration hostTimeout = Duration(seconds: 6);

  /// 见过的最大 joinOrder，用于丢弃迟到或被重放的旧计划。
  ///
  /// joinOrder 由房主单调分配，所以更新的计划一定不会更小——这比时间戳可靠，
  /// 因为设备时钟可能回拨。
  int _highestSeenJoinOrder = 0;

  /// 最近一次收到的交接计划（来自交接帧或定期快照）。
  HostTransferPlan? _cachedPlan;

  /// 迁移执行中，避免 2 秒一次的心跳把同一次迁移重复触发。
  bool _transferInProgress = false;

  HostTransferPlan? get cachedPlan => _cachedPlan;
  int get highestSeenJoinOrder => _highestSeenJoinOrder;
  bool get transferInProgress => _transferInProgress;

  /// 接收一份计划（交接帧或快照）。
  ///
  /// 返回 false 表示计划陈旧、已丢弃；true 表示已更新缓存。
  /// 调用方据此决定要不要继续（交接帧还要执行迁移）。
  bool acceptPlan(HostTransferPlan plan) {
    if (plan.members.isEmpty) return false;

    final maxOrder = plan.members.map((m) => m.joinOrder).reduce(max);
    if (maxOrder < _highestSeenJoinOrder) {
      AppLog.debug(
        'RoomSession',
        '忽略陈旧的交接计划（joinOrder $maxOrder < $_highestSeenJoinOrder）',
      );
      return false;
    }

    _highestSeenJoinOrder = maxOrder;
    _cachedPlan = plan;
    return true;
  }

  /// 判定当前是否应当触发故障迁移。
  ///
  /// [now] 由调用方注入，使「超时」这条规则可以被确定性测试。
  /// [members] 用于定位现任房主及其最后活跃时间。
  FailoverVerdict evaluate({
    required Iterable<Member> members,
    required DateTime now,
  }) {
    Member? host;
    for (final member in members) {
      if (member.isHost) {
        host = member;
        break;
      }
    }

    // 刚进房、名单还没到：不能当成「房主失联」，否则会误判散会。
    if (host == null) return const FailoverIdle(FailoverIdleReason.hostUnknown);

    if (now.difference(host.lastActiveAt) < hostTimeout) {
      return const FailoverIdle(FailoverIdleReason.hostAlive);
    }

    final plan = _cachedPlan;
    if (plan == null) return const FailoverDissolve();

    return FailoverProceed(plan);
  }

  /// 标记迁移开始。返回 false 表示已有一个迁移在进行中，调用方应当放弃本次。
  bool beginTransfer() {
    if (_transferInProgress) return false;
    _transferInProgress = true;
    return true;
  }

  void endTransfer() => _transferInProgress = false;

  /// 清空全部状态。入房与离房各调一次。
  void reset() {
    _highestSeenJoinOrder = 0;
    _cachedPlan = null;
    _transferInProgress = false;
  }
}
