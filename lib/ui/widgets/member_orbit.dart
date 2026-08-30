import 'package:flutter/material.dart';
import '../../core/session/member.dart';
import '../theme/app_theme.dart';

/// Member Horizontal Orbit Track displaying active participants and speaking waves.
class MemberOrbit extends StatelessWidget {
  final List<Member> members;
  final bool isNight;

  const MemberOrbit({
    super.key,
    required this.members,
    required this.isNight,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final member = members[index];
          return _MemberAvatarChip(
            member: member,
            isNight: isNight,
          );
        },
      ),
    );
  }
}

class _MemberAvatarChip extends StatelessWidget {
  final Member member;
  final bool isNight;

  const _MemberAvatarChip({
    required this.member,
    required this.isNight,
  });

  @override
  Widget build(BuildContext context) {
    final activeBorderColor = isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral;
    final speakingGlow = member.isSpeaking
        ? (isNight ? const Color(0xFF6B9BE8) : const Color(0xFFF39C82))
        : Colors.transparent;

    return SizedBox(
      // 固定宽度，昵称才有可省略的边界；否则横向列表里 Row 拿到的是无界约束。
      width: 92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg,
            border: Border.all(
              color: member.isSpeaking ? activeBorderColor : (isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8)),
              width: member.isSpeaking ? 3.0 : 1.4,
            ),
            boxShadow: member.isSpeaking
                ? [
                    BoxShadow(
                      color: speakingGlow.withValues(alpha: 0.45),
                      blurRadius: 12,
                      spreadRadius: 2.5,
                    )
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              member.nickname.isNotEmpty ? member.nickname.characters.first : "?",
              style: TextStyle(
                color: isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (member.isHost)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Icon(
                  Icons.star,
                  size: 14,
                  color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                ),
              ),
            Flexible(
              child: Text(
                member.nickname,
                style: TextStyle(
                  fontSize: 14,
                  color: isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        ],
      ),
    );
  }
}

