import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/session/device_code.dart';

void main() {
  group('DeviceCode', () {
    test('短码是 4 位大写十六进制，进程内稳定', () {
      final code = DeviceCode.current;
      expect(RegExp(r'^[0-9A-F]{4}$').hasMatch(code), isTrue, reason: code);
      expect(DeviceCode.current, code);
    });

    test('attach 接上短码，重复调用不会接两次', () {
      final once = DeviceCode.attach('探索者');
      expect(once, '探索者${DeviceCode.separator}${DeviceCode.current}');
      expect(DeviceCode.attach(once), once);
    });

    test('split 能把短码拆出来', () {
      expect(DeviceCode.split('探索者#3F7A'), ('探索者', '3F7A'));
      expect(DeviceCode.split(DeviceCode.attach('阿彬')).$1, '阿彬');
    });

    test('不把用户自己起的带 # 的名字切坏', () {
      // 长度不对
      expect(DeviceCode.split('C#爱好者'), ('C#爱好者', null));
      // 位置对但不是十六进制
      expect(DeviceCode.split('老王#ZZZZ'), ('老王#ZZZZ', null));
      // 小写不算，attach 出来的一定是大写
      expect(DeviceCode.split('老王#3f7a'), ('老王#3f7a', null));
      // 没有分隔符
      expect(DeviceCode.split('探索者'), ('探索者', null));
      // 分隔符开头，前面没有名字
      expect(DeviceCode.split('#3F7A'), ('#3F7A', null));
    });
  });
}
