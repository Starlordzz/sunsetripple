import 'dart:async';
import 'package:flutter/services.dart';
import '../diagnostics/app_log.dart';

const String _tag = 'WiFiDirect';

class WifiP2pPeer {
  final String name;
  final String address;
  final int status;
  final bool isGroupOwner;

  const WifiP2pPeer({
    required this.name,
    required this.address,
    required this.status,
    required this.isGroupOwner,
  });

  factory WifiP2pPeer.fromMap(Map<dynamic, dynamic> map) {
    return WifiP2pPeer(
      name: (map['name'] as String?) ?? '未知设备',
      address: (map['address'] as String?) ?? '',
      status: (map['status'] as int?) ?? 0,
      isGroupOwner: (map['isGroupOwner'] as bool?) ?? false,
    );
  }
}

class WifiP2pConnectionInfo {
  final bool isConnected;
  final bool isGroupOwner;
  final bool groupFormed;
  final String groupOwnerAddress;

  const WifiP2pConnectionInfo({
    required this.isConnected,
    required this.isGroupOwner,
    required this.groupFormed,
    required this.groupOwnerAddress,
  });

  factory WifiP2pConnectionInfo.fromMap(Map<dynamic, dynamic> map) {
    return WifiP2pConnectionInfo(
      isConnected: (map['isConnected'] as bool?) ?? false,
      isGroupOwner: (map['isGroupOwner'] as bool?) ?? false,
      groupFormed: (map['groupFormed'] as bool?) ?? false,
      groupOwnerAddress: (map['groupOwnerAddress'] as String?) ?? '',
    );
  }
}

/// Wi-Fi Direct (Wi-Fi P2P) 近场直连管理器。
class WifiDirectManager {
  static const MethodChannel _channel = MethodChannel('host.msknet.sunsetripple/wifi_direct');
  static const EventChannel _eventChannel = EventChannel('host.msknet.sunsetripple/wifi_direct_events');

  static final WifiDirectManager instance = WifiDirectManager._internal();

  StreamSubscription? _eventSubscription;
  final _peersController = StreamController<List<WifiP2pPeer>>.broadcast();
  final _connectionController = StreamController<WifiP2pConnectionInfo>.broadcast();

  Stream<List<WifiP2pPeer>> get peersStream => _peersController.stream;
  Stream<WifiP2pConnectionInfo> get connectionStream => _connectionController.stream;

  bool _isListening = false;

  WifiDirectManager._internal();

  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> startListeningEvents() async {
    if (_isListening) return;
    if (!await isSupported()) return;
    _isListening = true;

    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is! Map) return;
          final type = event['type'] as String?;
          if (type == 'peers') {
            final peerList = (event['peers'] as List?)
                    ?.map((p) => WifiP2pPeer.fromMap(p as Map))
                    .toList() ??
                [];
            if (!_peersController.isClosed) {
              _peersController.add(peerList);
            }
          } else if (type == 'connection') {
            final info = WifiP2pConnectionInfo.fromMap(event);
            if (!_connectionController.isClosed) {
              _connectionController.add(info);
            }
          }
        },
        onError: (Object e) {
          AppLog.debug(_tag, 'Wi-Fi Direct 事件流未就绪: $e');
        },
        cancelOnError: true,
      );
    } catch (e) {
      AppLog.debug(_tag, '监听 Wi-Fi Direct 事件流失败: $e');
    }
  }

  Future<bool> createGroup() async {
    if (!await isSupported()) return false;
    await startListeningEvents();
    try {
      final success = await _channel.invokeMethod<bool>('createGroup') ?? false;
      if (success) AppLog.info(_tag, '已成功建立 Wi-Fi Direct 群组 (Group Owner)');
      return success;
    } catch (e) {
      AppLog.debug(_tag, '建立 Wi-Fi Direct 群组未完成: $e');
      return false;
    }
  }

  Future<bool> removeGroup() async {
    if (!await isSupported()) return false;
    try {
      return await _channel.invokeMethod<bool>('removeGroup') ?? false;
    } catch (e) {
      AppLog.debug(_tag, '解散 Wi-Fi Direct 群组未完成: $e');
      return false;
    }
  }

  Future<bool> discoverPeers() async {
    if (!await isSupported()) return false;
    await startListeningEvents();
    try {
      return await _channel.invokeMethod<bool>('discoverPeers') ?? false;
    } catch (e) {
      AppLog.debug(_tag, '发起 Wi-Fi Direct 搜索未完成: $e');
      return false;
    }
  }

  Future<bool> connect(String deviceAddress) async {
    if (!await isSupported()) return false;
    await startListeningEvents();
    try {
      final success = await _channel.invokeMethod<bool>('connect', {'deviceAddress': deviceAddress}) ?? false;
      if (success) {
        AppLog.info(_tag, '已向 $deviceAddress 发起 Wi-Fi Direct 连接请求');
      }
      return success;
    } catch (e) {
      AppLog.debug(_tag, '发起到 $deviceAddress 的 Wi-Fi Direct 连接未完成: $e');
      return false;
    }
  }

  /// 发起到指定设备的 Wi-Fi Direct 直连请求并等待系统配对连接就绪。
  Future<WifiP2pConnectionInfo?> connectAndWait(
    String deviceAddress, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final initiated = await connect(deviceAddress);
    if (!initiated) {
      AppLog.error(_tag, '发起 Wi-Fi Direct 直连请求失败');
      return null;
    }

    try {
      final info = await connectionStream
          .firstWhere((info) => info.isConnected && info.groupOwnerAddress.isNotEmpty)
          .timeout(timeout);
      AppLog.info(_tag, 'Wi-Fi Direct 直连链路已就绪 (GO=${info.groupOwnerAddress})');
      return info;
    } on TimeoutException {
      AppLog.warn(_tag, '等待 Wi-Fi Direct 直连连接超时');
      return null;
    } catch (e) {
      AppLog.error(_tag, 'Wi-Fi Direct 握手连接异常: $e');
      return null;
    }
  }

  Future<bool> disconnect() async {
    try {
      return await _channel.invokeMethod<bool>('disconnect') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<WifiP2pConnectionInfo> getConnectionInfo() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getConnectionInfo');
      return WifiP2pConnectionInfo.fromMap(res ?? {});
    } catch (_) {
      return const WifiP2pConnectionInfo(
        isConnected: false,
        isGroupOwner: false,
        groupFormed: false,
        groupOwnerAddress: '',
      );
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _isListening = false;
    _peersController.close();
    _connectionController.close();
  }
}
