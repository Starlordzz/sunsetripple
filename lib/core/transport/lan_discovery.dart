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

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  final Map<String, DiscoveredRoom> _discoveredRooms = {};

  /// 自己作为房主时广播的房间号——用来把自己从「附近的房间」里滤掉。
  String? _selfRoomId;

  final _roomsController = StreamController<List<DiscoveredRoom>>.broadcast();
  Stream<List<DiscoveredRoom>> get roomsStream => _roomsController.stream;
  List<DiscoveredRoom> get currentRooms => _discoveredRooms.values.toList();

  bool get isListening => _socket != null;

  /// 开始监听 UDP 8990 上的房间广播。
  Future<bool> startListening() async {
    await stop();

    // reusePort 在 Windows 上不被支持，会直接抛异常，退回不带该选项重试。
    _socket = await _bind(reusePort: true) ?? await _bind(reusePort: false);

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
      onError: (Object e) => AppLog.error(_tag, '房间发现通道出错', e),
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

  void stopAdvertising() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _selfRoomId = null;
  }

  void _sendBroadcast({
    required String roomId,
    required String roomName,
    required String hostNickname,
    required int tcpPort,
    required int memberCount,
  }) {
    final socket = _socket;
    if (socket == null) return;

    final jsonPayload = jsonEncode({
      "magic": magicHeader,
      "roomId": roomId,
      "roomName": roomName,
      "hostNickname": hostNickname,
      "port": tcpPort,
      "members": memberCount,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });

    try {
      socket.send(
        utf8.encode(jsonPayload),
        InternetAddress("255.255.255.255"),
        discoveryPort,
      );
    } catch (e) {
      AppLog.warn(_tag, '广播房间信息失败', e);
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

      final room = DiscoveredRoom(
        roomId: roomId,
        roomName: json["roomName"] as String,
        hostNickname: json["hostNickname"] as String,
        hostAddress: datagram.address,
        port: json["port"] as int,
        memberCount: json["members"] as int,
        lastSeen: DateTime.now(),
      );

      _discoveredRooms[roomId] = room;
      _pruneStaleRooms();
      if (!_roomsController.isClosed) {
        _roomsController.add(_discoveredRooms.values.toList());
      }
    } catch (e) {
      AppLog.warn(_tag, '收到字段不完整的房间广播，已忽略', e);
    }
  }

  void _pruneStaleRooms() {
    final now = DateTime.now();
    _discoveredRooms.removeWhere(
      (_, room) => now.difference(room.lastSeen).inSeconds > 4,
    );
  }

  Future<void> stop() async {
    stopAdvertising();
    _socket?.close();
    _socket = null;
    _discoveredRooms.clear();
  }

  void dispose() {
    stop();
    _roomsController.close();
  }
}
