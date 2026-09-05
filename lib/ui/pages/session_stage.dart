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
import 'about_page.dart';
import '../theme/app_theme.dart';
import '../widgets/room_chat_sheet.dart';
import '../../l10n/app_strings.dart';

/// 首页与房间共用的一张"舞台"。
///
/// 这里不做页面跳转：首页和房间是同一块画布上的两组前景，中间那层日轮/水波背景
/// 从头到尾都是同一个 [CelestialCanvas]，进房时只是被挪了位置、放大了尺寸。
/// 首页的输入框、房型卡、按钮、房间列表依次沉下去淡出，背景长高、天体上浮变大，
/// 房间的成员轨道、对讲盘、底部控制条再依次浮上来——三段重叠成一镜到底。
///
/// 编排表见 [StageChoreography]。
///
/// 为了不掉帧，这里对"每帧要动的东西"抠得比较紧：
///   - 两组前景的顶边是**固定**的（首页贴首页头图高度，房间贴房间头图高度），
///     每帧变化的只有头部那一层。前景一旦按帧改 top，整棵树每帧都要重新布局。
///   - 前景的进出场由 [StageExitItem]/[StageEnterItem] 各自听动画，
///     子树只建一次，见那两个类的说明。
///   - 麦克风推迟到动画跑完再开，原因见 [RoomSession.startAudio]。
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

    // 建房时特意没开麦（见 HomeContent._onCreateRoom）：AudioRecord/AudioTrack
    // 的构造和前台服务启动都压在 Android 主线程上，一次上百毫秒，
    // 塞进转场里必然掉帧。等动画落位再开。
    _stage.forward(from: 0.0).whenComplete(() {
      if (mounted) session.startAudio();
    });
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

  void _showChatSheet(RoomSession session) {
    session.markChatRead();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RoomChatSheet(
        session: session,
        isNight: widget.isNight,
      ),
    ).then((_) {
      session.markChatRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final screenHeight = MediaQuery.of(context).size.height;
    final homeHeader = _homeHeaderFor(screenHeight);
    final roomHeader = _roomHeaderFor(screenHeight);

    return PopScope(
      // 在房间里时，系统返回键走的是退场动画，而不是直接弹出路由。
      canPop: !_inRoom,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inRoom) _onLeaveRoom();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // 1. 首页前景。顶边钉死在首页头图高度上，整段转场不重新布局。
            Positioned(
              top: homeHeader,
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _stage,
                child: HomeContent(
                  isNight: widget.isNight,
                  stage: _stage,
                  audioIo: _audioIo,
                  onEnterRoom: _onEnterRoom,
                ),
                builder: (context, child) => Offstage(
                  offstage: _stage.value >= 1.0,
                  child: IgnorePointer(
                    ignoring: _stage.value > 0.0,
                    child: child,
                  ),
                ),
              ),
            ),

            // 2. 房间前景。顶边钉死在房间头图高度上，同样不按帧重新布局。
            if (session != null)
              Positioned(
                top: roomHeader,
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: _stage,
                  child: RoomContent(
                    session: session,
                    isNight: widget.isNight,
                    stage: _stage,
                    onLeave: _onLeaveRoom,
                  ),
                  builder: (context, child) => IgnorePointer(
                    ignoring: _stage.value < 1.0,
                    child: child,
                  ),
                ),
              ),

            // 3. 头部盖在最上面：天空长高时会顺势把正在离场的首页内容盖掉，
            //    这是整段转场里唯一每帧重新布局的一层，只有一个 CustomPaint。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _stage,
                builder: (context, _) =>
                    _buildHeaderLayer(session, homeHeader, roomHeader),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderLayer(
      RoomSession? session, double homeHeader, double roomHeader) {
    final stage = _stage.value;
    // 背景形变走自己那一段区间，不跟着前景的进出走。
    final bg = StageChoreography.background.transform(stage);
    final headerHeight = lerpDouble(homeHeader, roomHeader, bg);

    return SizedBox(
      height: headerHeight,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: _buildBackground(
                  session, headerHeight, bg, homeHeader, roomHeader),
            ),
          ),
          ..._buildHomeHeaderOverlay(stage),
          if (session != null) ..._buildRoomHeaderOverlay(session, stage),
        ],
      ),
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
    final s = AppStrings.of(context);
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: s.tooltipInfoAndUpdates,
                iconSize: 28,
                padding: const EdgeInsets.all(10),
                icon: const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AboutPage(isNight: widget.isNight),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: s.tooltipToggleTheme,
                iconSize: 28,
                padding: const EdgeInsets.all(10),
                icon: Icon(
                  widget.isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  color: Colors.white,
                ),
                onPressed: widget.onToggleTheme,
              ),
            ],
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
              Text(
                s.appName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.appSubheading,
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
    final s = AppStrings.of(context);
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
            tooltip: s.tooltipLeaveRoom,
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<int>(
                stream: session.unreadChatStream,
                initialData: session.unreadChatCount,
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  return Semantics(
                    label: s.chatButtonLabel,
                    hint: unread > 0 ? s.chatUnreadBadge(unread) : null,
                    button: true,
                    child: IconButton(
                      tooltip: s.tooltipChat,
                      iconSize: 28,
                      padding: const EdgeInsets.all(12),
                      icon: Badge(
                        isLabelVisible: unread > 0,
                        label: Text(
                          '$unread',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        backgroundColor: widget.isNight
                            ? AppTheme.darkLeaveRosePink
                            : AppTheme.sunsetCoral,
                        child: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: () => _showChatSheet(session),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: s.tooltipDiagnostics,
                iconSize: 28,
                padding: const EdgeInsets.all(12),
                icon: const Icon(Icons.info_outline, color: Colors.white),
                onPressed: _showDiagnostics,
              ),
            ],
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
                session.isHost ? s.hostBroadcastingStatus : s.memberConnectedStatus,
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
