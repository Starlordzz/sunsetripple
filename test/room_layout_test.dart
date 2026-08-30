import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/session/room_session.dart';
import 'package:sunset_ripple/ui/pages/room_page.dart';
import 'package:sunset_ripple/ui/pages/session_stage.dart';

/// 这轮把房内 UI 整体放大过（对讲盘 212、头像 64、控制条图标 24、正文 +2~4pt），
/// 矮屏窄屏上很容易挤到溢出。这里在几种常见屏幕比例上各摆一次，
/// Flutter 的溢出会以 FlutterError 形式让测试直接失败。
void main() {
  // 依次是：窄屏千元机、主流直板机、大屏。
  const surfaces = <String, Size>{
    '360x640': Size(360, 640),
    '411x892': Size(411, 892),
    '430x932': Size(430, 932),
  };

  void useSurface(WidgetTester tester, Size surface) {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpRoom(
    WidgetTester tester, {
    required Size surface,
    required RoomMode mode,
    required bool isNight,
  }) async {
    useSurface(tester, surface);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomContent(
            session: RoomSession(
              audioIo: MockAudioIo(),
              selfNickname: '测试者',
              mode: mode,
            ),
            isNight: isNight,
            stage: 1.0,
            onLeave: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final entry in surfaces.entries) {
    testWidgets('${entry.key} WiFi 房内布局不溢出', (tester) async {
      await pumpRoom(
        tester,
        surface: entry.value,
        mode: RoomMode.wifiFullDuplex,
        isNight: false,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('通话中'), findsOneWidget);
    });

    testWidgets('${entry.key} 蓝牙房内布局不溢出', (tester) async {
      await pumpRoom(
        tester,
        surface: entry.value,
        mode: RoomMode.bluetoothPtt,
        isNight: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('按住说话'), findsOneWidget);
    });

    testWidgets('${entry.key} 首页整场（背景+标题+前景）不溢出', (tester) async {
      useSurface(tester, entry.value);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionStage(isNight: false, onToggleTheme: () {}),
        ),
      );
      // 首页 initState 会发起扫描，里面有 2 秒的 Future.delayed。
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
      expect(find.text('落日后残波'), findsOneWidget);
      expect(find.text('创建 WiFi 房'), findsOneWidget);
    });
  }
}
