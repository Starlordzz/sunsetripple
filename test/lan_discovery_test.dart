import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/transport/lan_discovery.dart';

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
  });
}
