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
import '../../l10n/app_strings.dart';

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
    final s = AppStrings.of(context);
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
                                  hintText: s.nicknamePlaceholder,
                                  hintStyle: TextStyle(color: textSecondary, fontSize: 17),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: '${s.deviceCodeTooltip} (#${DeviceCode.current})',
                              child: Container(
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
                              title: s.wifiRoom,
                              subtitle: s.wifiRoomChipSubtitle,
                              isSelected: _selectedMode == RoomMode.wifiFullDuplex,
                              isNight: isNight,
                              onTap: () => setState(() => _selectedMode = RoomMode.wifiFullDuplex),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ModeSelectChip(
                              icon: Icons.bluetooth,
                              title: s.bluetoothRoom,
                              subtitle: s.bleRoomChipSubtitle,
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                elevation: 0,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _selectedMode == RoomMode.wifiFullDuplex ? s.createWifiRoom : s.createBleRoom,
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: OutlinedButton(
                              onPressed: _isScanning ? null : _startScan,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                                  width: 1.6,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isScanning)
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                                        ),
                                      )
                                    else
                                      Icon(
                                        Icons.radar,
                                        size: 21,
                                        color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                                      ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isScanning ? s.scanning : s.scanRooms,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isNight ? AppTheme.moonSilverWhite : AppTheme.sunsetCoral,
                                      ),
                                    ),
                                  ],
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
                          Expanded(
                            child: Text(
                              s.nearbyRoomsTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_isScanning) ...[
                            const SizedBox(width: 8),
                            Text(
                              s.detectingRooms,
                              style: TextStyle(
                                color: isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
                                fontSize: 14,
                              ),
                            ),
                          ],
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
                          s.noRoomsDiscoveredHint,
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
                                        s.roomHostInfo(room.hostNickname, room.memberCount, 6),
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
                                  child: Text(
                                    s.joinRoom,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                        } else {
                          final peer = p2pPeers[index - rooms.length];
                          final peerTitle = peer.name.isNotEmpty ? s.defaultWifiRoomTitle(peer.name) : s.nearbyWifiRoom;
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
                                        "${s.hostTag}: ${peer.name.isNotEmpty ? peer.name : s.nearbyDevice} · ${s.nearFieldDirect}",
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
                                  child: Text(
                                    s.joinRoom,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    final s = AppStrings.of(context);
    final text = _nicknameController.text.trim();
    return text.isEmpty ? s.defaultNickname : text;
  }

  /// 走 roster 的身份名，带十六进制短码，房间里好区分同名的人。
  /// 房名仍然用不带码的昵称，免得标题变得很长。
  String get _identityNickname => DeviceCode.attach(_nickname);

  void _onCreateRoom() async {
    final s = AppStrings.of(context);
    final nickname = _nickname;
    final roomName = _selectedMode == RoomMode.wifiFullDuplex
        ? s.defaultWifiRoomTitle(nickname)
        : s.defaultBleRoomTitle(nickname);

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
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.connectingTo(peer.name.isNotEmpty ? peer.name : peer.address)),
        duration: const Duration(seconds: 4),
      ),
    );

    final connectionInfo = await WifiDirectManager.instance.connectAndWait(peer.address);
    if (connectionInfo == null || !connectionInfo.isConnected || connectionInfo.groupOwnerAddress.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.directConnectPermissionFailed),
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
      final displayName = peer.name.isNotEmpty ? s.defaultWifiRoomTitle(peer.name) : s.wifiRoom;
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

