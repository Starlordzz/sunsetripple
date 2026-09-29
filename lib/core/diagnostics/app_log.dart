import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'trace.dart';

enum LogLevel { debug, info, warn, error }

/// 一条诊断记录。
class LogEntry {
  final DateTime time;
  final LogLevel level;

  /// 写入时的会话 traceId 快照；不在会话里时为 null（打印成 `-`）。
  final String? traceId;
  final String tag;
  final String message;
  final Object? error;

  LogEntry({
    required this.level,
    required this.tag,
    required this.message,
    this.traceId,
    this.error,
    DateTime? time,
    // 缺省时间戳只是平台边界上的兜底：需要伪造时间的调用方显式传 time。
  }) : time = time ?? DateTime.now(); // clock-exempt: 日志缺省时间戳

  bool get isUserVisible => level == LogLevel.warn || level == LogLevel.error;

  /// 给用户看的短句：不带堆栈，不带英文异常类名。
  String get displayMessage => message;

  @override
  String toString() {
    final ts = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    final suffix = error == null ? '' : ' <- $error';
    return '[$ts][${level.name.toUpperCase()}][${traceId ?? '-'}][$tag] '
        '$message$suffix';
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
    // release 构建丢弃 debug/info：这些日志会通过对端 IP、端口、成员昵称
    // 泄出局域网拓扑，而用户抓 logcat 提交 issue 时并不会去审这一层。
    // warn/error 保留，诊断面板要靠它们。
    if (kReleaseMode && level != LogLevel.warn && level != LogLevel.error) {
      return;
    }

    final entry = LogEntry(
      level: level,
      tag: tag,
      message: message,
      // 会话级 traceId 在这里取快照：调用点不用（也不该）关心它。
      traceId: TraceId.current,
      error: error,
    );

    _retained.addLast(entry);
    while (_retained.length > _maxRetained) {
      _retained.removeFirst();
    }

    // 日志可能与平台通道/媒体管线竞争主线程，release 下 `print` 会同步写
    // stdout 并拖慢音频路径；用 debugPrint（带节流）替代。
    debugPrint(entry.toString());

    if (!_controller.isClosed) {
      _controller.add(entry);
    }
  }

  static void clear() => _retained.clear();
}
