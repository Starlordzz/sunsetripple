import 'dart:math';

/// 昵称后面那串十六进制短码。
///
/// 房间里允许重名——两个人都叫「探索者」时，成员轨道上就分不出谁是谁。
/// 这里给每次启动生成一个 4 位十六进制码，拼在昵称后面（`探索者#3F7A`）
/// 一起走 roster，对端拿到的就是带码的名字，不用改协议。
///
/// 没有做持久化：仓库里现在没有 shared_preferences 之类的依赖，而这串码
/// 只需要在"同一个房间里区分同名的人"这个尺度上唯一，进程内稳定就够了。
class DeviceCode {
  const DeviceCode._();

  /// 昵称与短码之间的分隔符。显示时按它拆开，短码画得淡一点。
  static const String separator = '#';

  static String? _cached;

  /// 本次启动的短码，4 位大写十六进制。
  static String get current {
    return _cached ??= _generate();
  }

  static String _generate() {
    final value = Random.secure().nextInt(0x10000);
    return value.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  /// 把 `探索者#3F7A` 拆成 `('探索者', '3F7A')`；没有短码时后一项为 null。
  ///
  /// 昵称本身可能含 `#`，所以按**最后一个**分隔符拆，且只认 4 位十六进制，
  /// 免得把用户自己起的名字（比如 `C#爱好者`）切坏。
  static (String, String?) split(String nickname) {
    final at = nickname.lastIndexOf(separator);
    if (at <= 0 || at != nickname.length - 5) return (nickname, null);

    final code = nickname.substring(at + 1);
    final isHex = RegExp(r'^[0-9A-F]{4}$').hasMatch(code);
    if (!isHex) return (nickname, null);

    return (nickname.substring(0, at), code);
  }

  /// 给昵称接上本次启动的短码。已经带了码就原样返回。
  static String attach(String nickname) {
    if (split(nickname).$2 != null) return nickname;
    return '$nickname$separator$current';
  }
}
