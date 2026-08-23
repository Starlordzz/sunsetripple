import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Push-To-Talk (PTT) Central Interactive Disc Button.
class PttButton extends StatefulWidget {
  final bool isNight;
  final bool isPressed;
  final ValueChanged<bool> onStateChanged;

  const PttButton({
    super.key,
    required this.isNight,
    required this.isPressed,
    required this.onStateChanged,
  });

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant PttButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPressed != oldWidget.isPressed) {
      if (widget.isPressed) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onPressDown(TapDownDetails _) {
    HapticFeedback.mediumImpact();
    widget.onStateChanged(true);
  }

  void _onPressUp(TapUpDetails _) {
    HapticFeedback.lightImpact();
    widget.onStateChanged(false);
  }

  void _onPressCancel() {
    widget.onStateChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetBurgundy;
    final pressedColor = widget.isNight ? const Color(0xFF5D85C2) : const Color(0xFFBA5F68);

    return GestureDetector(
      onTapDown: _onPressDown,
      onTapUp: _onPressUp,
      onTapCancel: _onPressCancel,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isPressed ? pressedColor : activeColor,
                boxShadow: [
                  BoxShadow(
                    color: (widget.isPressed ? pressedColor : activeColor).withValues(alpha: 0.38),
                    blurRadius: widget.isPressed ? 32 : 18,
                    spreadRadius: widget.isPressed ? 6 : 2,
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.isPressed ? Icons.mic : Icons.mic_none,
                      size: 46,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isPressed ? "正在讲话" : "按住说话",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

