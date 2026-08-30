import 'package:flutter/material.dart';

/// 进房转场的编排表。
///
/// 整段转场由 [SessionStage] 的单个 0→1 进度驱动，这里把这条时间轴切成三段：
///
/// ```
/// 0.00        0.40 0.52                    1.00
///  |--- 首页 UI 依次离场 ---|
///        0.18 |------- 背景挪动/放大 -------| 0.72
///                  |------ 房间 UI 依次入场 ------|
/// ```
///
/// 三段刻意重叠：首页元素还在往下淡出时，背景已经开始长大；背景快停稳时，
/// 房间的 UI 已经浮上来了。中间不留空档，整体才是一镜到底的感觉。
class StageChoreography {
  const StageChoreography._();

  /// 一次完整进房转场的时长。退场走反向，稍快一些。
  static const Duration enterDuration = Duration(milliseconds: 1050);
  static const Duration exitDuration = Duration(milliseconds: 640);

  // --- 第一段：首页元素离场 ---
  static const double _homeExitFirstStart = 0.0;
  static const double _homeExitStagger = 0.045;
  static const double _homeExitSpan = 0.22;

  // --- 第二段：背景形变 ---
  static const Interval background = Interval(0.18, 0.72, curve: Curves.easeInOutCubic);

  // --- 第三段：房间元素入场 ---
  static const double _roomEnterFirstStart = 0.52;
  static const double _roomEnterStagger = 0.07;
  static const double _roomEnterSpan = 0.26;

  /// 第 [index] 个首页元素的离场区间。索引越大越晚走。
  static Interval homeExit(int index) {
    final start = _homeExitFirstStart + index * _homeExitStagger;
    return Interval(
      start.clamp(0.0, 1.0),
      (start + _homeExitSpan).clamp(0.0, 1.0),
      curve: Curves.easeInCubic,
    );
  }

  /// 第 [index] 个房间元素的入场区间。索引越大越晚到。
  static Interval roomEnter(int index) {
    final start = _roomEnterFirstStart + index * _roomEnterStagger;
    return Interval(
      start.clamp(0.0, 1.0),
      (start + _roomEnterSpan).clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    );
  }
}

/// 首页元素的离场：随进度往下沉、缩一点、淡出。
///
/// 接的是 [Animation] 而不是每帧算好的 double：[child] 只建一次，
/// 每帧重建的只有外面这层 Opacity/Transform。首页那棵树里有 ListView 和
/// 好几个 StreamBuilder，按帧重建它是这段动画掉帧的主因之一。
class StageExitItem extends StatelessWidget {
  final Animation<double> stage;
  final int index;
  final Widget child;

  /// 下沉距离（逻辑像素）。
  final double drift;

  const StageExitItem({
    super.key,
    required this.stage,
    required this.index,
    required this.child,
    this.drift = 32,
  });

  @override
  Widget build(BuildContext context) {
    final interval = StageChoreography.homeExit(index);
    return AnimatedBuilder(
      animation: stage,
      child: child,
      builder: (context, child) {
        final t = interval.transform(stage.value.clamp(0.0, 1.0));
        if (t >= 1.0) return const SizedBox.shrink();
        if (t <= 0.0) return child!;

        return Opacity(
          opacity: 1.0 - t,
          child: Transform.translate(
            offset: Offset(0, drift * t),
            child: Transform.scale(
              scale: 1.0 - 0.04 * t,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// 房间元素的入场：从下方浮上来、淡入。
///
/// 同样只重建外层包装，[child] 建一次。
class StageEnterItem extends StatelessWidget {
  final Animation<double> stage;
  final int index;
  final Widget child;

  /// 起始下移距离（逻辑像素）。
  final double rise;

  /// 起始缩放。小于 1 会有"从远处来"的感觉；中心的对讲盘用得上。
  final double fromScale;

  const StageEnterItem({
    super.key,
    required this.stage,
    required this.index,
    required this.child,
    this.rise = 28,
    this.fromScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final interval = StageChoreography.roomEnter(index);
    return AnimatedBuilder(
      animation: stage,
      child: child,
      builder: (context, child) {
        final t = interval.transform(stage.value.clamp(0.0, 1.0));
        if (t >= 1.0) return child!;
        // 还没轮到它出场，占住位置但不画，免得布局在入场瞬间跳一下。
        if (t <= 0.0) return Opacity(opacity: 0, child: child);

        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, rise * (1.0 - t)),
            child: Transform.scale(
              scale: fromScale + (1.0 - fromScale) * t,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
