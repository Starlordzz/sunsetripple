import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/ffi/native_core_ffi.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NativeCoreFfi.initialize();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const SunsetRippleApp());
}

/// Root Application Widget for SunsetRipple.
class SunsetRippleApp extends StatefulWidget {
  const SunsetRippleApp({super.key});

  @override
  State<SunsetRippleApp> createState() => _SunsetRippleAppState();
}

class _SunsetRippleAppState extends State<SunsetRippleApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.light) {
        _themeMode = ThemeMode.dark;
      } else if (_themeMode == ThemeMode.dark) {
        _themeMode = ThemeMode.light;
      } else {
        // From system to dark
        _themeMode = ThemeMode.dark;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '落日后残波 SunsetRipple',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          final isNight = _themeMode == ThemeMode.dark ||
              (_themeMode == ThemeMode.system &&
                  MediaQuery.of(context).platformBrightness == Brightness.dark);
          return HomePage(
            isNight: isNight,
            onToggleTheme: _toggleTheme,
          );
        },
      ),
    );
  }
}
