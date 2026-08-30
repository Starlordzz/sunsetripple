import 'package:flutter/material.dart';
import '../../core/audio/audio_io.dart';
import '../../core/session/room_session.dart';
import '../../core/transport/lan_discovery.dart';
import '../theme/app_theme.dart';
import '../transitions/stage_choreography.dart';

/// 首页前景：昵称、房型、建房/扫描按钮、附近房间列表。
///
/// 头部的日轮背景与大标题不在这里——它们归 `SessionStage` 管，因为进房时那层
/// 背景要留在原地继续演。这里只负责"会离场的那些东西"：每一块都套了
/// [StageExitItem]，按 [stage] 依次下沉淡出。
class HomeContent extends StatefulWidget {
  final bool isNight;

  /// 整段进房转场的 0→1 进度。0 时是完整首页，0.4 之后这里已经空了。
  final double stage;

  final AudioIo audioIo;
  final void Function(RoomSession session, String roomName) onEnterRoom;

  const HomeContent({
    super.key,
    required this.isNight,
    required this.stage,
    required this.audioIo,
    required this.onEnterRoom,
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  final _nicknameController = TextEditingController(text: "探索者");
  final _lanDiscovery = LanRoomDiscovery();
  RoomMode _selectedMode = RoomMode.wifiFullDuplex;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
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
    final stage = widget.stage;
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;

    return SafeArea(
      top: false,
      child: Column(
        children: [
          const SizedBox(height: 18),

          // 1. 昵称输入
          StageExitItem(
            stage: stage,
            index: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8),
                    width: 1.2,
                  ),
                ),
                child: TextField(
                  controller: _nicknameController,
                  style: TextStyle(color: textPrimary, fontSize: 17),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    icon: Icon(Icons.person_outline, size: 24, color: textSecondary),
                    hintText: "请输入对讲昵称",
                    hintStyle: TextStyle(color: textSecondary, fontSize: 17),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // 2. 房型选择（WiFi 房 / 蓝牙房）
          StageExitItem(
            stage: stage,
            index: 1,
            child: Padding(
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
          ),

          const SizedBox(height: 18),

          // 3. 建房 + 扫描
          StageExitItem(
            stage: stage,
            index: 2,
            child: Padding(
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
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _selectedMode == RoomMode.wifiFullDuplex ? "创建 WiFi 房" : "创建蓝牙房",
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                              ),
                            )
                          : Icon(
                              Icons.radar,
                              size: 21,
                              color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                            ),
                      label: Text(
                        _isScanning ? "正在扫描" : "扫描房间",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                          width: 1.6,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),

          // 4. 房间列表标题
          StageExitItem(
            stage: stage,
            index: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "附近的对讲房间",
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_isScanning)
                    Text(
                      "正在探测...",
                      style: TextStyle(
                        color: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 5. 房间列表
          Expanded(
            child: StageExitItem(
              stage: stage,
              index: 4,
              child: StreamBuilder<List<DiscoveredRoom>>(
                stream: _lanDiscovery.roomsStream,
                initialData: _lanDiscovery.currentRooms,
                builder: (context, snapshot) {
                  final rooms = snapshot.data ?? [];
                  if (rooms.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          "未发现附近的房间\n点击上方「扫描房间」或同连热点/蓝牙即可自动发现",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textSecondary.withValues(alpha: 0.7),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    room.roomName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "房主: ${room.hostNickname} · ${room.memberCount}/6 台",
                                    style: TextStyle(color: textSecondary, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () => _onJoinRoom(room),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                              ),
                              child: const Text(
                                "加入",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _nickname {
    final text = _nicknameController.text.trim();
    return text.isEmpty ? "探索者" : text;
  }

  void _onCreateRoom() async {
    final nickname = _nickname;
    final roomName = _selectedMode == RoomMode.wifiFullDuplex
        ? "$nickname 的 WiFi 房"
        : "$nickname 的蓝牙房";

    final session = RoomSession(
      audioIo: widget.audioIo,
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

    if (mounted) widget.onEnterRoom(session, roomName);
  }

  void _onJoinRoom(DiscoveredRoom room) async {
    final session = RoomSession(
      audioIo: widget.audioIo,
      selfNickname: _nickname,
      mode: RoomMode.wifiFullDuplex,
    );
    await session.joinRoom();

    if (mounted) widget.onEnterRoom(session, room.roomName);
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
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : cardBg,
          borderRadius: BorderRadius.circular(18),
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
                Icon(icon, size: 20, color: isSelected ? activeColor : textSecondary),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? activeColor : textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
