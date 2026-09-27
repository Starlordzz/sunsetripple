import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/diagnostics/session_metrics.dart';

void main() {
  group('SessionMetrics.lossPercentOf', () {
    test('没有任何样本时是 0，不做除零', () {
      expect(SessionMetrics.lossPercentOf(0, 0), 0);
    });

    test('只丢没收到时是 100%', () {
      expect(SessionMetrics.lossPercentOf(0, 3), 100);
    });

    test('按收到+丢失为分母四舍五入', () {
      expect(SessionMetrics.lossPercentOf(98, 2), 2);
      expect(SessionMetrics.lossPercentOf(92, 8), 8);
      expect(SessionMetrics.lossPercentOf(2, 1), 33);
      expect(SessionMetrics.lossPercentOf(199, 1), 1);
    });
  });

  group('SessionMetrics.classifyQuality 边界', () {
    test('什么样本都没有 → unknown', () {
      expect(
        SessionMetrics.classifyQuality(receivedFrames: 0, lostFrames: 0),
        NetworkQuality.unknown,
      );
    });

    test('没有帧样本但有延迟样本 → 按延迟判 good', () {
      expect(
        SessionMetrics.classifyQuality(
          receivedFrames: 0,
          lostFrames: 0,
          roundTripTimeMs: 100,
        ),
        NetworkQuality.good,
      );
    });

    test('丢包 1% 且延迟 149ms → good', () {
      expect(
        SessionMetrics.classifyQuality(
          receivedFrames: 99,
          lostFrames: 1,
          roundTripTimeMs: 149,
        ),
        NetworkQuality.good,
      );
    });

    test('丢包恰好 2% → 不算 good，落到 fair', () {
      expect(
        SessionMetrics.classifyQuality(
          receivedFrames: 98,
          lostFrames: 2,
          roundTripTimeMs: 100,
        ),
        NetworkQuality.fair,
      );
    });

    test('延迟恰好 150ms → 不算 good，落到 fair', () {
      expect(
        SessionMetrics.classifyQuality(
          receivedFrames: 1000,
          lostFrames: 0,
          roundTripTimeMs: 150,
        ),
        NetworkQuality.fair,
      );
    });

    test('延迟恰好 400ms 且零丢包 → fair（丢包那一侧仍达标）', () {
      expect(
        SessionMetrics.classifyQuality(
          receivedFrames: 1000,
          lostFrames: 0,
          roundTripTimeMs: 400,
        ),
        NetworkQuality.fair,
      );
    });

    test('丢包恰好 8% 但延迟好 → fair', () {
      expect(
        SessionMetrics.classifyQuality(
          receivedFrames: 92,
          lostFrames: 8,
          roundTripTimeMs: 100,
        ),
        NetworkQuality.fair,
      );
    });

    test('丢包恰好 8% 且延迟恰好 400ms → poor', () {
      expect(
        SessionMetrics.classifyQuality(
          receivedFrames: 92,
          lostFrames: 8,
          roundTripTimeMs: 400,
        ),
        NetworkQuality.poor,
      );
    });

    test('丢包 100% 且无延迟样本 → poor', () {
      expect(
        SessionMetrics.classifyQuality(receivedFrames: 0, lostFrames: 9),
        NetworkQuality.poor,
      );
    });

    test('房主侧（有帧样本但测不到延迟）最多只到 fair', () {
      expect(
        SessionMetrics.classifyQuality(receivedFrames: 500, lostFrames: 0),
        NetworkQuality.fair,
      );
      expect(
        SessionMetrics.classifyQuality(receivedFrames: 500, lostFrames: 60),
        NetworkQuality.poor,
      );
    });
  });

  group('SessionMetrics 值对象', () {
    test('lossPercent 与 networkQuality 由帧计数派生', () {
      final metrics = SessionMetrics(
        receivedFrames: 98,
        lostFrames: 2,
        roundTripTimeMs: 120,
        concealedFrames: 3,
        memberCount: 4,
        uptimeSeconds: 95,
      );

      expect(metrics.lossPercent, 2);
      expect(metrics.networkQuality, NetworkQuality.fair);
      expect(metrics.concealedFrames, 3);
      expect(metrics.memberCount, 4);
      expect(metrics.uptimeSeconds, 95);
    });

    test('toJson 能被 jsonDecode 原样还原全部字段', () {
      final metrics = SessionMetrics(
        receivedFrames: 1200,
        lostFrames: 7,
        roundTripTimeMs: 143,
        concealedFrames: 11,
        memberCount: 6,
        uptimeSeconds: 3725,
      );

      final decoded =
          jsonDecode(jsonEncode(metrics.toJson())) as Map<String, dynamic>;

      expect(decoded['receivedFrames'], 1200);
      expect(decoded['lostFrames'], 7);
      expect(decoded['lossPercent'], metrics.lossPercent);
      expect(decoded['roundTripTimeMs'], 143);
      expect(decoded['concealedFrames'], 11);
      expect(decoded['networkQuality'], 'good');
      expect(decoded['memberCount'], 6);
      expect(decoded['uptimeSeconds'], 3725);
      expect(decoded.keys.toSet(), {
        'receivedFrames',
        'lostFrames',
        'lossPercent',
        'roundTripTimeMs',
        'concealedFrames',
        'networkQuality',
        'memberCount',
        'uptimeSeconds',
      });
    });

    test('没有延迟样本时 toJson 保留 null，toLine 显示 -', () {
      final metrics = SessionMetrics(receivedFrames: 10, lostFrames: 0);

      final decoded =
          jsonDecode(jsonEncode(metrics.toJson())) as Map<String, dynamic>;
      expect(decoded['roundTripTimeMs'], isNull);
      expect(decoded['networkQuality'], 'fair');
      expect(metrics.toLine(), contains('rtt=-ms'));
    });

    test('toLine 是一行 key=value，含全部指标', () {
      final metrics = SessionMetrics(
        receivedFrames: 4,
        lostFrames: 1,
        roundTripTimeMs: 88,
        concealedFrames: 2,
        memberCount: 3,
        uptimeSeconds: 61,
      );

      expect(metrics.toLine(), isNot(contains('\n')));
      expect(
        metrics.toLine(),
        'received=4 lost=1 loss=20% rtt=88ms concealed=2 quality=fair '
        'members=3 uptime=61s',
      );
      expect(metrics.toString(), contains(metrics.toLine()));
    });
  });
}
