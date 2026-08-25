import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Dynamic Canvas Painter for Sunset Sun / Moonlit Night & Water Wave Ripples.
class CelestialCanvas extends StatefulWidget {
  final bool isNight;
  final double waveIntensity; // 0.0 ~ 1.0 (audio activity)
  final double height;

  const CelestialCanvas({
    super.key,
    required this.isNight,
    this.waveIntensity = 0.0,
    this.height = 240,
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

  _CelestialPainter({
    required this.isNight,
    required this.wavePhase,
    required this.waveIntensity,
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
    final celestialCenter = Offset(size.width / 2, size.height * 0.38);
    final celestialRadius = math.min(size.height * 0.22, 50.0);

    final celestialColor = isNight ? AppTheme.moonSilverWhite : AppTheme.sunWarmYellow;

    // Outer Glow
    final glowPaint = Paint()
      ..color = celestialColor.withValues(alpha: 0.25 + 0.15 * math.sin(wavePhase))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(celestialCenter, celestialRadius + 12, glowPaint);

    // Main Circle
    final mainPaint = Paint()..color = celestialColor;
    canvas.drawCircle(celestialCenter, celestialRadius, mainPaint);

    // 3. Water Surface Ripple Reflections
    final waterY = size.height * 0.74;
    const rippleCount = 4;

    for (int i = 0; i < rippleCount; i++) {
      final y = waterY + i * (size.height * 0.055);
      final progress = i / rippleCount;
      final waveWidth = (140 + i * 36) + 26 * waveIntensity;
      final alpha = (0.38 - progress * 0.26).clamp(0.0, 1.0);

      final ripplePaint = Paint()
        ..color = celestialColor.withValues(alpha: alpha)
        ..strokeWidth = 2.2 - progress * 0.8
        ..style = PaintingStyle.stroke;

      final path = Path();
      final startX = size.width / 2 - waveWidth / 2;
      final endX = size.width / 2 + waveWidth / 2;

      path.moveTo(startX, y);
      for (double x = startX; x <= endX; x += 10) {
        final relX = (x - startX) / waveWidth;
        final waveOffset = math.sin(relX * math.pi * 3 + wavePhase + i) *
            (2.2 + waveIntensity * 5);
        path.lineTo(x, y + waveOffset);
      }

      canvas.drawPath(path, ripplePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CelestialPainter oldDelegate) {
    return oldDelegate.isNight != isNight ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.waveIntensity != waveIntensity;
  }
}
