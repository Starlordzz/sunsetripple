import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/session/device_code.dart';

void main() {
  group('DeviceCode', () {
    test('短码是 3 位纯数字，进程内稳定', () {
      final code = DeviceCode.current;
      expect(RegExp(r'^\d{3}$').hasMatch(code), isTrue, reason: code);
      expect(DeviceCode.current, code);
      final val = int.parse(code);
      expect(val >= 100 && val <= 999, isTrue);
    });

    test('attach 接上 3 位纯数字短码，重复调用不会接两次', () {
      final once = DeviceCode.attach('探索者');
      expect(once, '探索者${DeviceCode.separator}${DeviceCode.current}');
      expect(DeviceCode.attach(once), once);
    });

    test('split 能把 3 位纯数字短码拆出来', () {
      expect(DeviceCode.split('探索者#108'), ('探索者', '108'));
      expect(DeviceCode.split(DeviceCode.attach('阿彬')).$1, '阿彬');
    });

    test('兼容旧版 4 位十六进制短码，确定性映射为 3 位数字', () {
      final (name, code) = DeviceCode.split('探索者#3F7A');
      expect(name, '探索者');
      expect(RegExp(r'^\d{3}$').hasMatch(code!), isTrue);
      // 确定性验证
      expect(DeviceCode.split('探索者#3F7A').$2, code);
    });

    test('不把用户自己起的带 # 的名字切坏', () {
      expect(DeviceCode.split('C#爱好者'), ('C#爱好者', null));
      expect(DeviceCode.split('老王#ZZZZ'), ('老王#ZZZZ', null));
      expect(DeviceCode.split('探索者'), ('探索者', null));
      expect(DeviceCode.split('#108'), ('#108', null));
    });

    test('智能同名冲突判断 hasConflict 与 formatSmart', () {
      final members = ['探索者#108', '探索者#327', '阿彬#555'];

      expect(DeviceCode.hasConflict('探索者', members), isTrue);
      expect(DeviceCode.hasConflict('阿彬', members), isFalse);

      expect(
        DeviceCode.formatSmart('探索者#108', members),
        '探索者 #108',
      );
      expect(
        DeviceCode.formatSmart('探索者#327', members),
        '探索者 #327',
      );
      expect(
        DeviceCode.formatSmart('阿彬#555', members),
        '阿彬',
      );
    });
  });
}
