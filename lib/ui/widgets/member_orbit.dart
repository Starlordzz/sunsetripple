import 'package:flutter/material.dart';
import '../../core/session/member.dart';
import '../theme/app_theme.dart';

/// Member Horizontal Orbit Track displaying active participants and speaking waves.
class MemberOrbit extends StatelessWidget {
  final List<Member> members;
  final bool isNight;
  final ValueChanged<Member>? onTapMember;

  const MemberOrbit({
    super.key,
    required this.members,
    required this.isNight,
    this.onTapMember,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final member = members[index];
          return GestureDetector(
            onTap: () => onTapMember?.call(member),
            child: _MemberAvatarChip(
              member: member,
              isNight: isNight,
            ),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg,
            border: Border.all(
              color: member.isSpeaking
                  ? activeBorderColor
                  : (isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8)),
              width: member.isSpeaking ? 2.5 : 1.2,
            ),
            boxShadow: member.isSpeaking
                ? [
                    BoxShadow(
                      color: speakingGlow.withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 2,
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
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (member.isHost)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  Icons.star,
                  size: 11,
                  color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                ),
              ),
            Text(
              member.nickname,
              style: TextStyle(
                fontSize: 11,
                color: isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ],
    );
  }
}
