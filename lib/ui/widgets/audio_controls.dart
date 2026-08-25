import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// Refined Circular Command Bar (Mute, Speakerphone, Mic Source, Leave).
class AudioControlsBar extends StatelessWidget {
  final bool isNight;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool useBuiltinMic;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleMicSource;
  final VoidCallback onLeave;

  const AudioControlsBar({
    super.key,
    required this.isNight,
    required this.isMuted,
    required this.isSpeakerOn,
    this.useBuiltinMic = false,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onToggleMicSource,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final leaveColor =
        isNight ? AppTheme.darkLeaveRosePink : AppTheme.lightLeaveAccent;
    final activeSunColor =
        isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isNight
            ? Colors.black.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.45),
        border: Border(
          top: BorderSide(
            color: isNight
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 1. Mute
            _CircularCommandButton(
              icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: isMuted ? s.muted : s.micOn,
              isSelected: isMuted,
              activeColor: isMuted ? leaveColor : activeSunColor,
              isNight: isNight,
              onTap: onToggleMute,
            ),

            // 2. Speakerphone / Earpiece
            _CircularCommandButton(
              icon: isSpeakerOn
                  ? Icons.volume_up_rounded
                  : Icons.phone_in_talk_rounded,
              label: isSpeakerOn ? s.speaker : s.earpiece,
              isSelected: isSpeakerOn,
              activeColor: activeSunColor,
              isNight: isNight,
              onTap: onToggleSpeaker,
            ),

            // 3. Mic Source
            _CircularCommandButton(
              icon: useBuiltinMic
                  ? Icons.phone_android_rounded
                  : Icons.headset_mic_rounded,
              label: useBuiltinMic ? s.phoneMic : s.headsetMic,
              isSelected: useBuiltinMic,
              activeColor: activeSunColor,
              isNight: isNight,
              onTap: onToggleMicSource,
            ),

            // 4. Leave Room
            _CircularCommandButton(
              icon: Icons.call_end_rounded,
              label: s.leaveRoom,
              isDestructive: true,
              activeColor: leaveColor,
              isNight: isNight,
              onTap: onLeave,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircularCommandButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isDestructive;
  final Color activeColor;
  final bool isNight;
  final VoidCallback onTap;

  const _CircularCommandButton({
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.isDestructive = false,
    required this.activeColor,
    required this.isNight,
    required this.onTap,
  });

  @override
  State<_CircularCommandButton> createState() => _CircularCommandButtonState();
}

class _CircularCommandButtonState extends State<_CircularCommandButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final textSecondary = widget.isNight
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final textPrimary = widget.isNight
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;

    final Color containerColor;
    final Color borderColor;
    final Color iconColor;
    final Color labelColor;

    if (widget.isDestructive) {
      containerColor = widget.activeColor.withValues(alpha: 0.14);
      borderColor = widget.activeColor.withValues(alpha: 0.55);
      iconColor = widget.activeColor;
      labelColor = widget.activeColor;
    } else if (widget.isSelected) {
      containerColor = widget.activeColor.withValues(alpha: 0.18);
      borderColor = widget.activeColor;
      iconColor = widget.activeColor;
      labelColor = textPrimary;
    } else {
      containerColor = widget.isNight
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04);
      borderColor = widget.isNight
          ? const Color(0xFF283A52)
          : const Color(0xFFDCCEC8);
      iconColor = textSecondary;
      labelColor = textSecondary;
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: containerColor,
                  border: Border.all(color: borderColor, width: 1.3),
                  boxShadow: widget.isSelected || widget.isDestructive
                      ? [
                          BoxShadow(
                            color: iconColor.withValues(alpha: 0.22),
                            blurRadius: 10,
                            spreadRadius: 1,
                          )
                        ]
                      : [],
                ),
                child: Icon(widget.icon, size: 24, color: iconColor),
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
