import 'dart:async';
import 'dart:collection';

enum LogLevel { debug, info, warn, error }

/// 一条诊断记录。
class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
  final Object? error;

  LogEntry({
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  bool get isUserVisible => level == LogLevel.warn || level == LogLevel.error;

  /// 给用户看的短句：不带堆栈，不带英文异常类名。
  String get displayMessage => message;

  @override
  String toString() {
    final ts = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    final suffix = error == null ? '' : ' <- $error';
    return '[$ts][${level.name.toUpperCase()}][$tag] $message$suffix';
  }
}

/// 全局诊断总线。
///
/// 存在的理由：这个项目里所有平台通道、socket、蓝牙调用原本都被
/// `catch (_) {}` 吞掉，失败时界面上没有任何痕迹，排查只能靠猜。
/// 任何失败路径都应该走这里，让它同时进内存环形缓冲和 UI 提示流。
class AppLog {
  AppLog._();

  static const int _maxRetained = 200;

  static final Queue<LogEntry> _retained = Queue<LogEntry>();
  static final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  /// 全量日志流（诊断面板用）。
  static Stream<LogEntry> get stream => _controller.stream;

  /// 只包含 warn / error 的流（界面弹提示用）。
  static Stream<LogEntry> get userVisibleStream =>
      _controller.stream.where((e) => e.isUserVisible);

  /// 最近的日志，新的在前。
  static List<LogEntry> get recent => _retained.toList().reversed.toList();

  static void debug(String tag, String message) =>
      _add(LogLevel.debug, tag, message, null);

  static void info(String tag, String message) =>
      _add(LogLevel.info, tag, message, null);

  static void warn(String tag, String message, [Object? error]) =>
      _add(LogLevel.warn, tag, message, error);

  static void error(String tag, String message, [Object? error]) =>
      _add(LogLevel.error, tag, message, error);

  static void _add(LogLevel level, String tag, String message, Object? error) {
    final entry = LogEntry(
      level: level,
      tag: tag,
      message: message,
      error: error,
    );

    _retained.addLast(entry);
    while (_retained.length > _maxRetained) {
      _retained.removeFirst();
    }

    // ignore: avoid_print
    print(entry.toString());

    if (!_controller.isClosed) {
      _controller.add(entry);
    }
  }

  static void clear() => _retained.clear();
}
