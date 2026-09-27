import 'dart:math';

/// 会话级 trace 标识。
///
/// 一次「入房 → 退房」是一次追踪（trace）：入房时 [begin] 生成一个 8 字节
/// 随机 hex（[Random.secure]），此后所有经过 `AppLog` 的日志都会自动带上它，
/// 把同一场会话里散落在传输层、平台通道、会话控制里的日志串成一条线。
///
/// 做成全局单例而不是给每个日志调用点加参数：日志调用点有 60+ 处，大多在
/// 传输/平台层，让它们都去持有一个会话对象既不可行也不该做。`AppLog._add`
/// 在写入时取一次 [current] 快照即可。
///
/// 作用域是栈式的（类似 `Zone` 的嵌套）：[begin] 压入一个新 id，[end] 弹出
/// 最近一个并回到外层 id；栈空时 [current] 为 null，日志里显示为 `-`。
/// 因此 [end] 在重复调用（`leave` 与 `dispose` 都收尾）时是安全的空操作。
class TraceId {
  TraceId._();

  /// traceId 的字节数：8 字节 = 16 个 hex 字符。
  static const int byteLength = 8;

  static final Random _random = Random.secure();
  static final List<String> _stack = <String>[];

  /// 当前会话的 traceId；不在任何会话里时为 null。
  static String? get current => _stack.isEmpty ? null : _stack.last;

  /// 是否处于一次追踪中。
  static bool get isActive => _stack.isNotEmpty;

  /// 开始一次追踪，返回新生成的 traceId（16 位小写 hex）。
  ///
  /// 每调用一次都会生成新的 id。断线重连、房主转移会再次走到入房路径，
  /// 那些场景应先用 [isActive] 判断，避免把同一场会话拆成多条 trace。
  static String begin() {
    final id = generate();
    _stack.add(id);
    return id;
  }

  /// 结束最近一次追踪，返回被弹出的 id；栈空时返回 null。
  static String? end() => _stack.isEmpty ? null : _stack.removeLast();

  /// 生成一个合法的 traceId，但不改变当前作用域。
  static String generate() {
    final buffer = StringBuffer();
    for (var i = 0; i < byteLength; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// 清空所有作用域，供测试隔离全局状态。
  static void reset() => _stack.clear();
}
