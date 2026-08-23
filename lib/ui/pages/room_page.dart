import 'package:flutter/material.dart';
import '../../core/session/member.dart';
import '../../core/session/room_session.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_controls.dart';
import '../widgets/celestial_canvas.dart';
import '../widgets/member_orbit.dart';
import '../widgets/ptt_button.dart';
import 'diagnostics_sheet.dart';

/// Full Feature Parity Intercom Room Screen (Full-Duplex & PTT).
class RoomPage extends StatefulWidget {
  final RoomSession session;
  final bool isNight;
  final String roomName;

  const RoomPage({
    super.key,
    required this.session,
    required this.isNight,
    this.roomName = "落日对讲房",
  });

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  bool _isSpeakerOn = true;

  @override
  Widget build(BuildContext context) {
    final isNight = widget.isNight;
    final isFullDuplex = widget.session.isFullDuplex;
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // 1. Dynamic Celestial Header
            StreamBuilder<double>(
              stream: widget.session.waveStream,
              initialData: 0.0,
              builder: (context, snapshot) {
                return Stack(
                  children: [
                    CelestialCanvas(
                      isNight: isNight,
                      waveIntensity: snapshot.data ?? 0.0,
                    ),
                    Positioned(
                      top: 48,
                      left: 16,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _onLeaveRoom,
                      ),
                    ),
                    Positioned(
                      top: 48,
                      right: 16,
                      child: IconButton(
                        icon: const Icon(Icons.info_outline, color: Colors.white),
                        onPressed: _showDiagnostics,
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.roomName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  isFullDuplex ? "全双工" : "PTT对讲",
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.session.isHost ? "我是房主 · 局域网广播搜房中" : "已加入房间 · 语音加密互通中",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            // 2. Member Orbit Track
            StreamBuilder<List<Member>>(
              stream: widget.session.membersStream,
              initialData: widget.session.members,
              builder: (context, snapshot) {
                final members = snapshot.data ?? [];
                return MemberOrbit(
                  members: members,
                  isNight: isNight,
                );
              },
            ),

            const Spacer(),

            // 3. Central Interactive Element
            if (isFullDuplex)
              // Full-Duplex Mode: Real-time Audio Wave Glow Indicator
              StreamBuilder<double>(
                stream: widget.session.waveStream,
                initialData: 0.0,
                builder: (context, snapshot) {
                  final wave = snapshot.data ?? 0.0;
                  final activeColor = isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetBurgundy;
                  final isSpeaking = wave > 0.05 && !widget.session.isMuted;

                  return Container(
                    width: 170,
                    height: 170,
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
                            size: 48,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.session.isMuted
                                ? "麦克风已静音"
                                : (isSpeaking ? "正在实时拾音" : "全双工通话中"),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
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
            else
              // Bluetooth PTT Mode: Push-To-Talk Disc Button
              PttButton(
                isNight: isNight,
                isPressed: widget.session.isPttPressed,
                onStateChanged: (pressed) {
                  setState(() {
                    widget.session.setPtt(pressed);
                  });
                },
              ),

            const Spacer(),

            // 4. Audio Controls Bottom Bar (Mute, Speaker/Earpiece, Leave)
            AudioControlsBar(
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
              onLeave: _onLeaveRoom,
            ),
          ],
        ),
      ),
    );
  }

  void _onLeaveRoom() async {
    await widget.session.leave();
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
