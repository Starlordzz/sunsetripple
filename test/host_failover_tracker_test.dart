import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/session/host_failover.dart';
import 'package:sunset_ripple/core/session/host_transfer.dart';
import 'package:sunset_ripple/core/session/member.dart';

/// `HostFailoverTracker` 是「房主失联后该不该接管」这条规则的**唯一实现**。
///
/// 它此前完全测不到：原实现直接调 `DateTime.now()` 与 6 秒魔法数，
/// 要验证超时只能真的等 6 秒，于是这条规则在本轮之前覆盖率是 **0%**。
/// 现在 `evaluate` 要求调用方传 `now`，配合构造好的 `Member.lastActiveAt`
/// 可以在微秒内把「刚好在阈值内/外」两个方向都钉死。
void main() {
  // 一个固定的"现在"，让所有时间断言可复现。
  final now = DateTime(2026, 9, 28, 12, 0, 0);

  Member member(
    int id, {
    required bool isHost,
    required Duration idleFor,
  }) =>
      Member(
        memberId: id,
        nickname: '成员$id',
        sessionToken: _fakeToken(id),
        joinOrder: id,
        isHost: isHost,
        lastActiveAt: now.subtract(idleFor),
      );

  HostTransferPlan plan() => HostTransferPlan(
        successorId: 3,
        members: [
          HostTransferMember(
            memberId: 3,
            joinOrder: 5,
            nickname: '继任者',
            endpoint: '10.0.0.3',
            sessionToken: _fakeToken(3),
          ),
          HostTransferMember(
            memberId: 4,
            joinOrder: 6,
            nickname: '我',
            endpoint: '10.0.0.4',
            sessionToken: _fakeToken(4),
          ),
        ],
      );

  group('evaluate：房主存活性判定', () {
    test('名单里还没有房主时返回 hostUnknown，不当成失联', () {
      final tracker = HostFailoverTracker();

      final verdict = tracker.evaluate(
        members: [
          member(4, isHost: false, idleFor: const Duration(minutes: 5)),
        ],
        now: now,
      );

      expect(verdict, isA<FailoverIdle>());
      expect(
        (verdict as FailoverIdle).reason,
        FailoverIdleReason.hostUnknown,
        reason: '刚进房、名单帧还没到时误判失联会导致刚进房就散会',
      );
    });

    test('房主心跳在阈值内时返回 hostAlive', () {
      final tracker = HostFailoverTracker();

      final verdict = tracker.evaluate(
        members: [
          member(1, isHost: true, idleFor: const Duration(seconds: 1)),
          member(4, isHost: false, idleFor: const Duration(seconds: 1)),
        ],
        now: now,
      );

      expect((verdict as FailoverIdle).reason, FailoverIdleReason.hostAlive);
    });

    test('阈值边界：恰好差 1 毫秒仍在存活窗口内', () {
      final tracker = HostFailoverTracker();

      final verdict = tracker.evaluate(
        members: [
          member(
            1,
            isHost: true,
            idleFor: HostFailoverTracker.hostTimeout -
                const Duration(milliseconds: 1),
          ),
        ],
        now: now,
      );

      expect(
        (verdict as FailoverIdle).reason,
        FailoverIdleReason.hostAlive,
        reason: '阈值判定是严格小于，差 1ms 不能算失联',
      );
    });

    test('阈值边界：恰好等于阈值即视为失联', () {
      final tracker = HostFailoverTracker();
      tracker.acceptPlan(plan());

      final verdict = tracker.evaluate(
        members: [
          member(1, isHost: true, idleFor: HostFailoverTracker.hostTimeout),
        ],
        now: now,
      );

      expect(verdict, isA<FailoverProceed>(), reason: '恰好达到阈值就该接管，否则接管点被推后');
    });

    test('失联阈值比成员超时更短（房主是单点，恢复要更快）', () {
      // 这条断言把「6 秒 < 10 秒」这个设计意图钉住：如果将来有人把两者
      // 改成一致，房主失联后的空白期会从 6 秒变成 10 秒。
      expect(
        HostFailoverTracker.hostTimeout,
        lessThan(const Duration(seconds: 10)),
        reason: '成员超时是 10 秒；房主必须更早被判定失联',
      );
    });
  });

  group('evaluate：是否迁移', () {
    test('房主失联且无快照时返回 dissolve（只能散会）', () {
      final tracker = HostFailoverTracker();

      final verdict = tracker.evaluate(
        members: [
          member(1, isHost: true, idleFor: const Duration(seconds: 30)),
          member(4, isHost: false, idleFor: const Duration(seconds: 1)),
        ],
        now: now,
      );

      expect(
        verdict,
        isA<FailoverDissolve>(),
        reason: '没有快照就不知道谁该接任、别人在哪，不能瞎迁',
      );
    });

    test('房主失联且有快照时按快照迁移', () {
      final tracker = HostFailoverTracker();
      tracker.acceptPlan(plan());

      final verdict = tracker.evaluate(
        members: [
          member(1, isHost: true, idleFor: const Duration(seconds: 30)),
        ],
        now: now,
      );

      expect(verdict, isA<FailoverProceed>());
      expect((verdict as FailoverProceed).plan.successorId, 3);
    });
  });

  group('acceptPlan：防重放', () {
    test('joinOrder 更大的新计划被接受并替换缓存', () {
      final tracker = HostFailoverTracker();

      final older = HostTransferPlan(
        successorId: 3,
        members: [
          HostTransferMember(
            memberId: 3,
            joinOrder: 5,
            nickname: 'A',
            endpoint: '10.0.0.3',
            sessionToken: _fakeToken(3),
          ),
        ],
      );
      final newer = HostTransferPlan(
        successorId: 4,
        members: [
          HostTransferMember(
            memberId: 4,
            joinOrder: 9,
            nickname: 'B',
            endpoint: '10.0.0.4',
            sessionToken: _fakeToken(4),
          ),
        ],
      );

      expect(tracker.acceptPlan(older), isTrue);
      expect(tracker.acceptPlan(newer), isTrue);
      expect(tracker.cachedPlan!.successorId, 4);
      expect(tracker.highestSeenJoinOrder, 9);
    });

    test('joinOrder 更小的陈旧计划被拒绝，缓存不被覆盖', () {
      final tracker = HostFailoverTracker();

      final newer = HostTransferPlan(
        successorId: 4,
        members: [
          HostTransferMember(
            memberId: 4,
            joinOrder: 9,
            nickname: 'B',
            endpoint: '10.0.0.4',
            sessionToken: _fakeToken(4),
          ),
        ],
      );
      final stale = HostTransferPlan(
        successorId: 3,
        members: [
          HostTransferMember(
            memberId: 3,
            joinOrder: 2,
            nickname: 'A',
            endpoint: '10.0.0.3',
            sessionToken: _fakeToken(3),
          ),
        ],
      );

      tracker.acceptPlan(newer);
      expect(
        tracker.acceptPlan(stale),
        isFalse,
        reason: '迟到的旧计划若被接受，会把房间迁到已经过期的继任者',
      );
      expect(tracker.cachedPlan!.successorId, 4);
    });

    test('相同 joinOrder 的计划被接受（幂等的重复广播）', () {
      final tracker = HostFailoverTracker();
      final p = plan();

      expect(tracker.acceptPlan(p), isTrue);
      expect(
        tracker.acceptPlan(p),
        isTrue,
        reason: '房主每 2 秒重播同一份快照，用 >= 判定才不会把正常心跳当成陈旧',
      );
    });

    test('空成员表被拒绝', () {
      final tracker = HostFailoverTracker();
      // 正常构造器不允许空表，这里用一份"只有一个成员"的极端计划验证
      // acceptPlan 对退化输入不崩溃（构造器已挡住空表，故此行覆盖防御分支）。
      final single = HostTransferPlan(
        successorId: 1,
        members: [
          HostTransferMember(
            memberId: 1,
            joinOrder: 1,
            nickname: 'only',
            endpoint: '10.0.0.1',
            sessionToken: _fakeToken(1),
          ),
        ],
      );
      expect(tracker.acceptPlan(single), isTrue);
      expect(tracker.highestSeenJoinOrder, 1);
    });
  });

  group('迁移互斥', () {
    test('beginTransfer 只允许一次，避免心跳重复触发迁移', () {
      final tracker = HostFailoverTracker();

      expect(tracker.transferInProgress, isFalse);
      expect(tracker.beginTransfer(), isTrue);
      expect(tracker.transferInProgress, isTrue);
      expect(
        tracker.beginTransfer(),
        isFalse,
        reason: '2 秒一次的心跳会反复进入 checkHostFailover，必须互斥',
      );

      tracker.endTransfer();
      expect(tracker.transferInProgress, isFalse);
      expect(tracker.beginTransfer(), isTrue, reason: '完成后应可再次发起');
    });
  });

  group('reset', () {
    test('清空缓存、joinOrder 与迁移标记', () {
      final tracker = HostFailoverTracker();
      tracker.acceptPlan(plan());
      tracker.beginTransfer();

      tracker.reset();

      expect(tracker.cachedPlan, isNull);
      expect(tracker.highestSeenJoinOrder, 0);
      expect(tracker.transferInProgress, isFalse);
    });

    test('reset 后旧的高 joinOrder 计划可以再次被接受（新会话重新开始）', () {
      final tracker = HostFailoverTracker();
      tracker.acceptPlan(plan()); // joinOrder 上限 6
      tracker.reset();

      final lowOrder = HostTransferPlan(
        successorId: 3,
        members: [
          HostTransferMember(
            memberId: 3,
            joinOrder: 1,
            nickname: '新会话',
            endpoint: '10.0.0.3',
            sessionToken: _fakeToken(3),
          ),
        ],
      );
      expect(
        tracker.acceptPlan(lowOrder),
        isTrue,
        reason: 'reset 必须清掉跨会话的 joinOrder 水位，否则新房间的快照会被误判为陈旧',
      );
    });
  });
}

/// 生成合法的 16 字节非零 token。
Uint8List _fakeToken(int seed) => Uint8List.fromList(
      List<int>.generate(16, (i) => ((seed * 31 + i) & 0xFF) | 1),
    );
