import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Room advertisement record discovered over LAN.
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

/// Zero-Configuration LAN / Hotspot Room Discovery via UDP 8990 Broadcast.
class LanRoomDiscovery {
  static const int discoveryPort = 8990;
  static const String magicHeader = "SUNSET_RIPPLE_DISCOVERY_V1";

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  final Map<String, DiscoveredRoom> _discoveredRooms = {};

  final _roomsController = StreamController<List<DiscoveredRoom>>.broadcast();
  Stream<List<DiscoveredRoom>> get roomsStream => _roomsController.stream;
  List<DiscoveredRoom> get currentRooms => _discoveredRooms.values.toList();

  /// Starts listening for LAN room discovery broadcasts on UDP 8990.
  Future<void> startListening() async {
    await stop();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _socket?.broadcastEnabled = true;

      _socket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            _handleIncomingPacket(datagram);
          }
        }
      });
    } catch (e) {
      // In constrained environments or desktop firewalls
    }
  }

  /// Starts broadcasting room advertisement as Host.
  void startAdvertising({
    required String roomId,
    required String roomName,
    required String hostNickname,
    required int tcpPort,
    required int Function() getMemberCount,
  }) {
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
  }

  void _sendBroadcast({
    required String roomId,
    required String roomName,
    required String hostNickname,
    required int tcpPort,
    required int memberCount,
  }) {
    if (_socket == null) return;

    final jsonPayload = jsonEncode({
      "magic": magicHeader,
      "roomId": roomId,
      "roomName": roomName,
      "hostNickname": hostNickname,
      "port": tcpPort,
      "members": memberCount,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });

    final bytes = utf8.encode(jsonPayload);
    try {
      _socket?.send(bytes, InternetAddress("255.255.255.255"), discoveryPort);
    } catch (_) {}
  }

  void _handleIncomingPacket(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data);
      final json = jsonDecode(text) as Map<String, dynamic>;

      if (json["magic"] != magicHeader) return;

      final roomId = json["roomId"] as String;
      final roomName = json["roomName"] as String;
      final hostNickname = json["hostNickname"] as String;
      final port = json["port"] as int;
      final memberCount = json["members"] as int;

      final room = DiscoveredRoom(
        roomId: roomId,
        roomName: roomName,
        hostNickname: hostNickname,
        hostAddress: datagram.address,
        port: port,
        memberCount: memberCount,
        lastSeen: DateTime.now(),
      );

      _discoveredRooms[roomId] = room;
      _pruneStaleRooms();
      _roomsController.add(_discoveredRooms.values.toList());
    } catch (_) {}
  }

  void _pruneStaleRooms() {
    final now = DateTime.now();
    _discoveredRooms.removeWhere(
      (_, room) => now.difference(room.lastSeen).inSeconds > 4,
    );
  }

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _socket?.close();
    _socket = null;
    _discoveredRooms.clear();
  }

  void dispose() {
    stop();
    _roomsController.close();
  }
}
