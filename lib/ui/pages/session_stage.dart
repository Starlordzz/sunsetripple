import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/audio/audio_io.dart';
import '../../core/platform/platform_audio_channel.dart';
import '../../core/session/room_session.dart';
import '../transitions/stage_choreography.dart';
import '../widgets/celestial_canvas.dart';
import 'home_page.dart';
import 'room_page.dart';
import 'diagnostics_sheet.dart';

/// 首页与房间共用的一张"舞台"。
///
/// 这里不做页面跳转：首页和房间是同一块画布上的两组前景，中间那层日轮/水波背景
/// 从头到尾都是同一个 [CelestialCanvas]，进房时只是被挪了位置、放大了尺寸。
/// 首页的输入框、房型卡、按钮、房间列表依次沉下去淡出，背景长高、天体上浮变大，
/// 房间的成员轨道、对讲盘、底部控制条再依次浮上来——三段重叠成一镜到底。
///
/// 编排表见 [StageChoreography]。
class SessionStage extends StatefulWidget {
  final bool isNight;
  final VoidCallback onToggleTheme;

  const SessionStage({
    super.key,
    required this.isNight,
    required this.onToggleTheme,
  });

  @override
  State<SessionStage> createState() => _SessionStageState();
}

class _SessionStageState extends State<SessionStage>
    with SingleTickerProviderStateMixin {
  // 背景在首页与房间两种形态下的几何参数，转场时在两者之间插值。
  static const double _homeCelestialY = 0.42;
  static const double _roomCelestialY = 0.38;
  static const double _homeCelestialRadius = 52;
  static const double _roomCelestialRadius = 70;
  static const double _homeWaterLine = 0.76;
  static const double _roomWaterLine = 0.72;

  // 头部高度按屏幕比例取，再夹在上下限之间：矮屏上不至于把房间 UI 挤到溢出，
  // 高屏上也不会让天空涨得没边。
  static double _homeHeaderFor(double screenHeight) =>
      (screenHeight * 0.30).clamp(196.0, 260.0);

  static double _roomHeaderFor(double screenHeight) =>
      (screenHeight * 0.38).clamp(224.0, 348.0);

  late final AnimationController _stage;
  late final AudioIo _audioIo;

  RoomSession? _session;
  String _roomName = "";

  @override
  void initState() {
    super.initState();
    // 音频通道挂在舞台上，首页与房间共用一个，进出房间不会重建。
    _audioIo = PlatformAudioChannel();
    _stage = AnimationController(
      vsync: this,
      duration: StageChoreography.enterDuration,
      reverseDuration: StageChoreography.exitDuration,
    );
  }

  @override
  void dispose() {
    _stage.dispose();
    super.dispose();
  }

  bool get _inRoom => _session != null;

  void _onEnterRoom(RoomSession session, String roomName) {
    setState(() {
      _session = session;
      _roomName = roomName;
    });
    _stage.forward(from: 0.0);
  }

  void _onLeaveRoom() {
    final session = _session;
    if (session == null) return;

    // 点了就走：退场动画立刻起，音频与 socket 的收尾在后台并行做。
    // 早先这里是 `await session.leave()` 再反演动画，等于让用户干等一次
    // socket 关闭，手感上像是按钮没反应。
    unawaited(session.leave());

    _stage.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _session = null;
        _roomName = "";
      });
    });
  }

  void _showDiagnostics() {
    final session = _session;
    if (session == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DiagnosticsSheet(
        isNight: widget.isNight,
        memberCount: session.members.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 在房间里时，系统返回键走的是退场动画，而不是直接弹出路由。
      canPop: !_inRoom,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inRoom) _onLeaveRoom();
      },
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _stage,
          builder: (context, _) => _buildScene(context, _stage.value),
        ),
      ),
    );
  }

  Widget _buildScene(BuildContext context, double stage) {
    final session = _session;
    final screenHeight = MediaQuery.of(context).size.height;
    final homeHeader = _homeHeaderFor(screenHeight);
    final roomHeader = _roomHeaderFor(screenHeight);

    // 背景形变走自己那一段区间，不跟着前景的进出走。
    final bg = StageChoreography.background.transform(stage);
    final headerHeight = lerpDouble(homeHeader, roomHeader, bg);

    return Stack(
      children: [
        // 1. 头部：共用背景 + 压在上面的标题与图标，整块随 headerHeight 一起长高。
        //    标题贴着这块的底边，天空长高时它自然跟着往下走。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: headerHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildBackground(
                    session, headerHeight, bg, homeHeader, roomHeader),
              ),
              ..._buildHomeHeaderOverlay(stage),
              if (session != null) ..._buildRoomHeaderOverlay(session, stage),
            ],
          ),
        ),

        // 2. 主体内容：首页与房间的前景叠在一起，各自淡出/淡入。
        Positioned(
          top: headerHeight,
          left: 0,
          right: 0,
          bottom: 0,
          child: Stack(
            children: [
              Offstage(
                offstage: stage >= 1.0,
                child: IgnorePointer(
                  ignoring: stage > 0.0,
                  child: HomeContent(
                    isNight: widget.isNight,
                    stage: stage,
                    audioIo: _audioIo,
                    onEnterRoom: _onEnterRoom,
                  ),
                ),
              ),
              if (session != null)
                IgnorePointer(
                  ignoring: stage < 1.0,
                  child: RoomContent(
                    session: session,
                    isNight: widget.isNight,
                    stage: stage,
                    onLeave: _onLeaveRoom,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackground(
    RoomSession? session,
    double headerHeight,
    double bg,
    double homeHeader,
    double roomHeader,
  ) {
    // 天体半径跟着画布一起缩，矮屏上日轮不会显得撑满整片天。
    final radius = lerpDouble(
      _homeCelestialRadius * (homeHeader / 260.0),
      _roomCelestialRadius * (roomHeader / 348.0),
      bg,
    );

    Widget canvasFor(double waveIntensity) => CelestialCanvas(
          isNight: widget.isNight,
          waveIntensity: waveIntensity,
          height: headerHeight,
          celestialCenterFactorY:
              lerpDouble(_homeCelestialY, _roomCelestialY, bg),
          celestialRadius: radius,
          waterLineFactor: lerpDouble(_homeWaterLine, _roomWaterLine, bg),
        );

    if (session == null) return canvasFor(0.0);

    // 进房之后水波跟着说话音量起伏。
    return StreamBuilder<double>(
      stream: session.waveStream,
      initialData: 0.0,
      builder: (context, snapshot) => canvasFor(snapshot.data ?? 0.0),
    );
  }

  List<Widget> _buildHomeHeaderOverlay(double stage) {
    // 标题比正文早一点走，页面像是从上往下被抽走的。
    final t = const Interval(0.0, 0.26, curve: Curves.easeInCubic)
        .transform(stage.clamp(0.0, 1.0));
    if (t >= 1.0) return const [];

    Widget fade(Widget child, {double drift = 24}) => Opacity(
          opacity: 1.0 - t,
          child: Transform.translate(offset: Offset(0, drift * t), child: child),
        );

    return [
      Positioned(
        top: 40,
        right: 8,
        child: fade(
          IconButton(
            tooltip: "切换昼夜主题",
            iconSize: 30,
            padding: const EdgeInsets.all(12),
            icon: Icon(
              widget.isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
              color: Colors.white,
            ),
            onPressed: widget.onToggleTheme,
          ),
          drift: -20,
        ),
      ),
      Positioned(
        bottom: 18,
        left: 28,
        right: 28,
        child: fade(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "落日后残波",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "夕阳已远，涟漪未散，犹诉未尽之言。",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildRoomHeaderOverlay(RoomSession session, double stage) {
    final t = const Interval(0.56, 0.92, curve: Curves.easeOutCubic)
        .transform(stage.clamp(0.0, 1.0));
    if (t <= 0.0) return const [];

    Widget rise(Widget child, {double from = 20}) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, from * (1.0 - t)),
            child: child,
          ),
        );

    return [
      Positioned(
        top: 40,
        left: 8,
        child: rise(
          IconButton(
            tooltip: "离开房间",
            iconSize: 30,
            padding: const EdgeInsets.all(12),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _onLeaveRoom,
          ),
          from: -16,
        ),
      ),
      Positioned(
        top: 40,
        right: 8,
        child: rise(
          IconButton(
            tooltip: "连接诊断",
            iconSize: 30,
            padding: const EdgeInsets.all(12),
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: _showDiagnostics,
          ),
          from: -16,
        ),
      ),
      Positioned(
        bottom: 22,
        left: 28,
        right: 28,
        child: rise(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _roomName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                session.isHost ? "我是房主 · 房间广播中" : "已加入房间 · 语音加密互通中",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

/// `ui.lerpDouble` 会返回可空值，转场里每帧都要用，这里收一个非空版本。
double lerpDouble(double a, double b, double t) => a + (b - a) * t;
