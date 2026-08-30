import 'package:flutter/material.dart';
import '../../core/session/member.dart';
import '../../core/session/room_session.dart';
import '../theme/app_theme.dart';
import '../transitions/stage_choreography.dart';
import '../widgets/audio_controls.dart';
import '../widgets/member_orbit.dart';
import '../widgets/ptt_button.dart';

/// 房间前景：成员轨道、中央对讲盘、底部音频控制条。
///
/// 房名、状态行与返回/诊断按钮压在背景上，由 `SessionStage` 绘制。这里每一块都
/// 套了 [StageEnterItem]，按 [stage] 依次从下方浮上来。
class RoomContent extends StatefulWidget {
  final RoomSession session;
  final bool isNight;

  /// 整段进房转场的 0→1 进度。0.52 之前这里还是空的。
  /// 传的是动画本身而不是当帧的值——每块各自听，子树不用按帧重建。
  final Animation<double> stage;

  final VoidCallback onLeave;

  const RoomContent({
    super.key,
    required this.session,
    required this.isNight,
    required this.stage,
    required this.onLeave,
  });

  @override
  State<RoomContent> createState() => _RoomContentState();
}

class _RoomContentState extends State<RoomContent> {
  bool _isSpeakerOn = true;

  @override
  Widget build(BuildContext context) {
    final isNight = widget.isNight;
    final stage = widget.stage;
    // 对讲盘按屏幕高度取，矮屏上收一点，免得挤爆下面的控制条。
    final discSize =
        (MediaQuery.of(context).size.height * 0.24).clamp(148.0, 212.0);

    return SafeArea(
      top: false,
      child: Column(
        children: [
          const SizedBox(height: 18),

          // 1. 成员轨道
          StageEnterItem(
            stage: stage,
            index: 0,
            child: StreamBuilder<List<Member>>(
              stream: widget.session.membersStream,
              initialData: widget.session.members,
              builder: (context, snapshot) {
                return MemberOrbit(
                  members: snapshot.data ?? [],
                  isNight: isNight,
                );
              },
            ),
          ),

          const Spacer(),

          // 2. 中央对讲盘：WiFi 房是实时音浪，蓝牙房是按住说话
          StageEnterItem(
            stage: stage,
            index: 1,
            rise: 40,
            fromScale: 0.84,
            child: widget.session.isFullDuplex
                ? _buildDuplexDisc(isNight, discSize)
                : PttButton(
                    isNight: isNight,
                    size: discSize,
                    isPressed: widget.session.isPttPressed,
                    onStateChanged: (pressed) {
                      setState(() {
                        widget.session.setPtt(pressed);
                      });
                    },
                  ),
          ),

          const Spacer(),

          // 3. 底部控制条（静音 / 扬声器 / 离开）
          StageEnterItem(
            stage: stage,
            index: 2,
            rise: 36,
            child: AudioControlsBar(
              isNight: isNight,
              isMuted: widget.session.isMuted,
              isSpeakerOn: _isSpeakerOn,
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
              onLeave: widget.onLeave,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDuplexDisc(bool isNight, double size) {
    return StreamBuilder<double>(
      stream: widget.session.waveStream,
      initialData: 0.0,
      builder: (context, snapshot) {
        final wave = snapshot.data ?? 0.0;
        final activeColor = isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetBurgundy;
        final isSpeaking = wave > 0.05 && !widget.session.isMuted;

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: activeColor,
            boxShadow: [
              BoxShadow(
                color: activeColor.withValues(alpha: 0.35 + wave * 0.4),
                blurRadius: 24 + wave * 30,
                spreadRadius: 4 + wave * 14,
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.session.isMuted
                      ? Icons.mic_off
                      : (isSpeaking ? Icons.graphic_eq : Icons.mic),
                  size: size * 0.28,
                  color: Colors.white,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.session.isMuted
                      ? "麦克风已静音"
                      : (isSpeaking ? "正在说话..." : "通话中"),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (size * 0.085).clamp(15.0, 18.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
