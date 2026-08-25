import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/audio/audio_io.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/platform/platform_audio_channel.dart';
import '../../core/session/room_session.dart';
import '../../core/transport/ble_l2cap_transport.dart';
import '../../core/transport/lan_discovery.dart';
import '../../core/transport/lan_transport.dart';
import '../../core/transport/room_transport.dart';
import '../../core/update/update_service.dart';
import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../transitions/room_entry_reveal_route.dart';
import '../widgets/celestial_canvas.dart';
import 'about_page.dart';
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
  static String _generateDefaultNickname() {
    final hex = Random().nextInt(0xFFFF + 1).toRadixString(16).toUpperCase().padLeft(4, '0');
    return '探索者_$hex';
  }

  late final String _defaultNickname = _generateDefaultNickname();
  late final _nicknameController = TextEditingController(text: _defaultNickname);
  final _lanDiscovery = LanRoomDiscovery();

  /// 蓝牙的原生插件是引擎级单例，Dart 侧整页只能持有一个实例，
  /// 否则两个对象会抢同一条 EventChannel，互相把对方的连接关掉。
  final _ble = BleL2capTransport();

  late AudioIo _audioIo;
  RoomMode _selectedMode = RoomMode.wifiFullDuplex;
  bool _isScanning = false;
  StreamSubscription<LogEntry>? _logSubscription;

  /// 进房动画要从「创建房间」按钮自身的形状撑开，所以得拿到它的屏幕矩形。
  final _createButtonKey = GlobalKey();

  /// 「创建房间」与列表「加入」按钮各自的圆角，转场起点形状要和它们一致。
  static const double _createButtonRadius = 26.0;
  static const double _joinButtonRadius = 20.0;

  /// 控件在全局坐标下的矩形；拿不到（还没布局）时返回 null，转场会退回屏幕中心。
  RevealOrigin? _originOf(GlobalKey key, double borderRadius) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return RevealOrigin(box.localToGlobal(Offset.zero) & box.size, borderRadius);
  }

  @override
  void initState() {
    super.initState();
    _audioIo = PlatformAudioChannel();
    // 任何 warn/error 都直接弹到用户面前，不再只写日志。
    _logSubscription = AppLog.userVisibleStream.listen(_showLogEntry);
    _startScan();
  }

  void _showLogEntry(LogEntry entry) {
    if (!mounted) return;
    // 房间页压在上面时由它负责提示，否则同一条错误会弹两次。
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
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
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    // 两种房型的发现机制不同：WiFi 房靠 UDP 广播，蓝牙房靠 BLE 扫描。
    // 同时开着既费电又互相干扰，所以按当前选择只开一个。
    if (_selectedMode == RoomMode.wifiFullDuplex) {
      await _ble.stopScan();
      await _lanDiscovery.startListening();
    } else {
      await _lanDiscovery.stop();
      await _ble.startScan();
    }

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  void _onModeChanged(RoomMode mode) {
    if (mode == _selectedMode) return;
    setState(() => _selectedMode = mode);
    _startScan();
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _nicknameController.dispose();
    _lanDiscovery.dispose();
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isNight = widget.isNight;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // 1. Dynamic Celestial Header
            Stack(
              children: [
                CelestialCanvas(isNight: isNight, height: 230),
                Positioned(
                  top: 48,
                  right: 16,
                  child: IconButton(
                    tooltip: s.themeDescription(isNight ? s.themeDark : s.themeLight),
                    icon: Icon(
                      isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                      color: Colors.white,
                    ),
                    onPressed: widget.onToggleTheme,
                  ),
                ),
                Positioned(
                  bottom: 18,
                  left: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.appName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.tagline,
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

            const SizedBox(height: 14),

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
                    hintText: s.nicknamePlaceholder,
                    hintStyle: TextStyle(color: textSecondary),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 3. Room Mode Selector (WiFi 房 vs 蓝牙房)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ModeSelectChip(
                        icon: Icons.wifi,
                        title: s.wifiDirect,
                        subtitle: s.wifiDescription,
                        isSelected: _selectedMode == RoomMode.wifiFullDuplex,
                        isNight: isNight,
                        onTap: () => _onModeChanged(RoomMode.wifiFullDuplex),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ModeSelectChip(
                        icon: Icons.bluetooth,
                        title: s.bluetoothRoom,
                        subtitle: s.bluetoothDescription,
                        isSelected: _selectedMode == RoomMode.bluetoothPtt,
                        isNight: isNight,
                        onTap: () => _onModeChanged(RoomMode.bluetoothPtt),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 4. Primary Action: Create Room（居中等宽胶囊，蓝牙房与 WiFi 房尺寸完全一致）
            Center(
              child: SizedBox(
                width: 220,
                height: 52,
                child: ElevatedButton(
                  key: _createButtonKey,
                  onPressed: () => _onCreateRoom(
                    _originOf(_createButtonKey, _createButtonRadius),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetBurgundy,
                    foregroundColor: Colors.white,
                    elevation: 1.5,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _selectedMode == RoomMode.wifiFullDuplex
                          ? s.createWifiRoom
                          : s.createBleRoom,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 5. Discovered Rooms Section Header with inline Scan / Refresh Action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.radar_rounded,
                        size: 16,
                        color: textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedMode == RoomMode.wifiFullDuplex
                            ? (s.isEn ? "Nearby WiFi Rooms" : "附近的 WiFi 房")
                            : (s.isEn ? "Nearby Bluetooth Rooms" : "附近的蓝牙房"),
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: _isScanning ? null : _startScan,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isScanning)
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                              ),
                            )
                          else
                            Icon(
                              Icons.refresh_rounded,
                              size: 15,
                              color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            _isScanning ? s.scanning : s.scanAgain,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // 6. Discovered Rooms List
            Expanded(
              child: _selectedMode == RoomMode.wifiFullDuplex
                  ? _buildLanRoomList(isNight, cardBg, textPrimary, textSecondary, s)
                  : _buildBleRoomList(isNight, cardBg, textPrimary, textSecondary, s),
            ),

            // 7. Footer: About & Update Link
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => AboutPage(isNight: widget.isNight),
                    ),
                  );
                },
                child: Text(
                  "v${UpdateService.currentVersion} · ${s.aboutTitle}",
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanRoomList(
    bool isNight,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    AppStrings s,
  ) {
    return StreamBuilder<List<DiscoveredRoom>>(
      stream: _lanDiscovery.roomsStream,
      initialData: _lanDiscovery.currentRooms,
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? [];
        if (rooms.isEmpty) {
          return _buildEmptyHint(
            textSecondary,
            s.isEn
                ? "No WiFi rooms found nearby\nEnsure devices are on the same WiFi or hotspot"
                : "未发现附近的 WiFi 房\n请确保几台手机连在同一个 WiFi 或热点下",
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          itemCount: rooms.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final room = rooms[index];
            return _buildRoomCard(
              isNight: isNight,
              cardBg: cardBg,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              title: room.roomName,
              subtitle: "${s.hostTag}: ${room.hostNickname} · ${room.memberCount}/6",
              s: s,
              onJoin: (origin) => _onJoinLanRoom(room, origin),
            );
          },
        );
      },
    );
  }

  Widget _buildBleRoomList(
    bool isNight,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    AppStrings s,
  ) {
    return StreamBuilder<List<DiscoveredBleRoom>>(
      stream: _ble.roomsStream,
      initialData: _ble.currentRooms,
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? [];
        if (rooms.isEmpty) {
          return _buildEmptyHint(
            textSecondary,
            s.isEn
                ? "No Bluetooth rooms found nearby\nTurn on Bluetooth and keep devices close"
                : "未发现附近的蓝牙房\n请打开蓝牙并让几台手机靠近一些",
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          itemCount: rooms.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final room = rooms[index];
            return _buildRoomCard(
              isNight: isNight,
              cardBg: cardBg,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              title: room.roomName,
              subtitle: "${room.memberCount}/6 · RSSI ${room.rssi} dBm",
              s: s,
              onJoin: (origin) => _onJoinBleRoom(room, origin),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyHint(Color textSecondary, String text) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textSecondary.withValues(alpha: 0.6),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildRoomCard({
    required bool isNight,
    required Color cardBg,
    required Color textPrimary,
    required Color textSecondary,
    required String title,
    required String subtitle,
    required AppStrings s,
    required ValueChanged<RevealOrigin?> onJoin,
  }) {
    final joinButtonKey = GlobalKey();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isNight ? const Color(0xFF283A52) : const Color(0xFFDCCEC8),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNight
                  ? AppTheme.nightSkyBlue.withValues(alpha: 0.2)
                  : AppTheme.sunsetCoral.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.radio_button_checked,
              color: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            key: joinButtonKey,
            onPressed: () => onJoin(_originOf(joinButtonKey, _joinButtonRadius)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetBurgundy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
            child: Text(s.joinRoom, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String get _nickname {
    final text = _nicknameController.text.trim();
    return text.isEmpty ? _defaultNickname : text;
  }

  void _wire(RoomSession session, RoomTransport transport) {
    session.onSendFrame = transport.send;
    session.transport = transport; // 房主转移要用它取端点、接任监听、重连
    transport.incoming.listen(session.handleIncomingFrame);

    session.membersStream.listen((members) {
      // 成员号是房主通过名单帧分配的，拿到后必须同步给传输层，
      // 否则房主不知道该把别人的语音转发到哪个 UDP 端点。
      transport.updateSelfMemberId(session.selfMemberId);

      // 蓝牙房主把人数写进 BLE 广播，扫描列表上的「N/6 台」才是准的。
      if (transport is BleL2capTransport) {
        transport.updateMemberCount(members.length);
      }
    });
  }

  Future<void> _releaseTransport(RoomTransport transport) async {
    if (identical(transport, _ble)) {
      await _ble.stop();
    } else {
      await transport.dispose();
    }
  }

  Future<void> _enterRoom(
    RoomSession session,
    RoomTransport transport,
    String roomName,
    RevealOrigin? origin,
    Future<bool> ready,
  ) async {
    if (!mounted) {
      await _releaseTransport(transport);
      return;
    }

    await Navigator.of(context).push(
      RoomEntryRevealRoute<void>(
        origin: origin,
        edgeColor: widget.isNight
            ? AppTheme.moonSilverWhite
            : AppTheme.sunWarmYellow,
        builder: (context) => RoomPage(
          session: session,
          transport: transport,
          isNight: widget.isNight,
          roomName: roomName,
          ready: ready,
        ),
      ),
    );

    await _releaseTransport(transport);
    if (mounted) _startScan(); // 回到首页恢复扫描
  }

  void _onCreateRoom(RevealOrigin? origin) async {
    final nickname = _nickname;
    final isWifi = _selectedMode == RoomMode.wifiFullDuplex;
    final roomName = isWifi ? "$nickname 的 WiFi 房" : "$nickname 的蓝牙房";

    final RoomTransport transport = isWifi ? LanTransport() : _ble;
    final session = RoomSession(
      audioIo: _audioIo,
      selfNickname: nickname,
      mode: _selectedMode,
    );
    _wire(session, transport);

    // 页面立刻推出去，转场动画马上开始；建房在转场期间并发进行。
    // 结果通过 ready 交给房间页——失败它会退回首页，不会把人留在空房间里。
    final ready = _openHostRoom(
      session: session,
      transport: transport,
      isWifi: isWifi,
      roomName: roomName,
      nickname: nickname,
    );

    await _enterRoom(session, transport, roomName, origin, ready);

    if (isWifi) _lanDiscovery.stopAdvertising();
  }

  Future<bool> _openHostRoom({
    required RoomSession session,
    required RoomTransport transport,
    required bool isWifi,
    required String roomName,
    required String nickname,
  }) async {
    try {
      if (isWifi) {
        final lan = transport as LanTransport;
        if (!await lan.startHost()) {
          await lan.dispose();
          return false;
        }
      } else {
        await _lanDiscovery.stop();
        if (!await _ble.startHost(roomName: roomName)) return false;
      }

      // 不开麦：等转场动画结束后由房间页调用 session.startAudio()。
      await session.createRoom(startAudio: false);

      if (isWifi) {
        _lanDiscovery.startAdvertising(
          roomId: "room_${DateTime.now().millisecondsSinceEpoch}",
          roomName: roomName,
          hostNickname: nickname,
          tcpPort: LanTransport.controlPort,
          getMemberCount: () => session.members.length,
        );
      }
      return true;
    } catch (e) {
      AppLog.error('房间', '创建房间失败', e);
      return false;
    }
  }

  void _onJoinLanRoom(DiscoveredRoom room, RevealOrigin? origin) async {
    final lan = LanTransport();
    final session = RoomSession(
      audioIo: _audioIo,
      selfNickname: _nickname,
      mode: RoomMode.wifiFullDuplex,
    );
    _wire(session, lan);

    final ready = () async {
      try {
        final connected = await lan.startClient(
          hostAddress: room.hostAddress,
          port: room.port,
        );
        if (!connected) {
          await lan.dispose();
          return false;
        }
        await session.joinRoom(startAudio: false);
        return true;
      } catch (e) {
        AppLog.error('房间', '加入房间失败', e);
        return false;
      }
    }();

    await _enterRoom(session, lan, room.roomName, origin, ready);
  }

  void _onJoinBleRoom(DiscoveredBleRoom room, RevealOrigin? origin) async {
    final session = RoomSession(
      audioIo: _audioIo,
      selfNickname: _nickname,
      mode: RoomMode.bluetoothPtt,
    );
    _wire(session, _ble);

    final ready = () async {
      try {
        if (!await _ble.connectToHost(room)) return false;
        await session.joinRoom(startAudio: false);
        return true;
      } catch (e) {
        AppLog.error('房间', '加入蓝牙房失败', e);
        return false;
      }
    }();

    await _enterRoom(session, _ble, room.roomName, origin, ready);
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
        height: double.infinity,
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textSecondary,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
