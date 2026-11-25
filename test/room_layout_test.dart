import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/clock.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/join_request.dart';
import 'package:sunset_ripple/core/session/room_session.dart';
import 'package:sunset_ripple/l10n/app_strings.dart';
import 'package:sunset_ripple/ui/pages/diagnostics_sheet.dart';
import 'package:sunset_ripple/ui/pages/room_page.dart';
import 'package:sunset_ripple/ui/pages/session_stage.dart';
import 'package:sunset_ripple/ui/widgets/room_chat_sheet.dart';

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
            stage: const AlwaysStoppedAnimation(1.0),
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
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data == '通话中' || w.data == 'In call'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('${entry.key} 蓝牙房内布局不溢出', (tester) async {
      await pumpRoom(
        tester,
        surface: entry.value,
        mode: RoomMode.bluetoothPtt,
        isNight: true,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data == '按住说话' || w.data == 'Hold to talk'),
        ),
        findsOneWidget,
      );
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
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data == '落日后残波' || w.data == 'SunsetRipple'),
        ),
        findsWidgets,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data == '开始 Wi-Fi 畅聊' || w.data == 'Start Wi-Fi Chat'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('${entry.key} 聊天面板弹出、输入发送、长消息不溢出', (tester) async {
      useSurface(tester, entry.value);
      final session = RoomSession(
        audioIo: MockAudioIo(),
        selfNickname: '测试者',
      );
      await session.createRoom();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomChatSheet(
              session: session,
              isNight: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(RoomChatSheet), findsOneWidget);

      // 输入长文本并发送
      await tester.enterText(
        find.byType(TextField),
        '这是一条测试长消息，用于验证文字聊天在各种分辨率下的换行与自适应，绝不能出现 RenderFlex overflow！',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(session.chatMessages.length, 1);
      expect(find.textContaining('这是一条测试长消息'), findsOneWidget);

      await session.dispose();
    });
  }

  testWidgets('DiagnosticsSheet 展示 SessionMetrics 并可切换麦克风源且不溢出',
      (tester) async {
    useSurface(tester, const Size(360, 640));
    final clock = FakeClock(DateTime(2026, 9, 29, 12, 0, 0));
    final session = RoomSession(
      audioIo: MockAudioIo(),
      selfNickname: '房主',
      clock: clock,
    );
    await session.createRoom(startAudio: false);
    clock.advance(const Duration(seconds: 45));
    expect(session.metrics.uptimeSeconds, 45);

    bool? switchedTo;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosticsSheet(
            isNight: false,
            memberCount: session.members.length,
            packetLossRate: session.packetLossPercent,
            roundTripTimeMs: session.roundTripTimeMs,
            metrics: session.metrics,
            useBuiltinMic: session.useBuiltinMic,
            onToggleBuiltinMic: (v) {
              switchedTo = v;
              session.setUseBuiltinMic(v);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(Switch), findsOneWidget);

    await tester.ensureVisible(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(switchedTo, isTrue);
    expect(session.useBuiltinMic, isTrue);

    await session.dispose();
  });

  testWidgets('房主点击成员轨道可弹出更换房主确认弹窗', (tester) async {
    useSurface(tester, const Size(411, 892));
    final session = RoomSession(
      audioIo: MockAudioIo(),
      selfNickname: '房主',
    );
    await session.createRoom(startAudio: false);
    await session.handleIncomingFrame(
      Frame(
        type: FrameType.joinReq,
        senderId: 0,
        seq: 1,
        payload: JoinRequestPayload(
          nickname: '阿远#321',
          sessionToken: Uint8List.fromList(List.filled(16, 7)),
        ).encode(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomContent(
            session: session,
            isNight: false,
            stage: const AlwaysStoppedAnimation(1.0),
            onLeave: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('阿远'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == AppStrings.zh.transferHost ||
                w.data == AppStrings.en.transferHost),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == AppStrings.zh.cancel || w.data == AppStrings.en.cancel),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await session.dispose();
  });
}
