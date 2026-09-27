import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/session/reconnect_controller.dart';

/// 断线重连此前**完全没有测试**：退避序列、放弃回调、以及「重连途中用户
/// 自己退了房」时定时器必须不再触发——这些路径在近场场景（换房主、信号闪断）
/// 里最常被走到，也是改坏之后最难发现的。
void main() {
  group('ReconnectController', () {
    late int maxRetriesReached;
    late int attempts;

    /// 手动推进时间：用 [`fakeAsync`] 语义太绕，这里直接注入自定义退避序列，
    /// 全部用 `Duration.zero`，让测试只关心「顺序与次数」而不是墙上时钟。
    ReconnectController build({
      required Future<bool> Function() onAttempt,
      List<Duration>? delays,
    }) {
      return ReconnectController(
        onAttemptReconnect: onAttempt,
        onMaxRetriesReached: () => maxRetriesReached++,
        delays: delays ?? const [Duration.zero, Duration.zero, Duration.zero],
      );
    }

    setUp(() {
      maxRetriesReached = 0;
      attempts = 0;
    });

    /// 把事件循环推进足够多轮。退避时长都是 `Duration.zero`，所以
    /// N 轮微任务 + 宏任务足够跑完；不用固定 sleep，CI 慢也不会假失败。
    Future<void> settle() async {
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('默认退避序列是 1s / 2s / 4s', () {
      expect(ReconnectController.defaultDelays, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]);
    });

    test('重连成功即停止，不再有后续尝试', () async {
      final controller = build(onAttempt: () async {
        attempts++;
        return true; // 第一次就成功
      });

      controller.start();
      expect(controller.isReconnecting, isTrue);
      await settle();

      expect(attempts, 1);
      expect(controller.isReconnecting, isFalse);
      expect(controller.retryCount, 0, reason: '成功后应 cancel 归零');
      expect(maxRetriesReached, 0);
    });

    test('连续失败会耗尽三次退避并触发放弃回调', () async {
      final controller = build(onAttempt: () async {
        attempts++;
        return false;
      });

      controller.start();
      await settle();

      expect(attempts, 3, reason: 'delays 长度为 3');
      expect(maxRetriesReached, 1, reason: '耗尽后必须恰好回调一次');
      expect(controller.isReconnecting, isFalse);
    });

    test('中途成功不会触发放弃回调', () async {
      final controller = build(onAttempt: () async {
        attempts++;
        return attempts >= 2; // 第二次成功
      });

      controller.start();
      await settle();

      expect(attempts, 2);
      expect(maxRetriesReached, 0);
    });

    test('cancel() 之后在途的退避定时器不再触发回调', () async {
      final controller = build(
        delays: const [Duration(milliseconds: 30), Duration(milliseconds: 30)],
        onAttempt: () async {
          attempts++;
          return false;
        },
      );

      controller.start();
      controller.cancel(); // 用户自己退房了

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(attempts, 0, reason: 'cancel 后必须彻底静默，不能还在后台重连');
      expect(maxRetriesReached, 0, reason: '主动取消不算「放弃」');
      expect(controller.isReconnecting, isFalse);
    });

    test('cancel() 使在途的那一次尝试结果被丢弃', () async {
      final releaseAttempt = Completer<void>();
      final controller = build(onAttempt: () async {
        attempts++;
        await releaseAttempt.future; // 卡住，模拟连接超时中
        return true;
      });

      controller.start();
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1, reason: '第一次尝试已经开始');

      controller.cancel();
      releaseAttempt.complete(); // 尝试「成功」了，但已经取消
      await settle();

      expect(controller.isReconnecting, isFalse,
          reason: 'cancel 后的成功结果不得把状态翻回「重连中」');
      expect(maxRetriesReached, 0);
    });

    test('start() 会先取消上一轮，不会叠加两条重连链', () async {
      final controller = build(onAttempt: () async {
        attempts++;
        return false;
      });

      controller.start();
      controller.start(); // 例如断线事件连发两次
      await settle();

      expect(attempts, 3, reason: '两轮叠加会变成 6 次');
    });

    test('start() 重置 retryCount', () async {
      final controller = build(
        delays: const [Duration.zero, Duration.zero, Duration.zero],
        onAttempt: () async => false,
      );
      controller.start();
      await settle();
      expect(controller.retryCount, 3);

      controller.start();
      expect(controller.retryCount, 0);
      controller.cancel();
    });
  });
}
