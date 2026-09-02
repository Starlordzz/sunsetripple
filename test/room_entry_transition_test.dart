import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/ui/pages/session_stage.dart';

/// 进房转场的端到端验收：点「创建 WiFi 房」之后，首页那组 UI 要走干净，
/// 房间那组要到齐，中途每一帧都不许溢出；返回时再原路退回首页。
void main() {
  const audioChannel = MethodChannel('host.msknet.sunsetripple/audio');
  const audioEventsChannel = MethodChannel('host.msknet.sunsetripple/audio_events');

  setUp(() {
    // 单测里没有平台侧实现，把音频通道打桩掉，否则 MissingPluginException
    // 会盖住真正要看的布局问题。
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioChannel, (_) async => null);
    messenger.setMockMethodCallHandler(audioEventsChannel, (_) async => null);
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioChannel, null);
    messenger.setMockMethodCallHandler(audioEventsChannel, null);
  });

  testWidgets('创建房间：首页 UI 离场、背景留场、房间 UI 入场', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SessionStage(isNight: false, onToggleTheme: () {})),
    );
    // 首页 initState 会发起扫描，里面有 2 秒的 Future.delayed。
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('落日后残波'), findsOneWidget);
    expect(find.text('通话中'), findsNothing);

    // createRoom 里有真实的 socket 绑定，得让真事件循环跑一轮。
    await tester.runAsync(() async {
      await tester.tap(find.text('创建 WiFi 房'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    // 逐帧走完整段转场，任何一帧溢出都会在这里冒出来。
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: '转场第 ${i + 1} 帧溢出');
    }

    // 落位：首页那组走干净了，房间那组到齐了。
    expect(find.text('落日后残波'), findsNothing);
    expect(find.text('创建 WiFi 房'), findsNothing);
    expect(find.text('通话中'), findsOneWidget);
    expect(find.text('离开'), findsOneWidget);
    expect(find.textContaining('的 WiFi 房'), findsOneWidget);

    // 离开房间完成清理
    await tester.tap(find.text('离开'));
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  });

  testWidgets('离开房间：原路退回首页', (tester) async {
    tester.view.physicalSize = const Size(411, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SessionStage(isNight: false, onToggleTheme: () {})),
    );
    await tester.pump(const Duration(seconds: 3));

    await tester.runAsync(() async {
      await tester.tap(find.text('创建 WiFi 房'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('通话中'), findsOneWidget);

    // 退场清理
    await tester.tap(find.text('离开'));
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: '退场第 ${i + 1} 帧溢出');
    }

    expect(find.text('通话中'), findsNothing);
    expect(find.text('落日后残波'), findsOneWidget);
    expect(find.text('创建 WiFi 房'), findsOneWidget);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  });
}
