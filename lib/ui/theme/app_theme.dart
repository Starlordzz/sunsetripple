import 'package:flutter/material.dart';

/// SunsetRipple Color Palette & Theme Definitions.
class AppTheme {
  // Light (Sunset Warm)
  static const Color sunsetCoral = Color(0xFFC97C66);
  static const Color sunsetBurgundy = Color(0xFF9B4A52);
  static const Color sunsetDeepPlum = Color(0xFF392832);
  static const Color sunWarmYellow = Color(0xFFF3DCAA);
  static const Color lightBg = Color(0xFFF4F1EC);
  static const Color lightCardBg = Color(0xFFFCFAF7);
  static const Color lightTextPrimary = Color(0xFF2A2225);
  static const Color lightTextSecondary = Color(0xFF6E625E);
  static const Color lightLeaveAccent = Color(0xFFFF9E90);

  // Dark (Moonlit Deep Ocean)
  static const Color nightSkyBlue = Color(0xFF3C5A8C);
  static const Color nightDeepOcean = Color(0xFF24395F);
  static const Color nightAbyss = Color(0xFF101A2E);
  static const Color moonSilverWhite = Color(0xFFE9EEF7);
  static const Color darkBg = Color(0xFF0E1626);
  static const Color darkCardBg = Color(0xFF182437);
  static const Color darkTextPrimary = Color(0xFFE4EBF4);
  static const Color darkTextSecondary = Color(0xFF8FA2BC);
  static const Color darkLeaveRosePink = Color(0xFFFF7B92); // High-contrast (>7.5:1)

  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: sunsetBurgundy,
      colorScheme: const ColorScheme.light(
        primary: sunsetBurgundy,
        secondary: sunsetCoral,
        surface: lightCardBg,
      ),
      fontFamily: 'sans-serif',
    );
  }

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: nightSkyBlue,
      colorScheme: const ColorScheme.dark(
        primary: nightSkyBlue,
        secondary: nightDeepOcean,
        surface: darkCardBg,
      ),
      fontFamily: 'sans-serif',
    );
  }
}

