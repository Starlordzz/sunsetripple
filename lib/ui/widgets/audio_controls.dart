import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Bottom Audio Controls Bar (Mute, Speakerphone, Leave).
class AudioControlsBar extends StatelessWidget {
  final bool isNight;
  final bool isMuted;
  final bool isSpeakerOn;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onLeave;

  const AudioControlsBar({
    super.key,
    required this.isNight,
    required this.isMuted,
    required this.isSpeakerOn,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final leaveColor = isNight ? AppTheme.darkLeaveRosePink : AppTheme.lightLeaveAccent;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 18),
      child: Row(
        children: [
          // 1. 静音
          _ActionButton(
            icon: isMuted ? Icons.mic_off : Icons.mic,
            label: isMuted ? s.muted : s.microphone,
            isActive: !isMuted,
            isNight: isNight,
            onTap: onToggleMute,
            bgColor: cardBg,
            textColor: textPrimary,
          ),

          // 2. 扬声器 / 听筒
          _ActionButton(
            icon: isSpeakerOn ? Icons.volume_up : Icons.phone_in_talk,
            label: isSpeakerOn ? s.speaker : s.earpiece,
            isActive: isSpeakerOn,
            isNight: isNight,
            onTap: onToggleSpeaker,
            bgColor: cardBg,
            textColor: textPrimary,
          ),

          // 3. 离开房间 (高对比度月夜玫瑰粉)
          _ActionButton(
            icon: Icons.call_end,
            label: s.leave,
            isActive: true,
            isNight: isNight,
            onTap: onLeave,
            bgColor: leaveColor.withValues(alpha: 0.15),
            borderColor: leaveColor.withValues(alpha: 0.62),
            textColor: leaveColor,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isNight;
  final VoidCallback onTap;
  final Color bgColor;
  final Color? borderColor;
  final Color textColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isNight,
    required this.onTap,
    required this.bgColor,
    this.borderColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    // 三个按钮均分底部宽度：放大字号后，360dp 的窄屏上原来的自适应宽度会挤爆。
    // 均分之后再套一层 FittedBox，更窄的屏上是整体缩小而不是溢出。
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: borderColor ?? (isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8)),
                width: 1.4,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24, color: textColor),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
