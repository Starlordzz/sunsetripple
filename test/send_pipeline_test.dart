import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/session/send_pipeline.dart';

Frame buildFrame(int seq) => Frame(
      type: FrameType.heartbeat,
      senderId: 1,
      seq: seq,
      payload: Uint8List(0),
    );

void main() {
  group('序号分配', () {
    test('从 1 开始累加，到 0xFFFF 之后回绕到 0', () {
      final pipeline = SendPipeline();

      expect(pipeline.nextSeq(), 1);
      expect(pipeline.nextSeq(), 2);

      // 把计数器推到上界前一位：再调 65532 次后，下一次正好返回 0xFFFF。
      for (var i = 0; i < 0xFFFC; i++) {
        pipeline.nextSeq();
      }
      expect(pipeline.nextSeq(), 0xFFFF);
      expect(pipeline.nextSeq(), 0);
      expect(pipeline.nextSeq(), 1);
    });
  });

  group('链路装配', () {
    test('没接出口时 emit 是空操作，不抛异常', () {
      final pipeline = SendPipeline();

      expect(pipeline.isAttached, isFalse);
      expect(pipeline.output, isNull);
      expect(() => pipeline.emit(buildFrame(1)), returnsNormally);
    });

    test('观察者在换传输层出口后仍然被调用（回归 attachTransport 抹钩子）', () {
      final pipeline = SendPipeline();
      final firstSink = <Frame>[];
      final secondSink = <Frame>[];
      final observed = <Frame>[];

      pipeline.addObserver(observed.add);
      pipeline.replaceSink(firstSink.add);
      pipeline.emit(buildFrame(1));

      pipeline.replaceSink(secondSink.add);
      pipeline.emit(buildFrame(2));

      expect(observed.map((f) => f.seq), [1, 2]);
      expect(firstSink.map((f) => f.seq), [1]);
      expect(secondSink.map((f) => f.seq), [2]);
    });

    test('先注册观察者、后接出口，之后照样生效', () {
      final pipeline = SendPipeline();
      final sink = <Frame>[];
      final observed = <Frame>[];

      pipeline.addObserver(observed.add);
      expect(pipeline.output, isNull);

      pipeline.replaceSink(sink.add);
      pipeline.emit(buildFrame(3));

      expect(observed.map((f) => f.seq), [3]);
      expect(sink.map((f) => f.seq), [3]);
    });

    test('改写层可以丢帧，也可以放行', () {
      final pipeline = SendPipeline();
      final sink = <Frame>[];
      pipeline.replaceSink(sink.add);

      pipeline.setInterceptor((frame, next) {
        if (frame.seq == 9) return; // 模拟丢包
        next(frame);
      });

      pipeline.emit(buildFrame(8));
      pipeline.emit(buildFrame(9));
      pipeline.emit(buildFrame(10));

      expect(sink.map((f) => f.seq), [8, 10]);
    });

    test('调用顺序是 观察者 → 改写层 → 出口（观察者只读，位于最外层）', () {
      final pipeline = SendPipeline();
      final order = <String>[];

      pipeline.addObserver((_) => order.add('observer'));
      pipeline.replaceSink((_) => order.add('sink'));
      pipeline.setInterceptor((frame, next) {
        order.add('interceptor');
        next(frame);
      });

      pipeline.emit(buildFrame(1));

      expect(order, ['observer', 'interceptor', 'sink']);
    });

    test('replaceSink(null) 断开出口，emit 不再落到旧出口', () {
      final pipeline = SendPipeline();
      final sink = <Frame>[];
      pipeline.replaceSink(sink.add);

      pipeline.replaceSink(null);
      pipeline.emit(buildFrame(1));

      expect(sink, isEmpty);
      expect(pipeline.isAttached, isFalse);
    });
  });
}
