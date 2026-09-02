import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunset_ripple/main.dart';

void main() {
  const audioChannel = MethodChannel('host.msknet.sunsetripple/audio');
  const audioEventsChannel = MethodChannel('host.msknet.sunsetripple/audio_events');
  const wifiDirectChannel = MethodChannel('host.msknet.sunsetripple/wifi_direct');
  const wifiDirectEventsChannel = MethodChannel('host.msknet.sunsetripple/wifi_direct_events');

  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioChannel, (_) async => null);
    messenger.setMockMethodCallHandler(audioEventsChannel, (_) async => null);
    messenger.setMockMethodCallHandler(wifiDirectChannel, (call) async {
      if (call.method == 'isSupported') return true;
      if (call.method == 'isEnabled') return true;
      if (call.method == 'discoverPeers') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(wifiDirectEventsChannel, (_) async => null);
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioChannel, null);
    messenger.setMockMethodCallHandler(audioEventsChannel, null);
    messenger.setMockMethodCallHandler(wifiDirectChannel, null);
    messenger.setMockMethodCallHandler(wifiDirectEventsChannel, null);
  });

  // 首页 initState 会发起一次扫描，里面有 2 秒的 Future.delayed；
  // 不把假时钟推过去，测试结束时会因为「还有未完成的 Timer」而失败。
  const scanSettle = Duration(seconds: 3);

  testWidgets('首页能正常渲染并显示输入框与建房按钮', (WidgetTester tester) async {
    await tester.pumpWidget(const SunsetRippleApp());
    await tester.pump(scanSettle);

    // 能找到标题（SunsetRipple 或 落日后残波）与输入框
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data == '落日后残波' || w.data == 'SunsetRipple'),
      ),
      findsWidgets,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == '创建 WiFi 房' || w.data == 'Create WiFi Room'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('可以在 WiFi 房与蓝牙房之间切换', (WidgetTester tester) async {
    await tester.pumpWidget(const SunsetRippleApp());
    await tester.pump(scanSettle);

    final bluetoothChip = find.byWidgetPredicate(
      (w) => w is Text && (w.data == '蓝牙房' || w.data == 'Bluetooth room'),
    );
    expect(bluetoothChip, findsOneWidget);

    await tester.tap(bluetoothChip);
    // 切换房型会重新扫描，同样有 2 秒延时。
    await tester.pump();
    await tester.pump(scanSettle);

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == '创建蓝牙房' || w.data == 'Create Bluetooth Room'),
      ),
      findsOneWidget,
    );
  });
}
