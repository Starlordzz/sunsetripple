import 'package:flutter/material.dart';
import '../../core/session/member.dart';
import '../../core/session/room_session.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_controls.dart';
import '../widgets/celestial_canvas.dart';
import '../widgets/member_orbit.dart';
import '../widgets/ptt_button.dart';
import 'diagnostics_sheet.dart';

/// Intercom Room Active Screen.
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
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // 1. Dynamic Canvas Header
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
                          Text(
                            widget.roomName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.session.isHost ? "我是房主 · 局域网广播中" : "已加入房间",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
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

            // 3. Central PTT Disc Button
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

            // 4. Audio Controls Bottom Bar
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

