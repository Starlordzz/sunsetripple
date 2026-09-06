import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/transport/lan_discovery.dart';

import 'lan_transport_whitelist_test.dart' show pumpUntil;

void main() {
  group('LanRoomDiscovery Tests', () {
    test('初始状态房间列表为空且生命周期释放正常', () async {
      final discovery = LanRoomDiscovery();
      expect(discovery.currentRooms.isEmpty, isTrue);
      expect(discovery.isListening, isFalse);

      await discovery.startListening();
      expect(discovery.isListening, isTrue);

      discovery.stopAdvertising();
      await discovery.stop();
      expect(discovery.isListening, isFalse);
      discovery.dispose();
    });

    test('ROOM_CLOSED 同源包即时移除房间；畸形字段被钳制', () async {
      final discovery = LanRoomDiscovery();
      await discovery.startListening();
      addTearDown(discovery.dispose);

      final advertiser = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(advertiser.close);

      void advertise({required int port, String? name, String? action}) {
        advertiser.send(
          utf8.encode(jsonEncode({
            'magic': LanRoomDiscovery.magicHeader,
            'roomId': 'room_origin_test',
            'roomName': name ?? '测试房',
            'hostNickname': '主持人',
            'port': port,
            'members': 2,
            if (action != null) 'action': action,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          })),
          InternetAddress.loopbackIPv4,
          LanRoomDiscovery.discoveryPort,
        );
      }

      // 正常广告进入列表
      advertise(port: 8988);
      await pumpUntil(
        () => discovery.currentRooms.any((r) => r.roomId == 'room_origin_test'),
        reason: '正常广播必须被发现',
      );

      // 畸形端口：忽略该包，已有记录不受影响
      advertise(port: 70000);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        discovery.currentRooms
            .firstWhere((r) => r.roomId == 'room_origin_test')
            .port,
        8988,
      );

      // 超长房名：截断到展示上限
      advertise(port: 8988, name: '长' * 500);
      await pumpUntil(
        () =>
            discovery.currentRooms
                    .firstWhere((r) => r.roomId == 'room_origin_test')
                    .roomName
                    .length <=
            LanRoomDiscovery.maxAdvertisedTextLength,
        reason: '广播里的房名不受任何校验，必须钳制长度',
      );

      // 同源解散通知：立即移除
      advertise(port: 8988, action: 'ROOM_CLOSED');
      await pumpUntil(
        () => discovery.currentRooms.every((r) => r.roomId != 'room_origin_test'),
        reason: '同源的 ROOM_CLOSED 必须即时移除房间',
      );
    });

    test('发现列表容量有上限，伪造洪水灌不满内存', () async {
      final discovery = LanRoomDiscovery();
      await discovery.startListening();
      addTearDown(discovery.dispose);

      final advertiser = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(advertiser.close);

      for (int i = 0; i < LanRoomDiscovery.maxDiscoveredRooms + 20; i++) {
        advertiser.send(
          utf8.encode(jsonEncode({
            'magic': LanRoomDiscovery.magicHeader,
            'roomId': 'room_flood_$i',
            'roomName': '洪水房$i',
            'hostNickname': '伪造者',
            'port': 8988,
            'members': 1,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          })),
          InternetAddress.loopbackIPv4,
          LanRoomDiscovery.discoveryPort,
        );
      }

      // 给UDP 处理留一点时间，然后断言列表从未超过上限。
      await pumpUntil(
        () => discovery.currentRooms.length >= 4,
        reason: '至少应收到一部分广播',
        timeout: const Duration(seconds: 3),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        discovery.currentRooms.length,
        lessThanOrEqualTo(LanRoomDiscovery.maxDiscoveredRooms),
        reason: '匿名广播可以伪造大量 roomId，列表必须有硬上限',
      );
    });
  });
}
