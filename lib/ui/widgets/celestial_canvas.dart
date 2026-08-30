import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Dynamic Canvas Painter for Sunset Sun / Moonlit Night & Water Wave Ripples.
class CelestialCanvas extends StatefulWidget {
  final bool isNight;
  final double waveIntensity; // 0.0 ~ 1.0 (audio activity)

  /// 画布高度。进房转场时由 [SessionStage] 在首页高度与房间高度之间插值。
  final double height;

  /// 日轮/月轮圆心的纵向位置，取值为高度的比例。
  final double celestialCenterFactorY;

  /// 日轮/月轮半径（逻辑像素）。
  final double celestialRadius;

  /// 水面波纹起始线的纵向位置，取值为高度的比例。
  final double waterLineFactor;

  const CelestialCanvas({
    super.key,
    required this.isNight,
    this.waveIntensity = 0.0,
    this.height = 260,
    this.celestialCenterFactorY = 0.42,
    this.celestialRadius = 52,
    this.waterLineFactor = 0.76,
  });

  @override
  State<CelestialCanvas> createState() => _CelestialCanvasState();
}

class _CelestialCanvasState extends State<CelestialCanvas>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _CelestialPainter(
            isNight: widget.isNight,
            wavePhase: _animController.value * 2 * math.pi,
            waveIntensity: widget.waveIntensity,
            celestialCenterFactorY: widget.celestialCenterFactorY,
            celestialRadius: widget.celestialRadius,
            waterLineFactor: widget.waterLineFactor,
          ),
        );
      },
    );
  }
}

class _CelestialPainter extends CustomPainter {
  final bool isNight;
  final double wavePhase;
  final double waveIntensity;
  final double celestialCenterFactorY;
  final double celestialRadius;
  final double waterLineFactor;

  _CelestialPainter({
    required this.isNight,
    required this.wavePhase,
    required this.waveIntensity,
    required this.celestialCenterFactorY,
    required this.celestialRadius,
    required this.waterLineFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Sky Gradient
    final skyColors = isNight
        ? [AppTheme.nightSkyBlue, AppTheme.nightDeepOcean, AppTheme.nightAbyss]
        : [AppTheme.sunsetCoral, AppTheme.sunsetBurgundy, AppTheme.sunsetDeepPlum];

    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: skyColors,
      ).createShader(rect);

    canvas.drawRect(rect, skyPaint);

    // 2. Sun / Moon (Celestial Body)
    final celestialCenter =
        Offset(size.width / 2, size.height * celestialCenterFactorY);
    final radius = celestialRadius;

    final celestialColor = isNight ? AppTheme.moonSilverWhite : AppTheme.sunWarmYellow;

    // Outer Glow
    final glowPaint = Paint()
      ..color = celestialColor.withValues(alpha: 0.25 + 0.15 * math.sin(wavePhase))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawCircle(celestialCenter, radius + 14, glowPaint);

    // Main Circle
    final mainPaint = Paint()..color = celestialColor;
    canvas.drawCircle(celestialCenter, radius, mainPaint);

    // 3. Water Surface Ripple Reflections
    final waterY = size.height * waterLineFactor;
    const rippleCount = 5;
    // 波纹跟着天体一起变大，转场时整片背景才像是同一个东西在缩放。
    final rippleScale = radius / 52.0;

    for (int i = 0; i < rippleCount; i++) {
      final y = waterY + i * 14 * rippleScale;
      final progress = i / rippleCount;
      final waveWidth = ((160 + i * 40) + 30 * waveIntensity) * rippleScale;
      final alpha = (0.4 - progress * 0.28).clamp(0.0, 1.0);

      final ripplePaint = Paint()
        ..color = celestialColor.withValues(alpha: alpha)
        ..strokeWidth = 2.5 - progress * 0.8
        ..style = PaintingStyle.stroke;

      final path = Path();
      final startX = size.width / 2 - waveWidth / 2;
      final endX = size.width / 2 + waveWidth / 2;

      path.moveTo(startX, y);
      for (double x = startX; x <= endX; x += 10) {
        final relX = (x - startX) / waveWidth;
        final waveOffset = math.sin(relX * math.pi * 3 + wavePhase + i) *
            (2.5 + waveIntensity * 6);
        path.lineTo(x, y + waveOffset);
      }

      canvas.drawPath(path, ripplePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CelestialPainter oldDelegate) {
    return oldDelegate.isNight != isNight ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.waveIntensity != waveIntensity ||
        oldDelegate.celestialCenterFactorY != celestialCenterFactorY ||
        oldDelegate.celestialRadius != celestialRadius ||
        oldDelegate.waterLineFactor != waterLineFactor;
  }
}

