import 'package:flutter/material.dart';
import '../../core/audio/audio_io.dart';
import '../../core/platform/platform_audio_channel.dart';
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
  late AudioIo _audioIo;
  RoomMode _selectedMode = RoomMode.wifiFullDuplex;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _audioIo = PlatformAudioChannel();
    _startScan();
  }

  void _startScan() {
    setState(() => _isScanning = true);
    _lanDiscovery.startListening();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });
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
            // 1. Dynamic Celestial Header
            Stack(
              children: [
                CelestialCanvas(isNight: isNight),
                Positioned(
                  top: 48,
                  right: 16,
                  child: IconButton(
                    tooltip: "切换昼夜主题",
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

            const SizedBox(height: 16),

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

            const SizedBox(height: 12),

            // 3. Room Mode Selector (WiFi 房 vs 蓝牙房)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeSelectChip(
                      icon: Icons.wifi,
                      title: "WiFi 房",
                      subtitle: "同连WiFi/热点 · 畅聊",
                      isSelected: _selectedMode == RoomMode.wifiFullDuplex,
                      isNight: isNight,
                      onTap: () => setState(() => _selectedMode = RoomMode.wifiFullDuplex),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ModeSelectChip(
                      icon: Icons.bluetooth,
                      title: "蓝牙房",
                      subtitle: "近场免配对 · 按住对讲",
                      isSelected: _selectedMode == RoomMode.bluetoothPtt,
                      isNight: isNight,
                      onTap: () => setState(() => _selectedMode = RoomMode.bluetoothPtt),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. Action Buttons (创建房间 + 扫描搜房)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
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
                      child: Text(
                        _selectedMode == RoomMode.wifiFullDuplex ? "创建 WiFi 房" : "创建蓝牙房",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: OutlinedButton.icon(
                      onPressed: _isScanning ? null : _startScan,
                      icon: _isScanning
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                              ),
                            )
                          : Icon(
                              Icons.radar,
                              size: 18,
                              color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                            ),
                      label: Text(
                        _isScanning ? "正在扫描" : "扫描房间",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 5. Discovered Rooms List Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "附近的对讲房间",
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_isScanning)
                    Text(
                      "正在探测...",
                      style: TextStyle(
                        color: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // 6. Discovered Rooms List
            Expanded(
              child: StreamBuilder<List<DiscoveredRoom>>(
                stream: _lanDiscovery.roomsStream,
                initialData: _lanDiscovery.currentRooms,
                builder: (context, snapshot) {
                  final rooms = snapshot.data ?? [];
                  if (rooms.isEmpty) {
                    return Center(
                      child: Text(
                        "未发现附近的房间\n点击上方「扫描房间」或同连热点/蓝牙即可自动发现",
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
    final roomName = _selectedMode == RoomMode.wifiFullDuplex ? "$nickname 的 WiFi 房" : "$nickname 的蓝牙房";

    final session = RoomSession(
      audioIo: _audioIo,
      selfNickname: nickname,
      mode: _selectedMode,
    );
    await session.createRoom();

    _lanDiscovery.startAdvertising(
      roomId: "room_${DateTime.now().millisecondsSinceEpoch}",
      roomName: roomName,
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
            roomName: roomName,
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
      mode: RoomMode.wifiFullDuplex,
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

class _ModeSelectChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isNight;
  final VoidCallback onTap;

  const _ModeSelectChip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.isNight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetBurgundy;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeColor : (isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8)),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: isSelected ? activeColor : textSecondary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? activeColor : textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
