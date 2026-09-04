import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 预设不可自定义的 8 款成员身份头像框主题
class AvatarFrameTheme {
  final String name;
  final List<Color> borderGradient;
  final Color glowColor;

  const AvatarFrameTheme({
    required this.name,
    required this.borderGradient,
    required this.glowColor,
  });

  static const List<AvatarFrameTheme> memberThemes = [
    // 0. 夕阳琥珀
    AvatarFrameTheme(
      name: 'SunsetAmber',
      borderGradient: [AppTheme.sunsetCoral, Color(0xFFFFA726)],
      glowColor: AppTheme.sunsetCoral,
    ),
    // 1. 碧海青风
    AvatarFrameTheme(
      name: 'AzureBreeze',
      borderGradient: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
      glowColor: Color(0xFF00C9FF),
    ),
    // 2. 极光紫霓
    AvatarFrameTheme(
      name: 'AuroraViolet',
      borderGradient: [Color(0xFFDA22FF), Color(0xFF9733EE)],
      glowColor: Color(0xFFDA22FF),
    ),
    // 3. 翡翠霓光
    AvatarFrameTheme(
      name: 'EmeraldGlow',
      borderGradient: [Color(0xFF11998E), Color(0xFF38EF7D)],
      glowColor: Color(0xFF38EF7D),
    ),
    // 4. 炽阳金焰
    AvatarFrameTheme(
      name: 'SolarCrimson',
      borderGradient: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
      glowColor: Color(0xFFFF416C),
    ),
    // 5. 深夜星河
    AvatarFrameTheme(
      name: 'MidnightStar',
      borderGradient: [Color(0xFF3A7BD5), Color(0xFF3A6073)],
      glowColor: Color(0xFF3A7BD5),
    ),
    // 6. 晨曦粉黛
    AvatarFrameTheme(
      name: 'RoseBlush',
      borderGradient: [Color(0xFFFFA07A), Color(0xFFFF69B4)],
      glowColor: Color(0xFFFF69B4),
    ),
    // 7. 赛博钛银
    AvatarFrameTheme(
      name: 'TitaniumSteel',
      borderGradient: [Color(0xFFB0BEC5), Color(0xFF78909C)],
      glowColor: Color(0xFFB0BEC5),
    ),
  ];

  /// 房主专属夕阳荣耀金辉
  static const AvatarFrameTheme hostTheme = AvatarFrameTheme(
    name: 'HostCrown',
    borderGradient: [Color(0xFFFFD700), Color(0xFFFF8C00), Color(0xFFFF4500)],
    glowColor: Color(0xFFFFD700),
  );

  /// 根据短码确定性选择主题（不可自定义，跨退出改名保持恒定）
  static AvatarFrameTheme fromCode(String senderCode, {bool isHost = false}) {
    if (isHost) return hostTheme;
    final code = senderCode.trim().toUpperCase();
    int hash = 0;
    for (int i = 0; i < code.length; i++) {
      hash = (hash * 31 + code.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return memberThemes[hash % memberThemes.length];
  }
}

/// 系统算法生成的确定性头像框组件（支持房主金冠与 8 款成员算法光环）
class AvatarFrame extends StatelessWidget {
  final String senderCode;
  final String nickname;
  final bool isHost;
  final double size;
  final bool isNight;

  const AvatarFrame({
    super.key,
    required this.senderCode,
    required this.nickname,
    this.isHost = false,
    this.size = 36,
    this.isNight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AvatarFrameTheme.fromCode(senderCode, isHost: isHost);
    final initial = nickname.isNotEmpty ? nickname.characters.first : '?';
    final framePadding = isHost ? 3.0 : 2.5;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // 外层不可自定义算法光环 / 头像框
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: theme.borderGradient,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.glowColor.withValues(alpha: isHost ? 0.45 : 0.25),
                blurRadius: isHost ? 6 : 4,
                spreadRadius: isHost ? 1.0 : 0.5,
              ),
            ],
          ),
          padding: EdgeInsets.all(framePadding),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNight ? const Color(0xFF1E1C24) : Colors.white,
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.bold,
                  color: isNight ? Colors.white : AppTheme.lightTextPrimary,
                ),
              ),
            ),
          ),
        ),

        // 房主顶部专属微型小标识
        if (isHost)
          Positioned(
            top: -3,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFD700),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66FFD700),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.star_rounded,
                size: 10,
                color: Color(0xFF7A4500),
              ),
            ),
          ),
      ],
    );
  }
}

