import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/transport/wifi_direct_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('host.msknet.sunsetripple/wifi_direct');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'isEnabled':
          return true;
        case 'createGroup':
          return true;
        case 'removeGroup':
          return true;
        case 'discoverPeers':
          return true;
        case 'connect':
          return true;
        case 'disconnect':
          return true;
        case 'getConnectionInfo':
          return {
            'isConnected': true,
            'isGroupOwner': true,
            'groupFormed': true,
            'groupOwnerAddress': '192.168.49.1',
          };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('WifiP2pPeer & WifiP2pConnectionInfo Model Tests', () {
    test('WifiP2pPeer.fromMap parses standard map properly', () {
      final map = {
        'name': 'OnePlus 9',
        'address': '46:b2:f7:ca:c4:b3',
        'status': 3,
        'isGroupOwner': true,
      };
      final peer = WifiP2pPeer.fromMap(map);
      expect(peer.name, 'OnePlus 9');
      expect(peer.address, '46:b2:f7:ca:c4:b3');
      expect(peer.status, 3);
      expect(peer.isGroupOwner, isTrue);
    });

    test('WifiP2pPeer.fromMap uses sensible defaults on empty/null values', () {
      final peer = WifiP2pPeer.fromMap({});
      expect(peer.name, '未知设备');
      expect(peer.address, '');
      expect(peer.status, 0);
      expect(peer.isGroupOwner, isFalse);
    });

    test('WifiP2pConnectionInfo.fromMap parses standard map', () {
      final map = {
        'isConnected': true,
        'isGroupOwner': false,
        'groupFormed': true,
        'groupOwnerAddress': '192.168.49.1',
      };
      final info = WifiP2pConnectionInfo.fromMap(map);
      expect(info.isConnected, isTrue);
      expect(info.isGroupOwner, isFalse);
      expect(info.groupFormed, isTrue);
      expect(info.groupOwnerAddress, '192.168.49.1');
    });

    test('WifiP2pConnectionInfo.fromMap uses defaults on empty map', () {
      final info = WifiP2pConnectionInfo.fromMap({});
      expect(info.isConnected, isFalse);
      expect(info.isGroupOwner, isFalse);
      expect(info.groupFormed, isFalse);
      expect(info.groupOwnerAddress, '');
    });
  });

  group('WifiDirectManager MethodChannel Tests', () {
    final manager = WifiDirectManager.instance;

    test('isSupported and isEnabled return true when mocked', () async {
      expect(await manager.isSupported(), isTrue);
      expect(await manager.isEnabled(), isTrue);
    });

    test('createGroup and removeGroup succeed', () async {
      expect(await manager.createGroup(), isTrue);
      expect(await manager.removeGroup(), isTrue);
    });

    test('discoverPeers, connect and disconnect invoke correctly', () async {
      expect(await manager.discoverPeers(), isTrue);
      expect(await manager.connect('46:b2:f7:ca:c4:b3'), isTrue);
      expect(await manager.disconnect(), isTrue);
    });

    test('getConnectionInfo retrieves structured info', () async {
      final info = await manager.getConnectionInfo();
      expect(info.isConnected, isTrue);
      expect(info.isGroupOwner, isTrue);
      expect(info.groupOwnerAddress, '192.168.49.1');
    });

    test('connectAndWait returns null when connection times out', () async {
      final result = await manager.connectAndWait(
        '46:b2:f7:ca:c4:b3',
        timeout: const Duration(milliseconds: 50),
      );
      expect(result, isNull);
    });
  });
}
