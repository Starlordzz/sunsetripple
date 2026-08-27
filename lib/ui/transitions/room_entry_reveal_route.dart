import 'package:flutter/material.dart';

/// 转场起点：触发按钮在全局坐标下的矩形，以及它的圆角半径。
class RevealOrigin {
  final Rect rect;
  final double borderRadius;

  const RevealOrigin(this.rect, this.borderRadius);
}

/// 从按钮自身形状撑开到全屏的进房转场。
///
/// 房间页盖在首页上方，被一个圆角矩形裁切：这个矩形从按钮的位置和尺寸出发，
/// 一路撑满全屏，圆角同步收敛到 0；边缘再画一圈随进度淡出的天体色描边。
///
/// 时序沿用旧版 Compose（`MainActivity.runEntryTransition`）：
///   - 时长 560ms
///   - 缓动 LinearOutSlowInEasing，即 Cubic(0, 0, 0.2, 1)
///   - 描边 1.4，透明度 (1 - 进度) * 0.18
///
/// 与旧版的差别：旧版 `sunsetCircularReveal` 裁的是圆（`addOval`），
/// 这里按需求改成与按钮同形状的圆角矩形。
class RoomEntryRevealRoute<T> extends PageRouteBuilder<T> {
  /// 为 null 时从屏幕中心零尺寸展开。
  final RevealOrigin? origin;

  /// 边缘描边颜色。白天用日轮暖黄，夜间用冷月银白。
  final Color edgeColor;

  RoomEntryRevealRoute({
    required WidgetBuilder builder,
    required this.origin,
    required this.edgeColor,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 560),
          // 退出不必和进入一样慢，收得快一点更利落。
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return _ShapeRevealTransition(
              animation: CurvedAnimation(
                parent: animation,
                curve: const Cubic(0.0, 0.0, 0.2, 1.0),
                reverseCurve: const Cubic(0.4, 0.0, 1.0, 1.0),
              ),
              origin: origin,
              edgeColor: edgeColor,
              child: child,
            );
          },
        );
}

class _ShapeRevealTransition extends StatelessWidget {
  final Animation<double> animation;
  final RevealOrigin? origin;
  final Color edgeColor;
  final Widget child;

  const _ShapeRevealTransition({
    required this.animation,
    required this.origin,
    required this.edgeColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final fraction = animation.value;

        // 已经铺满，撤掉裁切与 CustomPaint，省一层合成开销。
        if (fraction >= 1.0) return child!;

        return ClipRRect(
          clipper: _RevealClipper(origin: origin, fraction: fraction),
          child: CustomPaint(
            foregroundPainter: _RevealEdgePainter(
              origin: origin,
              fraction: fraction,
              color: edgeColor,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// 当前这一帧的裁切形状：按钮矩形 → 全屏矩形，圆角同步收敛到 0。
RRect _revealRRect(RevealOrigin? origin, double fraction, Size size) {
  final full = Offset.zero & size;
  final start = origin?.rect ??
      Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
  final startRadius = origin?.borderRadius ?? 0.0;

  final rect = Rect.lerp(start, full, fraction) ?? full;
  final radius = startRadius * (1.0 - fraction);
  return RRect.fromRectAndRadius(rect, Radius.circular(radius));
}

class _RevealClipper extends CustomClipper<RRect> {
  final RevealOrigin? origin;
  final double fraction;

  const _RevealClipper({required this.origin, required this.fraction});

  @override
  RRect getClip(Size size) => _revealRRect(origin, fraction, size);

  @override
  bool shouldReclip(_RevealClipper oldClipper) =>
      oldClipper.fraction != fraction || oldClipper.origin != origin;
}

class _RevealEdgePainter extends CustomPainter {
  final RevealOrigin? origin;
  final double fraction;
  final Color color;

  const _RevealEdgePainter({
    required this.origin,
    required this.fraction,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = (1.0 - fraction) * 0.18;
    if (alpha <= 0.0) return;

    canvas.drawRRect(
      _revealRRect(origin, fraction, size),
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..color = color.withOpacity(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_RevealEdgePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.origin != origin ||
      oldDelegate.color != color;
}
