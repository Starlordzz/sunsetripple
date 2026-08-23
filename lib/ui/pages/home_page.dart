import 'package:flutter/material.dart';
import '../../core/audio/audio_io.dart';
import '../../core/session/room_session.dart';
import '../../core/transport/lan_discovery.dart';
import '../theme/app_theme.dart';
import '../widgets/celestial_canvas.dart';
import 'room_page.dart';

/// SunsetRipple Homepage.
class HomePage extends StatefulWidget {
  final bool isNight;
  final VoidCallback onToggleTheme;

  const HomePage({
    super.key,
    required this.isNight,
    required this.onToggleTheme,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _nicknameController = TextEditingController(text: "探索者");
  final _lanDiscovery = LanRoomDiscovery();
  final _audioIo = MockAudioIo();

  @override
  void initState() {
    super.initState();
    _lanDiscovery.startListening();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _lanDiscovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNight = widget.isNight;
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // 1. Celestial Header
            Stack(
              children: [
                CelestialCanvas(isNight: isNight),
                Positioned(
                  top: 48,
                  right: 16,
                  child: IconButton(
                    icon: Icon(
                      isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                      color: Colors.white,
                    ),
                    onPressed: widget.onToggleTheme,
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 28,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "落日后残波",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "夕阳已远，涟漪未散，犹诉未尽之言。",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 2. Nickname input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8),
                    width: 1.2,
                  ),
                ),
                child: TextField(
                  controller: _nicknameController,
                  style: TextStyle(color: textPrimary),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    icon: Icon(Icons.person_outline, color: textSecondary),
                    hintText: "请输入对讲昵称",
                    hintStyle: TextStyle(color: textSecondary),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 3. Action Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _onCreateRoom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetBurgundy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        elevation: 0,
                      ),
                      child: const Text("创建房间", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                        side: BorderSide(
                          color: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text("局域网搜房", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 4. Discovered Rooms List Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "附近局域网/热点房间",
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // 5. Discovered Rooms List
            Expanded(
              child: StreamBuilder<List<DiscoveredRoom>>(
                stream: _lanDiscovery.roomsStream,
                initialData: _lanDiscovery.currentRooms,
                builder: (context, snapshot) {
                  final rooms = snapshot.data ?? [];
                  if (rooms.isEmpty) {
                    return Center(
                      child: Text(
                        "未发现附近的局域网房间\n同 Wi-Fi 或热点下建房即可自动发现",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: textSecondary.withValues(alpha: 0.6), fontSize: 13),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  room.roomName,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "房主: ${room.hostNickname} · ${room.memberCount}/6 台",
                                  style: TextStyle(color: textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                            ElevatedButton(
                              onPressed: () => _onJoinRoom(room),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: const Text("加入"),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onCreateRoom() async {
    final nickname = _nicknameController.text.trim().isEmpty ? "探索者" : _nicknameController.text.trim();
    final session = RoomSession(
      audioIo: _audioIo,
      selfNickname: nickname,
    );
    await session.createRoom();

    _lanDiscovery.startAdvertising(
      roomId: "room_${DateTime.now().millisecondsSinceEpoch}",
      roomName: "$nickname 的落日房间",
      hostNickname: nickname,
      tcpPort: 8988,
      getMemberCount: () => session.members.length,
    );

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RoomPage(
            session: session,
            isNight: widget.isNight,
            roomName: "$nickname 的落日房间",
          ),
        ),
      );
    }
  }

  void _onJoinRoom(DiscoveredRoom room) async {
    final nickname = _nicknameController.text.trim().isEmpty ? "探索者" : _nicknameController.text.trim();
    final session = RoomSession(
      audioIo: _audioIo,
      selfNickname: nickname,
    );
    await session.joinRoom();

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RoomPage(
            session: session,
            isNight: widget.isNight,
            roomName: room.roomName,
          ),
        ),
      );
    }
  }
}

