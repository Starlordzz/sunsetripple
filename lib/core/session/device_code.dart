import 'dart:math';

/// 方案三：3 位纯数字 + 智能同名冲突显隐
///
/// 房间里允许重名——两个人都叫「探索者」时，为了清晰区分：
/// 1. 采用更简洁亲和的 3 位纯数字设备标识码（100~999）；
/// 2. 兼容旧版本或测试中出现的 4 位十六进制短码（确定性哈希映射为 3 位数字）；
/// 3. 智能同名冲突机制：当房间内昵称唯一时保持纯净美观（如「探索者」），
///    仅在发生同名冲突时才自动显式标注设备码（如「探索者 #108」与「探索者 #327」）。
class DeviceCode {
  const DeviceCode._();

  /// 昵称与短码之间的分隔符。
  static const String separator = '#';

  static String? _cached;

  /// 本次启动的短码：3 位纯数字（100 ~ 999）
  static String get current {
    return _cached ??= _generate();
  }

  static String _generate() {
    final value = 100 + Random.secure().nextInt(900); // 100..999
    return value.toString();
  }

  /// 转换或规范化为 3 位纯数字短码
  static String toNumeric(String? code) {
    if (code == null || code.trim().isEmpty) return '100';
    final trimmed = code.trim();
    if (RegExp(r'^\d{3}$').hasMatch(trimmed)) return trimmed;

    // 针对旧版 4 位十六进制码或异常字符串，进行确定性哈希映射至 100..999
    int hash = 0;
    for (int i = 0; i < trimmed.length; i++) {
      hash = (hash * 31 + trimmed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final num = 100 + (hash % 900);
    return num.toString();
  }

  /// 把 `探索者#108` 或 `探索者#3F7A` 拆成 `('探索者', '108')`；没有短码时后一项为 null。
  ///
  /// 昵称本身可能含 `#`，所以按**最后一个**分隔符拆，
  /// 支持 3 位纯数字以及 4 位十六进制码，避免将用户自定义名字切坏。
  static (String, String?) split(String nickname) {
    final at = nickname.lastIndexOf(separator);
    if (at <= 0) return (nickname, null);

    final code = nickname.substring(at + 1);
    final is3Digit = RegExp(r'^\d{3}$').hasMatch(code);
    final is4Hex = RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(code);
    if (!is3Digit && !is4Hex) return (nickname, null);

    return (nickname.substring(0, at), toNumeric(code));
  }

  /// 给昵称接上本次启动的短码。已经带了码就原样返回。
  static String attach(String nickname) {
    final (_, code) = split(nickname);
    if (code != null) return nickname;
    return '$nickname$separator$current';
  }

  /// 检测给定的基准昵称在全员列表中是否存在同名冲突
  static bool hasConflict(String baseName, Iterable<String> allNicknames) {
    int count = 0;
    for (final nick in allNicknames) {
      final (base, _) = split(nick);
      if (base == baseName) {
        count++;
        if (count > 1) return true;
      }
    }
    return false;
  }

  /// 智能格式化：若同名则展示 `昵称 #108`，若唯一则仅展示 `昵称`
  static String formatSmart(String rawNickname, Iterable<String> allNicknames) {
    final (base, code) = split(rawNickname);
    if (code == null) return base;
    if (hasConflict(base, allNicknames)) {
      return '$base $separator$code';
    }
    return base;
  }
}
