import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../diagnostics/app_log.dart';
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import 'room_transport.dart';

enum TransportRole { idle, host, client }

const String _tag = 'LanTransport';

/// 一个成员的语音端点（UDP 源地址+端口）。
class _Endpoint {
  final InternetAddress address;
  final int port;
  const _Endpoint(this.address, this.port);
}

/// 把 TCP 字节流重新切回一个个 [Frame]。
///
/// TCP 是流式的，一次 `listen` 回调可能拿到半个帧，也可能拿到三个半帧。
/// 帧头第 [4..5] 字节是载荷长度，所以帧本身是自定界的，不需要额外的长度前缀。
class _FrameAccumulator {
  final List<int> _buf = <int>[];

  Iterable<Frame> add(List<int> chunk) sync* {
    _buf.addAll(chunk);

    while (true) {
      if (_buf.length < Frame.headerSize) return;

      final payloadLength = (_buf[4] << 8) | _buf[5];
      if (payloadLength > Frame.maxPayloadSize) {
        // 长度字段不可能这么大，说明流已经错位，没法再对齐了。
        AppLog.error(
          _tag,
          '控制流错位（载荷长度 $payloadLength 超出上限），已丢弃缓冲区',
        );
        _buf.clear();
        return;
      }

      final total = Frame.headerSize + payloadLength;
      if (_buf.length < total) return;

      final raw = Uint8List.fromList(_buf.sublist(0, total));
      _buf.removeRange(0, total);

      final frame = Frame.decode(raw);
      if (frame == null) {
        AppLog.warn(_tag, '收到无法解析的控制帧（$total 字节），已跳过');
        continue;
      }
      yield frame;
    }
  }
}

/// 局域网/热点下的真实传输层：控制帧走 TCP，语音帧走 UDP，房主负责中继。
///
/// 拓扑是星型的——和 [RoomSession] 里「房主分配成员号、广播名单」的假设一致：
///   - 客户端只跟房主连一条 TCP（控制）+ 一条 UDP（语音）
///   - 房主收到任何一帧，都会转发给除来源以外的其他成员，再交给本地会话
///
/// 语音单独走 UDP 是因为 TCP 的队头阻塞会让丢包变成持续卡顿；控制帧量小、
/// 必须可靠，所以留在 TCP 上。
class LanTransport implements RoomTransport {
  static const int controlPort = 8988;
  static const int audioPort = 8989;

  /// 房主自己占 1 个位置，所以最多再接 5 台，合计 6 台。
  static const int maxClients = 5;

  TransportRole _role = TransportRole.idle;

  // 房主侧
  ServerSocket? _server;
  final Map<Socket, String> _clientLabels = {};
  final Map<int, _Endpoint> _audioEndpoints = {};

  // 客户端侧
  Socket? _hostSocket;
  InternetAddress? _hostAddress;

  RawDatagramSocket? _udp;
  Timer? _udpKeepalive;

  int _selfMemberId = 0;

  final StreamController<Frame> _incoming = StreamController<Frame>.broadcast();
  final StreamController<int> _peerCount = StreamController<int>.broadcast();

  /// 收到的、需要交给 [RoomSession.handleIncomingFrame] 的帧。
  @override
  Stream<Frame> get incoming => _incoming.stream;

  /// 当前连接上的对端数量。
  Stream<int> get peerCountStream => _peerCount.stream;

  TransportRole get role => _role;
  bool get isHost => _role == TransportRole.host;

  @override
  int get peerCount => _role == TransportRole.host
      ? _clientLabels.length
      : (_hostSocket == null ? 0 : 1);

  /// 成员号是房主通过名单帧分配的，拿到后要同步进来，
  /// 否则房主无法把语音端点和成员对应起来。
  @override
  void updateSelfMemberId(int id) {
    _selfMemberId = id;
    if (_role == TransportRole.client && _udp != null && _hostAddress != null && id > 0) {
      _sendUdpToHost(
        Frame(
          type: FrameType.heartbeat,
          senderId: id,
          seq: 0,
          payload: Uint8List(0),
        ),
      );
    }
  }

  @override
  bool get supportsHostTransfer => true;

  /// 已知成员的 IP。来自各自 UDP 语音包的源地址——能发语音就说明这条路通，
  /// 正好是交接后重连要用的端点。
  @override
  Map<int, String> get peerEndpoints => {
        for (final entry in _audioEndpoints.entries)
          entry.key: entry.value.address.address,
      };

  @override
  Future<bool> becomeHost() async {
    AppLog.info(_tag, '接任房主，重新开始监听');
    await stop();
    return startHost();
  }

  @override
  Future<bool> reconnectToHost(String endpoint) async {
    final InternetAddress address;
    try {
      address = InternetAddress(endpoint);
    } on ArgumentError catch (e) {
      AppLog.error(_tag, '新房主端点无法解析：$endpoint', e);
      return false;
    }

    AppLog.info(_tag, '重连到新房主 $endpoint');
    await stop();

    for (int attempt = 1; attempt <= 6; attempt++) {
      if (await startClient(hostAddress: address, silent: attempt < 6)) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  // ---------------------------------------------------------------- 房主

  Future<bool> startHost() async {
    await stop();
    _role = TransportRole.host;

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, controlPort);
    } on SocketException catch (e) {
      AppLog.error(_tag, '控制端口 $controlPort 监听失败，其他人无法加入房间', e);
      _role = TransportRole.idle;
      return false;
    }

    _server!.listen(
      _onClientConnected,
      onError: (Object e) => AppLog.error(_tag, '监听连接时出错', e),
    );

    if (!await _bindUdp(audioPort)) {
      await stop();
      return false;
    }

    AppLog.info(_tag, '房间已开启：控制 TCP $controlPort，语音 UDP $audioPort');
    return true;
  }

  void _onClientConnected(Socket socket) {
    // remoteAddress 在 socket 关闭后会抛异常，先把地址记下来。
    final label = '${socket.remoteAddress.address}:${socket.remotePort}';

    if (_clientLabels.length >= maxClients) {
      AppLog.warn(_tag, '房间已满（${maxClients + 1} 台），拒绝了 $label');
      socket.destroy();
      return;
    }

    final accumulator = _FrameAccumulator();
    _clientLabels[socket] = label;
    AppLog.info(_tag, '成员接入：$label');
    _notifyPeerCount();

    socket.listen(
      (chunk) {
        for (final frame in accumulator.add(chunk)) {
          _relayControl(frame, exclude: socket);
          _deliver(frame);
        }
      },
      onError: (Object e) {
        AppLog.warn(_tag, '成员 $label 的连接出错', e);
        _removeClient(socket, label);
      },
      onDone: () {
        AppLog.info(_tag, '成员 $label 已断开');
        _removeClient(socket, label);
      },
      cancelOnError: true,
    );
  }

  void _removeClient(Socket socket, String label) {
    if (_clientLabels.remove(socket) == null) return;
    try {
      socket.destroy();
    } catch (e) {
      AppLog.debug(_tag, '关闭 $label 时被忽略的异常：$e');
    }
    _notifyPeerCount();
  }

  // -------------------------------------------------------------- 客户端

  Future<bool> startClient({
    required InternetAddress hostAddress,
    int port = controlPort,
    bool silent = false,
  }) async {
    await stop();
    _role = TransportRole.client;
    _hostAddress = hostAddress;

    try {
      _hostSocket = await Socket.connect(
        hostAddress,
        port,
        timeout: const Duration(seconds: 4),
      );
    } on SocketException catch (e) {
      if (!silent) {
        AppLog.error(_tag, '连接房主 ${hostAddress.address}:$port 失败', e);
      }
      _role = TransportRole.idle;
      return false;
    } on TimeoutException {
      if (!silent) {
        AppLog.error(_tag, '连接房主 ${hostAddress.address}:$port 超时，请确认在同一个 WiFi/热点下');
      }
      _role = TransportRole.idle;
      return false;
    }

    final accumulator = _FrameAccumulator();
    _hostSocket!.listen(
      (chunk) {
        for (final frame in accumulator.add(chunk)) {
          _deliver(frame);
        }
      },
      onError: (Object e) => AppLog.error(_tag, '与房主的连接出错', e),
      onDone: () => AppLog.warn(_tag, '房主已断开连接'),
      cancelOnError: true,
    );

    // 语音用临时端口，房主从数据包的源地址学习端点。
    if (!await _bindUdp(0)) {
      await stop();
      return false;
    }

    _startUdpKeepalive();
    _notifyPeerCount();
    AppLog.info(_tag, '已连接房主 ${hostAddress.address}:$port');
    return true;
  }

  /// 客户端定期用 UDP 心跳「报到」，房主才知道该把别人的声音发到哪个端口。
  /// 这条心跳只用于登记端点，房主不会把它交给会话层（TCP 上已经有一份）。
  void _startUdpKeepalive() {
    _udpKeepalive?.cancel();
    _udpKeepalive = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_selfMemberId <= 0) return;
      _sendUdpToHost(
        Frame(
          type: FrameType.heartbeat,
          senderId: _selfMemberId,
          seq: 0,
          payload: Uint8List(0),
        ),
      );
    });
  }

  // ------------------------------------------------------------------ UDP

  Future<bool> _bindUdp(int port) async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _udp!.broadcastEnabled = true;
      _udp!.listen(
        _onUdpEvent,
        onError: (Object e) => AppLog.error(_tag, '语音通道出错', e),
      );
      return true;
    } on SocketException catch (e) {
      final what = port == 0 ? '临时端口' : '端口 $port';
      AppLog.error(_tag, '语音 UDP $what 绑定失败，将听不到声音', e);
      return false;
    }
  }

  void _onUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _udp?.receive();
    if (datagram == null) return;

    final frame = Frame.decode(datagram.data);
    if (frame == null) {
      AppLog.warn(_tag, '收到无法解析的语音包（${datagram.data.length} 字节）');
      return;
    }

    if (_role == TransportRole.host) {
      if (frame.senderId > 0) {
        _audioEndpoints[frame.senderId] =
            _Endpoint(datagram.address, datagram.port);
      }
      // 报到心跳只用来登记端点，控制面已经有一份了。
      if (frame.type == FrameType.heartbeat) return;

      _relayAudio(frame, excludeSenderId: frame.senderId);
    }

    _deliver(frame);
  }

  // ------------------------------------------------------------ 发送入口

  /// [RoomSession.onSendFrame] 挂到这里。
  @override
  void send(Frame frame) {
    switch (_role) {
      case TransportRole.host:
        if (frame.type == FrameType.audio) {
          _relayAudio(frame, excludeSenderId: frame.senderId);
        } else {
          _relayControl(frame, exclude: null);
        }
        break;

      case TransportRole.client:
        if (frame.type == FrameType.audio) {
          _sendUdpToHost(frame);
        } else {
          _sendTcpToHost(frame);
        }
        break;

      case TransportRole.idle:
        if (frame.type != FrameType.audio) {
          AppLog.warn(_tag, '传输层未启动，${frame.type.name} 帧没有发出去');
        }
        break;
    }
  }

  void _relayControl(Frame frame, {required Socket? exclude}) {
    if (frame.type == FrameType.leave) {
      _audioEndpoints.remove(frame.senderId);
    }
    if (_clientLabels.isEmpty) return;
    final bytes = frame.encode();

    for (final entry in _clientLabels.entries.toList()) {
      final socket = entry.key;
      if (identical(socket, exclude)) continue;
      try {
        socket.add(bytes);
      } catch (e) {
        AppLog.warn(_tag, '向 ${entry.value} 转发 ${frame.type.name} 帧失败', e);
        _removeClient(socket, entry.value);
      }
    }
  }

  void _relayAudio(Frame frame, {int? excludeSenderId}) {
    final socket = _udp;
    if (socket == null || _audioEndpoints.isEmpty) return;
    final bytes = frame.encode();

    for (final entry in _audioEndpoints.entries) {
      if (entry.key == excludeSenderId) continue;
      final endpoint = entry.value;
      try {
        socket.send(bytes, endpoint.address, endpoint.port);
      } catch (e) {
        AppLog.warn(_tag, '向成员 ${entry.key} 转发语音失败', e);
      }
    }
  }

  void _sendTcpToHost(Frame frame) {
    final socket = _hostSocket;
    if (socket == null) {
      AppLog.warn(_tag, '尚未连接房主，${frame.type.name} 帧没有发出去');
      return;
    }
    try {
      socket.add(frame.encode());
    } catch (e) {
      AppLog.error(_tag, '向房主发送 ${frame.type.name} 帧失败', e);
    }
  }

  void _sendUdpToHost(Frame frame) {
    final socket = _udp;
    final host = _hostAddress;
    if (socket == null || host == null) {
      // 正在重连或初始化过渡中，静默丢弃音频帧（高频路径不打扰 UI）
      return;
    }
    try {
      socket.send(frame.encode(), host, audioPort);
    } catch (e) {
      AppLog.debug(_tag, '发送语音帧失败：$e');
    }
  }

  // ---------------------------------------------------------------- 杂项

  void _deliver(Frame frame) {
    if (_incoming.isClosed) return;
    _incoming.add(frame);
  }

  void _notifyPeerCount() {
    if (_peerCount.isClosed) return;
    _peerCount.add(peerCount);
  }

  @override
  Future<void> stop() async {
    _udpKeepalive?.cancel();
    _udpKeepalive = null;

    for (final entry in _clientLabels.entries.toList()) {
      try {
        entry.key.destroy();
      } catch (e) {
        AppLog.debug(_tag, '关闭 ${entry.value} 时被忽略的异常：$e');
      }
    }
    _clientLabels.clear();
    _audioEndpoints.clear();

    try {
      await _server?.close();
    } catch (e) {
      AppLog.debug(_tag, '关闭监听端口时被忽略的异常：$e');
    }
    _server = null;

    _hostSocket?.destroy();
    _hostSocket = null;
    _hostAddress = null;

    _udp?.close();
    _udp = null;

    _selfMemberId = 0;
    _role = TransportRole.idle;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _incoming.close();
    await _peerCount.close();
  }
}
