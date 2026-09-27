import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/diagnostics/app_log.dart';
import 'package:sunset_ripple/core/diagnostics/diagnostic_report.dart';
import 'package:sunset_ripple/core/diagnostics/trace.dart';

void main() {
  setUp(() {
    TraceId.reset();
    AppLog.clear();
  });

  tearDown(() {
    TraceId.reset();
    AppLog.clear();
  });

  group('TraceId', () {
    test('begin 生成 16 位小写 hex，且每次都不重复', () {
      final ids = <String>{};
      for (var i = 0; i < 200; i++) {
        final id = TraceId.begin();
        expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id), isTrue,
            reason: '非法 traceId: $id');
        ids.add(id);
      }
      expect(ids.length, 200, reason: '8 字节随机 id 不该重复');
    });

    test('未开始追踪时 current 为 null、isActive 为 false', () {
      expect(TraceId.current, isNull);
      expect(TraceId.isActive, isFalse);
    });

    test('end 之后 current 回到 null', () {
      final id = TraceId.begin();
      expect(TraceId.current, id);
      expect(TraceId.isActive, isTrue);

      expect(TraceId.end(), id);
      expect(TraceId.current, isNull);
      expect(TraceId.isActive, isFalse);
    });

    test('end 在空栈上是安全的空操作', () {
      expect(TraceId.end(), isNull);
      expect(TraceId.end(), isNull);
      expect(TraceId.current, isNull);
    });

    test('嵌套 begin/end 逐层恢复外层 id', () {
      final outer = TraceId.begin();
      final inner = TraceId.begin();
      expect(TraceId.current, inner);

      expect(TraceId.end(), inner);
      expect(TraceId.current, outer);

      expect(TraceId.end(), outer);
      expect(TraceId.current, isNull);
    });

    test('generate 不改变当前作用域', () {
      final id = TraceId.begin();
      final generated = TraceId.generate();
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(generated), isTrue);
      expect(generated == id, isFalse);
      expect(TraceId.current, id);
    });
  });

  group('AppLog traceId', () {
    test('日志自动带上当前 traceId，格式为 [时间][级别][traceId][tag]', () {
      final id = TraceId.begin();
      AppLog.warn('LanTransport', '房间已满');

      final entry = AppLog.recent.first;
      expect(entry.traceId, id);
      expect(
        entry.toString(),
        matches(RegExp(r'^\[\d{2}:\d{2}:\d{2}\]\[WARN\]\[[0-9a-f]{16}\]'
            r'\[LanTransport\] 房间已满$')),
      );
      expect(entry.toString(), contains('[$id]'));
    });

    test('不在会话里时 traceId 位置显示为 -', () {
      AppLog.info('音频', '麦克风已开启');

      final entry = AppLog.recent.first;
      expect(entry.traceId, isNull);
      expect(entry.toString(), contains('][-][音频] 麦克风已开启'));
    });

    test('退房后新写入的日志不再带旧 traceId', () {
      final id = TraceId.begin();
      AppLog.warn('a', 'in-room');
      TraceId.end();
      AppLog.warn('b', 'after-leave');

      final entries = AppLog.recent;
      expect(entries.first.traceId, isNull);
      expect(entries.first.message, 'after-leave');
      expect(entries[1].traceId, id);
      expect(entries[1].message, 'in-room');
    });

    test('error 后缀与 traceId 共存', () {
      TraceId.begin();
      AppLog.error('音频', '麦克风数据流中断', 'boom');

      final text = AppLog.recent.first.toString();
      expect(text, contains('[ERROR]'));
      expect(text, endsWith('麦克风数据流中断 <- boom'));
    });
  });

  group('DiagnosticReport traceId', () {
    test('create 默认带上当前会话的 traceId 并进 JSON/summary', () {
      final id = TraceId.begin();
      final report =
          DiagnosticReport.create(appVersion: '0.1.0', roomType: 'Wi-Fi');

      expect(report.traceId, id);
      final decoded = jsonDecode(report.encode()) as Map<String, dynamic>;
      expect(decoded['traceId'], id);
      expect(report.issueSummary(), contains('- Trace: $id'));
    });

    test('不在会话里时 traceId 为 null，summary 用 - 占位', () {
      final report =
          DiagnosticReport.create(appVersion: '0.1.0', roomType: 'Idle');

      expect(report.traceId, isNull);
      final decoded = jsonDecode(report.encode()) as Map<String, dynamic>;
      expect(decoded.containsKey('traceId'), isTrue);
      expect(decoded['traceId'], isNull);
      expect(report.issueSummary(), contains('- Trace: -\n'));
    });

    test('显式传入的 traceId 优先于当前作用域', () {
      TraceId.begin();
      final report = DiagnosticReport.create(
        appVersion: '0.1.0',
        roomType: 'Idle',
        traceId: 'deadbeefdeadbeef',
      );
      expect(report.traceId, 'deadbeefdeadbeef');
    });
  });
}
