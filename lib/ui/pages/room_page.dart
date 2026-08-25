import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/session/member.dart';
import '../../core/session/room_session.dart';
import '../../core/transport/room_transport.dart';
import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_controls.dart';
import '../widgets/celestial_canvas.dart';
import '../widgets/member_orbit.dart';
import '../widgets/ptt_button.dart';
import 'diagnostics_sheet.dart';

/// SunsetRipple Intercom Room Screen.
class RoomPage extends StatefulWidget {
  final RoomSession session;
  final RoomTransport transport;
  final bool isNight;
  final String roomName;

  /// 建房/连接是否成功。
  ///
  /// 页面是点击瞬间就推出去的（这样转场动画能立刻开始），建房本身在转场期间
  /// 并发进行。失败时不能把用户丢在一个根本没建起来的房间里，所以这里等结果，
  /// 失败就退回首页——具体原因由 [AppLog] 弹出来。
  final Future<bool> ready;

  const RoomPage({
    super.key,
    required this.session,
    required this.transport,
    required this.isNight,
    required this.ready,
    this.roomName = "落日对讲房",
  });

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  bool _isSpeakerOn = true;
  bool _useBuiltinMic = false;
  StreamSubscription<LogEntry>? _logSubscription;

  /// 页面提前销毁时用来摘掉转场动画的监听。
  VoidCallback? _transitionListener;

  @override
  void initState() {
    super.initState();
    _useBuiltinMic = widget.session.useBuiltinMic;
    _logSubscription = AppLog.userVisibleStream.listen((entry) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(entry.displayMessage),
          backgroundColor: entry.level == LogLevel.error
              ? AppTheme.sunsetBurgundy
              : AppTheme.sunsetCoral,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 70, left: 16, right: 16),
        ),
      );
    });

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // ready 来自一个未 await 的 Future，万一它抛出来这里要兜住，
    // 否则会变成一条无人处理的异步异常。
    final ok = await widget.ready.catchError((Object e) {
      AppLog.error('房间', '建立房间时发生未预期的错误', e);
      return false;
    });
    if (!mounted) return;

    if (!ok) {
      // 失败原因已经通过 AppLog 弹给用户了，这里只负责别把人留在空房间里。
      Navigator.of(context).maybePop();
      return;
    }

    // 等转场动画跑完再开麦。AudioRecord/AudioTrack 的初始化在 Android 主线程上
    // 要上百毫秒，压在动画里会直接把动画拖掉帧。
    await _waitForTransition();
    if (!mounted) return;
    await widget.session.startAudio();
  }

  Future<void> _waitForTransition() {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeStatusListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    }

    animation.addStatusListener(listener);
    _transitionListener = () => animation.removeStatusListener(listener);
    return completer.future;
  }

  @override
  void dispose() {
    _transitionListener?.call();
    _transitionListener = null;
    _logSubscription?.cancel();
    super.dispose();
  }

  void _onTapMember(Member member) {
    if (!widget.session.isHost) return;
    if (member.memberId == widget.session.selfMemberId) return;

    // 蓝牙房的 PSM 由系统分配、经广播发布，换房主要走一整套重新广播 +
    // 全员重新扫描的流程，一期不做。这里直接拦掉，不给半成品入口。
    if (!widget.transport.supportsHostTransfer) {
      AppLog.warn('房间', '蓝牙房暂不支持房主转移');
      return;
    }

    final s = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isNight ? const Color(0xFF1E2638) : Colors.white,
        title: Text(
          s.transferHost,
          style: TextStyle(
            color: widget.isNight ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          s.transferHostConfirm(member.nickname),
          style: TextStyle(
            color: widget.isNight ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.sunsetCoral,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.session.transferHost(member.memberId);
              if (mounted) setState(() {});
            },
            child: Text(s.confirm),
          ),
        ],
      ),
    );
  }

  void _showHostTransferSheet() {
    if (!widget.session.isHost) return;
    if (!widget.transport.supportsHostTransfer) {
      AppLog.warn('房间', '蓝牙房暂不支持房主转移');
      return;
    }
    final s = AppStrings.of(context);
    final isNight = widget.isNight;
    final otherMembers = widget.session.members
        .where((m) => m.memberId != widget.session.selfMemberId)
        .toList();

    if (otherMembers.isEmpty) {
      AppLog.info('房间', '房内暂无其他成员可转让');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: isNight ? const Color(0xFF1E2638) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s.transferHost,
                    style: TextStyle(
                      color: isNight ? Colors.white : Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: isNight ? Colors.white70 : Colors.black54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...otherMembers.map((member) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.sunsetCoral.withValues(alpha: 0.2),
                      child: Text(
                        member.nickname.characters.take(1).toString().toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.sunsetCoral,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      member.nickname,
                      style: TextStyle(
                        color: isNight ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'ID: ${member.memberId}',
                      style: TextStyle(
                        color: isNight ? Colors.white54 : Colors.black45,
                        fontSize: 12,
                      ),
                    ),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.sunsetCoral,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _onTapMember(member);
                      },
                      child: Text(s.transferHost, style: const TextStyle(fontSize: 13)),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isNight = widget.isNight;
    final isFullDuplex = widget.session.isFullDuplex;

    return Scaffold(
      body: Column(
        children: [
          // 1. Compact Header with Celestial Canvas (Height 140)
          StreamBuilder<double>(
            stream: widget.session.waveStream,
            initialData: 0.0,
            builder: (context, snapshot) {
              return Stack(
                children: [
                  CelestialCanvas(
                    isNight: isNight,
                    waveIntensity: snapshot.data ?? 0.0,
                    height: 140,
                  ),
                  Positioned(
                    top: 40,
                    left: 12,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: _onLeaveRoom,
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 12,
                    child: IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.white, size: 22),
                      onPressed: _showDiagnostics,
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 20,
                    right: 20,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.roomName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.session.isHost
                                    ? "${s.hostTag} · ${s.roomOnlineCount(widget.session.members.length)}"
                                    : "${s.roomConnected} · ${s.roomOnlineCount(widget.session.members.length)}",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.session.isHost &&
                                widget.transport.supportsHostTransfer &&
                                widget.session.members.length > 1) ...[
                              GestureDetector(
                                onTap: _showHostTransferSheet,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF8A2387), Color(0xFFE94057)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFE94057).withValues(alpha: 0.4),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        s.transferHost,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                isFullDuplex ? s.fullDuplex : s.pttMode,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 10),

          // 2. Member Orbit Track (Height 75)
          StreamBuilder<List<Member>>(
            stream: widget.session.membersStream,
            initialData: widget.session.members,
            builder: (context, snapshot) {
              final members = snapshot.data ?? [];
              return MemberOrbit(
                members: members,
                isNight: isNight,
                onTapMember: _onTapMember,
              );
            },
          ),

          // 3. Central Interactive Element (Flexible, never overflows!)
          Expanded(
            child: Center(
              child: isFullDuplex
                  ? StreamBuilder<double>(
                      stream: widget.session.waveStream,
                      initialData: 0.0,
                      builder: (context, snapshot) {
                        final wave = snapshot.data ?? 0.0;
                        final activeColor = isNight
                            ? AppTheme.nightSkyBlue
                            : AppTheme.sunsetBurgundy;
                        final isSpeaking = wave > 0.05 && !widget.session.isMuted;

                        return Container(
                          width: 156,
                          height: 156,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: activeColor,
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.35 + wave * 0.4),
                                blurRadius: 22 + wave * 26,
                                spreadRadius: 4 + wave * 12,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.session.isMuted
                                      ? Icons.mic_off_rounded
                                      : (isSpeaking
                                          ? Icons.graphic_eq_rounded
                                          : Icons.mic_rounded),
                                  size: 44,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.session.isMuted
                                      ? s.muted
                                      : (isSpeaking ? s.speaking : s.roomConnected),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  : PttButton(
                      isNight: isNight,
                      isPressed: widget.session.isPttPressed,
                      onStateChanged: (pressed) {
                        setState(() {
                          widget.session.setPtt(pressed);
                        });
                      },
                    ),
            ),
          ),

          // 4. Circular Audio Controls Bottom Bar
          AudioControlsBar(
            isNight: isNight,
            isMuted: widget.session.isMuted,
            isSpeakerOn: _isSpeakerOn,
            useBuiltinMic: _useBuiltinMic,
            onToggleMute: () {
              setState(() {
                widget.session.toggleMute();
              });
            },
            onToggleSpeaker: () {
              setState(() {
                _isSpeakerOn = !_isSpeakerOn;
                widget.session.setSpeakerphone(_isSpeakerOn);
              });
            },
            onToggleMicSource: () {
              setState(() {
                _useBuiltinMic = !_useBuiltinMic;
                widget.session.setUseBuiltinMic(_useBuiltinMic);
              });
            },
            onLeave: _onLeaveRoom,
          ),
        ],
      ),
    );
  }

  void _onLeaveRoom() async {
    await widget.session.leave();
    await widget.transport.stop();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showDiagnostics() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DiagnosticsSheet(
        isNight: widget.isNight,
        memberCount: widget.session.members.length,
      ),
    );
  }
}
