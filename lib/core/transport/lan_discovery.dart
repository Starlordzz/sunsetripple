import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../diagnostics/app_log.dart';

const String _tag = '房间发现';

/// 通过 UDP 广播发现到的房间。
class DiscoveredRoom {
  final String roomId;
  final String roomName;
  final String hostNickname;
  final InternetAddress hostAddress;
  final int port;
  final int memberCount;
  final DateTime lastSeen;

  DiscoveredRoom({
    required this.roomId,
    required this.roomName,
    required this.hostNickname,
    required this.hostAddress,
    required this.port,
    required this.memberCount,
    required this.lastSeen,
  });

  @override
  String toString() =>
      'DiscoveredRoom($roomName by $hostNickname at ${hostAddress.address}:$port, $memberCount members)';
}

/// 局域网/热点下的零配置房间发现（UDP 8990 广播）。
class LanRoomDiscovery {
  static const int discoveryPort = 8990;
  static const String magicHeader = "SUNSET_RIPPLE_DISCOVERY_V1";

  /// 发现列表容量上限。广播匿名可伪造，过期清理 3.5 秒才跑一轮，
  /// 没有上限的话伪造洪水能在窗口内灌出上千个假房间。
  static const int maxDiscoveredRooms = 64;

  /// 房名/昵称展示上限（字符）。广播里的字段不受任何校验，超长文本
  /// 会撑爆房间卡片的单行布局。
  static const int maxAdvertisedTextLength = 64;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;
  final Map<String, DiscoveredRoom> _discoveredRooms = {};

  /// 自己作为房主时广播的房间号——用来把自己从「附近的房间」里滤掉。
  String? _selfRoomId;

  final _roomsController = StreamController<List<DiscoveredRoom>>.broadcast();
  Stream<List<DiscoveredRoom>> get roomsStream => _roomsController.stream;
  List<DiscoveredRoom> get currentRooms => _discoveredRooms.values.toList();

  // 上次发出的列表指纹。广播每秒都会刷新 lastSeen 并重建房间对象，
  // 但 UI 关心的字段往往没变；不去重的话首页列表（含退场转场期间）
  // 会被按秒整棵重建。
  String? _lastRoomsSignature;

  bool get isListening => _socket != null;

  /// 开始监听 UDP 8990 上的房间广播。
  Future<bool> startListening() async {
    await stop();

    // reusePort 在 Windows 上不被支持，会直接输出底层报错日志，故 Windows 下直接跳过。
    if (Platform.isWindows) {
      _socket = await _bind(reusePort: false);
    } else {
      _socket = await _bind(reusePort: true) ?? await _bind(reusePort: false);
    }

    if (_socket == null) {
      AppLog.error(_tag, '无法监听 UDP $discoveryPort，扫描不到附近的房间');
      return false;
    }

    _socket!.broadcastEnabled = true;
    _socket!.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _socket?.receive();
        if (datagram != null) _handleIncomingPacket(datagram);
      },
    );

    AppLog.info(_tag, '已开始监听 UDP $discoveryPort');
    return true;
  }

  Future<RawDatagramSocket?> _bind({required bool reusePort}) async {
    try {
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: reusePort,
      );
    } catch (e) {
      if (reusePort) {
        AppLog.debug(_tag, '带 reusePort 绑定失败，改用兼容方式重试：$e');
      } else {
        AppLog.error(_tag, '绑定 UDP $discoveryPort 失败', e);
      }
      return null;
    }
  }

  /// 作为房主开始广播房间信息。
  void startAdvertising({
    required String roomId,
    required String roomName,
    required String hostNickname,
    required int tcpPort,
    required int Function() getMemberCount,
  }) {
    if (_socket == null) {
      AppLog.error(_tag, '发现通道未就绪，房间广播没有发出，其他人搜不到这个房间');
      return;
    }

    _selfRoomId = roomId;
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sendBroadcast(
        roomId: roomId,
        roomName: roomName,
        hostNickname: hostNickname,
        tcpPort: tcpPort,
        memberCount: getMemberCount(),
      );
    });
    AppLog.info(_tag, '房间「$roomName」开始广播（控制端口 $tcpPort）');
  }

  /// 停止广播；[sendGoodbye] 为 true 时向局域网发送即时解散通知，
  /// 让其他设备列表立刻清除该房间，无需等待超时。
  void stopAdvertising({bool sendGoodbye = true}) {
    if (sendGoodbye && _selfRoomId != null && _socket != null) {
      final lastRoomId = _selfRoomId!;
      _sendBroadcast(
        roomId: lastRoomId,
        roomName: "",
        hostNickname: "",
        tcpPort: 0,
        memberCount: 0,
        action: "ROOM_CLOSED",
      );
      Future.delayed(const Duration(milliseconds: 80), () {
        if (_socket != null) {
          _sendBroadcast(
            roomId: lastRoomId,
            roomName: "",
            hostNickname: "",
            tcpPort: 0,
            memberCount: 0,
            action: "ROOM_CLOSED",
          );
        }
      });
    }

    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _selfRoomId = null;
  }

  Future<List<InternetAddress>> _getBroadcastAddresses() async {
    final addresses = <InternetAddress>{
      InternetAddress("255.255.255.255"),
    };

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            // 计算热点/局域网 /24 定向子网广播（如 192.168.43.255）
            final directed = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            addresses.add(InternetAddress(directed));
          }
        }
      }
    } catch (e) {
      AppLog.debug(_tag, '获取本地网卡广播地址失败: $e');
    }

    return addresses.toList();
  }

  void _sendBroadcast({
    required String roomId,
    required String roomName,
    required String hostNickname,
    required int tcpPort,
    required int memberCount,
    String? action,
  }) async {
    final socket = _socket;
    if (socket == null) return;

    final jsonPayload = jsonEncode({
      "magic": magicHeader,
      "roomId": roomId,
      "roomName": roomName,
      "hostNickname": hostNickname,
      "port": tcpPort,
      "members": memberCount,
      if (action != null) "action": action,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });

    final bytes = utf8.encode(jsonPayload);
    final targets = await _getBroadcastAddresses();
    for (final target in targets) {
      try {
        socket.send(bytes, target, discoveryPort);
      } catch (_) {
        // 部分接口若不支持广播，静默跳过
      }
    }
  }

  void _handleIncomingPacket(Datagram datagram) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
    } catch (e) {
      // 同网段其他应用的广播包，属于正常噪声，不打扰用户。
      AppLog.debug(_tag, '忽略无法解析的广播包（${datagram.data.length} 字节）');
      return;
    }

    if (json["magic"] != magicHeader) return;

    try {
      final roomId = json["roomId"] as String;

      // 广播是发到 255.255.255.255 的，自己也会收到自己的包。
      if (roomId == _selfRoomId) return;

      // 收到解散通知，即刻移除。广播谁都能发，只有与该房间最后一次
      // 广播同源的解散包才算数——否则任何设备都能把别人列表里的
      // 房间踢掉。
      if (json["action"] == "ROOM_CLOSED") {
        final known = _discoveredRooms[roomId];
        if (known != null &&
            known.hostAddress.address == datagram.address.address) {
          _discoveredRooms.remove(roomId);
          AppLog.info(_tag, '收到房间 $roomId 的解散通知，已即时从列表移除');
          _notifyRoomsChanged();
        }
        return;
      }

      final port = json["port"] as int;
      // 字段边界检查：广播是匿名的，畸形/恶意的大数值不能往下游传。
      if (port <= 0 || port > 65535) return;

      final room = DiscoveredRoom(
        roomId: roomId,
        roomName: _clampText(json["roomName"] as String),
        hostNickname: _clampText(json["hostNickname"] as String),
        hostAddress: datagram.address,
        port: port,
        memberCount: ((json["members"] as int?) ?? 0).clamp(0, 99),
        lastSeen: DateTime.now(),
      );

      // 防伪造洪水：过期清理是 3.5 秒一次，短时间灌入大量假 roomId
      // 会把列表撑爆，超过上限的陌生房间直接不收。
      if (!_discoveredRooms.containsKey(roomId) &&
          _discoveredRooms.length >= maxDiscoveredRooms) {
        AppLog.warn(_tag, '发现列表已满（$maxDiscoveredRooms），忽略新房间 $roomId');
        return;
      }

      _discoveredRooms[roomId] = room;
      _ensurePruneTimer();
      _pruneStaleRooms();
      _notifyRoomsChanged();
    } catch (e) {
      AppLog.warn(_tag, '收到字段不完整的房间广播，已忽略', e);
    }
  }

  /// 广播字段截断：按字符数钳制，超长的房名/昵称不能进列表 UI。
  static String _clampText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length <= maxAdvertisedTextLength) return trimmed;
    return trimmed.substring(0, maxAdvertisedTextLength);
  }

  void _ensurePruneTimer() {
    if (_pruneTimer != null || _discoveredRooms.isEmpty) return;
    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pruneStaleRooms();
    });
  }

  void _pruneStaleRooms() {
    final now = DateTime.now();
    final countBefore = _discoveredRooms.length;
    _discoveredRooms.removeWhere(
      (_, room) => now.difference(room.lastSeen).inMilliseconds > 3500,
    );
    if (_discoveredRooms.length != countBefore) {
      _notifyRoomsChanged();
    }
    if (_discoveredRooms.isEmpty) {
      _pruneTimer?.cancel();
      _pruneTimer = null;
    }
  }

  void _notifyRoomsChanged() {
    if (_roomsController.isClosed) return;
    final signature = _discoveredRooms.values
        .map((r) => '${r.roomId}|${r.roomName}|${r.hostNickname}|'
            '${r.hostAddress.address}|${r.port}|${r.memberCount}')
        .join(';');
    if (signature == _lastRoomsSignature) return;
    _lastRoomsSignature = signature;
    _roomsController.add(_discoveredRooms.values.toList());
  }

  Future<void> stop() async {
    stopAdvertising();
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _discoveredRooms.clear();
    _notifyRoomsChanged();
  }

  void dispose() {
    stop();
    _roomsController.close();
  }
}
