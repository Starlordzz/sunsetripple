import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/audio/audio_io.dart';
import '../../core/session/device_code.dart';
import '../../core/session/room_session.dart';
import '../../core/transport/ble_l2cap_transport.dart';
import '../../core/transport/lan_discovery.dart';
import '../../core/transport/lan_transport.dart';
import '../../core/transport/wifi_direct_manager.dart';
import '../theme/app_theme.dart';
import '../transitions/stage_choreography.dart';
import '../../core/update/update_service.dart';

/// 首页前景：昵称、房型、建房/扫描按钮、附近房间列表。
///
/// 头部的日轮背景与大标题不在这里——它们归 `SessionStage` 管，因为进房时那层
/// 背景要留在原地继续演。这里只负责"会离场的那些东西"：每一块都套了
/// [StageExitItem]，按 [stage] 依次下沉淡出。
class HomeContent extends StatefulWidget {
  final bool isNight;

  /// 整段进房转场的 0→1 进度。0 时是完整首页，0.4 之后这里已经空了。
  /// 传的是动画本身而不是当帧的值——每行各自听，子树不用按帧重建。
  final Animation<double> stage;

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
  List<WifiP2pPeer> _p2pPeers = [];

  Timer? _scanTimer;
  StreamSubscription<List<WifiP2pPeer>>? _p2pSubscription;

  @override
  void initState() {
    super.initState();
    widget.stage.addStatusListener(_onStageStatusChanged);
    _p2pSubscription = WifiDirectManager.instance.peersStream.listen((peers) {
      if (mounted) {
        setState(() {
          _p2pPeers = peers;
        });
      }
    });
    _startScan();
  }

  void _onStageStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _lanDiscovery.stopAdvertising();
      WifiDirectManager.instance.removeGroup();
    }
  }

  void _startScan() {
    setState(() => _isScanning = true);
    _lanDiscovery.startListening();
    WifiDirectManager.instance.discoverPeers();
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });
  }

  @override
  void dispose() {
    widget.stage.removeStatusListener(_onStageStatusChanged);
    _scanTimer?.cancel();
    _p2pSubscription?.cancel();
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
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        child: Row(
                          children: [
                            Icon(Icons.person_outline, size: 24, color: textSecondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _nicknameController,
                                style: TextStyle(color: textPrimary, fontSize: 17),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                                  hintText: "请输入对讲昵称",
                                  hintStyle: TextStyle(color: textSecondary, fontSize: 17),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: (isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '#${DeviceCode.current}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                                ),
                              ),
                            ),
                          ],
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
                              subtitle: "同连WiFi/热点/直连 · 畅聊",
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
                ],
              ),
            ),

            // 5. 房间列表
            SliverToBoxAdapter(
              child: StageExitItem(
                stage: stage,
                index: 4,
                child: StreamBuilder<List<DiscoveredRoom>>(
                  stream: _lanDiscovery.roomsStream,
                  initialData: _lanDiscovery.currentRooms,
                  builder: (context, snapshot) {
                    final rooms = snapshot.data ?? [];
                    final p2pPeers = _p2pPeers;
                    final totalCount = rooms.length + p2pPeers.length;

                    if (totalCount == 0) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                        alignment: Alignment.center,
                        child: Text(
                          "未发现附近的房间或设备\n点击上方「扫描房间」或同连热点/蓝牙即可自动发现",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textSecondary.withValues(alpha: 0.7),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: totalCount,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index < rooms.length) {
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
                        } else {
                          final peer = p2pPeers[index - rooms.length];
                          final peerTitle = peer.name.isNotEmpty ? "${peer.name} 的 WiFi 房" : "附近 WiFi 房";
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
                                        peerTitle,
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
                                        "房主: ${peer.name.isNotEmpty ? peer.name : '附近设备'} · 近场直连",
                                        style: TextStyle(color: textSecondary, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: () => _onJoinWifiDirectPeer(peer),
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
                        }
                      },
                    );
                  },
                ),
              ),
            ),

            // 6. 版本号
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 36),
                child: Center(
                  child: Text(
                    'v${UpdateService.currentVersion}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: textSecondary.withValues(alpha: 0.5),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _nickname {
    final text = _nicknameController.text.trim();
    return text.isEmpty ? "探索者" : text;
  }

  /// 走 roster 的身份名，带十六进制短码，房间里好区分同名的人。
  /// 房名仍然用不带码的昵称，免得标题变得很长。
  String get _identityNickname => DeviceCode.attach(_nickname);

  void _onCreateRoom() async {
    final nickname = _nickname;
    final roomName = _selectedMode == RoomMode.wifiFullDuplex
        ? "$nickname 的 WiFi 房"
        : "$nickname 的蓝牙房";

    final session = RoomSession(
      audioIo: widget.audioIo,
      selfNickname: _identityNickname,
      mode: _selectedMode,
    );

    if (_selectedMode == RoomMode.wifiFullDuplex) {
      unawaited(WifiDirectManager.instance.createGroup());
      final transport = LanTransport();
      await transport.startHost();
      session.transport = transport;
      session.onSendFrame = transport.send;
      transport.incoming.listen(session.handleIncomingFrame);
    } else {
      final transport = BleL2capTransport();
      await transport.startHost(roomName: roomName);
      session.transport = transport;
      session.onSendFrame = transport.send;
      transport.incoming.listen(session.handleIncomingFrame);
    }

    // 不在这里开麦：AudioRecord/AudioTrack 的构造压在 Android 主线程上，
    // 一次上百毫秒，塞进转场会掉帧。SessionStage 会在动画落位后调 startAudio。
    await session.createRoom(startAudio: false);

    if (_selectedMode == RoomMode.wifiFullDuplex) {
      _lanDiscovery.startAdvertising(
        roomId: "room_${DateTime.now().millisecondsSinceEpoch}",
        roomName: roomName,
        hostNickname: _identityNickname,
        tcpPort: 8988,
        getMemberCount: () => session.members.length,
      );
    }

    if (mounted) widget.onEnterRoom(session, roomName);
  }

  void _onJoinRoom(DiscoveredRoom room) async {
    final session = RoomSession(
      audioIo: widget.audioIo,
      selfNickname: _identityNickname,
      mode: RoomMode.wifiFullDuplex,
    );

    final transport = LanTransport();
    await transport.startClient(
      hostAddress: room.hostAddress,
      port: room.port,
    );
    session.transport = transport;
    session.onSendFrame = transport.send;
    transport.incoming.listen(session.handleIncomingFrame);

    // 同 _onCreateRoom：开麦推迟到转场跑完。
    await session.joinRoom(startAudio: false);

    if (mounted) widget.onEnterRoom(session, room.roomName);
  }

  void _onJoinWifiDirectPeer(WifiP2pPeer peer) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("正在连接 (${peer.name.isNotEmpty ? peer.name : peer.address})..."),
        duration: const Duration(seconds: 4),
      ),
    );

    final connectionInfo = await WifiDirectManager.instance.connectAndWait(peer.address);
    if (connectionInfo == null || !connectionInfo.isConnected || connectionInfo.groupOwnerAddress.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("近场连接失败，请确认对端已允许连接"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final hostIp = InternetAddress(connectionInfo.groupOwnerAddress);
    final session = RoomSession(
      audioIo: widget.audioIo,
      selfNickname: _identityNickname,
      mode: RoomMode.wifiFullDuplex,
    );

    final transport = LanTransport();
    await transport.startClient(
      hostAddress: hostIp,
      port: 8988,
    );
    session.transport = transport;
    session.onSendFrame = transport.send;
    transport.incoming.listen(session.handleIncomingFrame);

    await session.joinRoom(startAudio: false);

    if (mounted) {
      final displayName = peer.name.isNotEmpty ? "${peer.name} 的 WiFi 房" : "WiFi 房";
      widget.onEnterRoom(session, displayName);
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
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? activeColor : textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
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

