import 'dart:async';

import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';
import '../protocol/frame.dart';
import 'room_transport.dart';

const String _tag = '蓝牙';

enum BleRole { idle, hostPeripheral, clientCentral }

/// 扫描到的蓝牙房。
class DiscoveredBleRoom {
  final String address;
  final String roomName;

  /// L2CAP 通道号。由房主那侧的系统动态分配，从 BLE 广播里读出来。
  final int psm;
  final int memberCount;
  final int rssi;
  final DateTime lastSeen;

  DiscoveredBleRoom({
    required this.address,
    required this.roomName,
    required this.psm,
    required this.memberCount,
    required this.rssi,
    required this.lastSeen,
  });
}

/// 蓝牙房传输层：BLE L2CAP CoC（面向连接通道）。
///
/// 选它而不是经典蓝牙 RFCOMM 的原因：iOS 有 CBL2CAPChannel 对应物、不需要 MFi，
/// 鸿蒙 NEXT 也原生支持，是三端共用同一套协议的唯一选择。需要 Android 10（API 29）。
///
/// 注意 **PSM 不能写死**：它由房主那侧的系统在开监听时分配，通过 BLE 广播的
/// 厂商数据发布，客户端扫描时读取。这个类原先有一个 `defaultPsm = 0x1001`
/// 的常量，用它永远连不上。
///
/// 星型拓扑的帧转发在原生侧完成（房主把一个成员的帧转给其余成员），
/// 这里只负责收发。
class BleL2capTransport implements RoomTransport {
  static const MethodChannel _channel =
      MethodChannel('host.msknet.sunsetripple/ble_l2cap');
  static const EventChannel _dataChannel =
      EventChannel('host.msknet.sunsetripple/ble_l2cap_data');
  static const EventChannel _scanChannel =
      EventChannel('host.msknet.sunsetripple/ble_l2cap_scan');

  /// 扫描结果多久没再出现就认为房间已经消失。
  static const Duration _roomTtl = Duration(seconds: 6);

  BleRole _role = BleRole.idle;
  int? _currentSpeakerId; // PTT 话权令牌
  int _peerCount = 0;

  StreamSubscription? _dataSubscription;
  StreamSubscription? _scanSubscription;
  Timer? _pruneTimer;

  bool _sendErrorReported = false;

  final Map<String, DiscoveredBleRoom> _rooms = {};
  final StreamController<Frame> _incoming = StreamController<Frame>.broadcast();
  final StreamController<List<DiscoveredBleRoom>> _roomsController =
      StreamController<List<DiscoveredBleRoom>>.broadcast();

  @override
  Stream<Frame> get incoming => _incoming.stream;

  @override
  int get peerCount => _peerCount;

  Stream<List<DiscoveredBleRoom>> get roomsStream => _roomsController.stream;
  List<DiscoveredBleRoom> get currentRooms => _rooms.values.toList();

  BleRole get role => _role;
  bool get isHost => _role == BleRole.hostPeripheral;

  /// 本机能否开蓝牙房。不能的话返回的原因已经写进日志了。
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (e) {
      AppLog.error(_tag, '检查蓝牙能力失败', e);
      return false;
    }
  }

  // ------------------------------------------------------------------ 房主

  Future<bool> startHost({
    required String roomName,
    int memberCount = 1,
  }) async {
    _role = BleRole.hostPeripheral;
    _currentSpeakerId = null;
    _sendErrorReported = false;
    _listenIncomingData();

    try {
      final ok = await _channel.invokeMethod<bool>('startAdvertising', {
        'roomName': roomName,
        'memberCount': memberCount,
      });
      if (ok != true) {
        AppLog.error(_tag, '蓝牙房广播未能开启，其他人搜不到这个房间');
        _role = BleRole.idle;
        return false;
      }
      AppLog.info(_tag, '蓝牙房「$roomName」已开始广播');
      return true;
    } on PlatformException catch (e) {
      AppLog.error(_tag, e.message ?? '开启蓝牙房失败', e);
      _role = BleRole.idle;
      return false;
    } on MissingPluginException catch (e) {
      AppLog.error(_tag, '当前平台没有实现蓝牙通道', e);
      _role = BleRole.idle;
      return false;
    }
  }

  /// 人数变了要更新广播内容，扫描列表上的「N/6 台」才准。
  Future<void> updateMemberCount(int memberCount) async {
    if (!isHost) return;
    try {
      await _channel.invokeMethod('updateMemberCount', {
        'memberCount': memberCount,
      });
    } catch (e) {
      AppLog.debug(_tag, '更新广播人数失败：$e');
    }
  }

  // ---------------------------------------------------------------- 客户端

  Future<bool> startScan() async {
    _listenScanResults();

    try {
      final ok = await _channel.invokeMethod<bool>('startScan');
      if (ok != true) {
        AppLog.error(_tag, '蓝牙扫描未能启动，搜不到附近的蓝牙房');
        return false;
      }
      _pruneTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pruneStaleRooms(),
      );
      return true;
    } on PlatformException catch (e) {
      AppLog.error(_tag, e.message ?? '蓝牙扫描失败', e);
      return false;
    } on MissingPluginException catch (e) {
      AppLog.error(_tag, '当前平台没有实现蓝牙通道', e);
      return false;
    }
  }

  Future<void> stopScan() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await _channel.invokeMethod('stopScan');
    } catch (e) {
      AppLog.debug(_tag, '停止蓝牙扫描失败：$e');
    }
  }

  Future<bool> connectToHost(DiscoveredBleRoom room) async {
    _role = BleRole.clientCentral;
    _sendErrorReported = false;
    _listenIncomingData();

    try {
      final ok = await _channel.invokeMethod<bool>('connectL2cap', {
        'address': room.address,
        'psm': room.psm,
      });
      if (ok != true) {
        AppLog.error(_tag, '连接蓝牙房主失败');
        _role = BleRole.idle;
        return false;
      }
      _peerCount = 1;
      AppLog.info(_tag, '已连接蓝牙房「${room.roomName}」');
      return true;
    } on PlatformException catch (e) {
      AppLog.error(_tag, e.message ?? '连接蓝牙房主失败', e);
      _role = BleRole.idle;
      return false;
    } on MissingPluginException catch (e) {
      AppLog.error(_tag, '当前平台没有实现蓝牙通道', e);
      _role = BleRole.idle;
      return false;
    }
  }

  // -------------------------------------------------------------- 话权令牌

  /// 蓝牙带宽扛不住多人同时说话，同一时刻只放行一个人。
  bool requestPttToken(int memberId) {
    if (_currentSpeakerId == null || _currentSpeakerId == memberId) {
      _currentSpeakerId = memberId;
      return true;
    }
    return false;
  }

  void releasePttToken(int memberId) {
    if (_currentSpeakerId == memberId) {
      _currentSpeakerId = null;
    }
  }

  // ------------------------------------------------------------ RoomTransport

  @override
  void send(Frame frame) {
    if (_role == BleRole.idle) {
      AppLog.warn(_tag, '蓝牙通道未建立，${frame.type.name} 帧没有发出去');
      return;
    }

    _channel.invokeMethod('sendL2capData', {
      'data': frame.encode(),
    }).catchError((Object e) {
      // 发送是高频路径，只报第一次。
      if (!_sendErrorReported) {
        _sendErrorReported = true;
        AppLog.error(_tag, '蓝牙数据发送失败，对方收不到语音', e);
      }
      return null;
    });
  }

  /// 转发在原生侧按链路地址完成，不需要成员号映射。
  @override
  void updateSelfMemberId(int id) {}

  /// 蓝牙房不支持房主转移。
  ///
  /// L2CAP 的 PSM 由系统在开监听时分配、经 BLE 广播发布，换房主意味着
  /// 新房主要重新开监听拿一个新 PSM、重新广播，其余人要全部重新扫描才能
  /// 发现它。这套流程一期不做——与旧版「主机退出即散会」的结论一致。
  @override
  bool get supportsHostTransfer => false;

  @override
  Map<int, String> get peerEndpoints => const {};

  @override
  Future<bool> becomeHost() async {
    AppLog.error(_tag, '蓝牙房暂不支持房主转移');
    return false;
  }

  @override
  Future<bool> reconnectToHost(String endpoint) async {
    AppLog.error(_tag, '蓝牙房暂不支持房主转移');
    return false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _incoming.close();
    await _roomsController.close();
  }

  @override
  Future<void> stop() async {
    _role = BleRole.idle;
    _currentSpeakerId = null;
    _sendErrorReported = false;
    _peerCount = 0;

    await stopScan();
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    _rooms.clear();

    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      AppLog.debug(_tag, '关闭蓝牙通道时被忽略的异常：$e');
    }
  }

  // -------------------------------------------------------------------- 内部

  void _listenIncomingData() {
    _dataSubscription?.cancel();
    _dataSubscription = _dataChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) {
          AppLog.warn(_tag, '收到非预期的蓝牙事件类型：${event.runtimeType}');
          return;
        }
        final data = event['data'] as Uint8List?;
        final peerAddress = event['peerAddress'] as String? ?? 'unknown';
        if (data == null) return;

        // 原生侧已经按帧头补齐成整帧了，这里直接解码即可。
        final frame = Frame.decode(data);
        if (frame == null) {
          AppLog.warn(_tag, '收到无法解析的蓝牙帧（${data.length} 字节），来自 $peerAddress');
          return;
        }
        if (!_incoming.isClosed) _incoming.add(frame);
      },
      onError: (Object e) => AppLog.error(_tag, '蓝牙数据通道中断', e),
    );
  }

  void _listenScanResults() {
    _scanSubscription?.cancel();
    _scanSubscription = _scanChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;

        final address = event['address'] as String?;
        final psm = event['psm'] as int?;
        if (address == null || psm == null || psm <= 0) return;

        _rooms[address] = DiscoveredBleRoom(
          address: address,
          roomName: event['roomName'] as String? ?? '蓝牙房',
          psm: psm,
          memberCount: event['memberCount'] as int? ?? 1,
          rssi: event['rssi'] as int? ?? 0,
          lastSeen: DateTime.now(),
        );
        _emitRooms();
      },
      onError: (Object e) => AppLog.error(_tag, '蓝牙扫描出错', e),
    );
  }

  void _pruneStaleRooms() {
    final now = DateTime.now();
    final before = _rooms.length;
    _rooms.removeWhere((_, room) => now.difference(room.lastSeen) > _roomTtl);
    if (_rooms.length != before) _emitRooms();
  }

  void _emitRooms() {
    if (_roomsController.isClosed) return;
    _roomsController.add(_rooms.values.toList());
  }
}
