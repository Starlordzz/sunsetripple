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

  Finder findTitle() => find.byWidgetPredicate(
        (w) => w is Text && (w.data == '落日后残波' || w.data == 'SunsetRipple'),
      );
  Finder findCreateWifi() => find.byWidgetPredicate(
        (w) => w is Text && (w.data == '创建 WiFi 房' || w.data == 'Create WiFi Room'),
      );
  Finder findInCall() => find.byWidgetPredicate(
        (w) => w is Text && (w.data == '通话中' || w.data == 'In call'),
      );
  Finder findLeave() => find.byWidgetPredicate(
        (w) => w is Text && (w.data == '离开' || w.data == 'Leave'),
      );
  Finder findRoomTitle() => find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains('WiFi 房') == true || w.data?.contains('WiFi Room') == true),
      );

  testWidgets('创建房间：首页 UI 离场、背景留场、房间 UI 入场', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SessionStage(isNight: false, onToggleTheme: () {})),
    );
    // 首页 initState 会发起扫描，里面有 2 秒的 Future.delayed。
    await tester.pump(const Duration(seconds: 3));

    expect(findTitle(), findsWidgets);
    expect(findInCall(), findsNothing);

    // createRoom 里有真实的 socket 绑定，得让真事件循环跑一轮。
    await tester.runAsync(() async {
      await tester.tap(findCreateWifi());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    // 逐帧走完整段转场，任何一帧溢出都会在这里冒出来。
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: '转场第 ${i + 1} 帧溢出');
    }

    // 落位：首页那组走干净了，房间那组到齐了。
    expect(findTitle(), findsNothing);
    expect(findCreateWifi(), findsNothing);
    expect(findInCall(), findsOneWidget);
    expect(findLeave(), findsOneWidget);
    expect(findRoomTitle(), findsOneWidget);

    // 离开房间完成清理
    await tester.tap(findLeave());
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
      await tester.tap(findCreateWifi());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(findInCall(), findsOneWidget);

    // 退场清理
    await tester.tap(findLeave());
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: '退场第 ${i + 1} 帧溢出');
    }

    expect(findInCall(), findsNothing);
    expect(findTitle(), findsWidgets);
    expect(findCreateWifi(), findsOneWidget);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  });
}
