import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/session/host_transfer.dart';
import 'package:sunset_ripple/core/session/member.dart';

Uint8List token(int seed) => Uint8List.fromList(
      List<int>.generate(16, (index) => (seed + index + 1) & 0xFF),
    );

Member member(
  int id, {
  required int joinOrder,
  String endpoint = '',
  Uint8List? sessionToken,
  bool isHost = false,
  String? nickname,
}) =>
    Member(
      memberId: id,
      nickname: nickname ?? '成员$id',
      sessionToken: sessionToken ?? token(id),
      joinOrder: joinOrder,
      endpoint: endpoint,
      isHost: isHost,
    );

void main() {
  group('从成员表组装交接计划', () {
    test('端点未知的成员不会被选为继任者', () {
      final host = member(1, joinOrder: 0, isHost: true, endpoint: '10.0.0.1');
      final unknown = member(2, joinOrder: 1);
      final known = member(3, joinOrder: 2, endpoint: '10.0.0.3');

      final plan = buildTransferPlanFromRoster(
        members: [host, unknown, known],
        selfMemberId: 1,
        knownEndpoints: const {},
      );

      expect(plan, isNotNull);
      expect(plan!.successorId, 3);
      expect(plan.members.map((m) => m.memberId), [3]);
    });

    test('传输层学到的端点优先，并回填进成员对象', () {
      final host = member(1, joinOrder: 0, isHost: true);
      final peer = member(2, joinOrder: 1, endpoint: '10.0.0.2');

      final plan = buildTransferPlanFromRoster(
        members: [host, peer],
        selfMemberId: 1,
        knownEndpoints: const {2: '192.168.1.9'},
      );

      expect(plan!.successor.endpoint, '192.168.1.9');
      expect(peer.endpoint, '192.168.1.9', reason: '端点会被回填，供下一次快照复用');
    });

    test('继任者按 joinOrder 升序选，房主自己不参与', () {
      final host = member(1, joinOrder: 0, isHost: true, endpoint: '10.0.0.1');
      final junior = member(2, joinOrder: 5, endpoint: '10.0.0.2');
      final senior = member(3, joinOrder: 3, endpoint: '10.0.0.3');

      final plan = buildTransferPlanFromRoster(
        members: [host, junior, senior],
        selfMemberId: 1,
        knownEndpoints: const {},
      );

      expect(plan!.successorId, 3);
      expect(plan.members.map((m) => m.memberId), [3, 2]);
    });

    test('成员缺有效 sessionToken 时整份计划作废', () {
      final host = member(1, joinOrder: 0, isHost: true, endpoint: '10.0.0.1');
      final valid = member(2, joinOrder: 1, endpoint: '10.0.0.2');
      final broken = member(
        3,
        joinOrder: 2,
        endpoint: '10.0.0.3',
        sessionToken: Uint8List(16), // 全零令牌
      );

      expect(
        buildTransferPlanFromRoster(
          members: [host, valid, broken],
          selfMemberId: 1,
          knownEndpoints: const {},
        ),
        isNull,
        reason: '拿不到令牌就恢复不了身份，宁可不迁移',
      );
    });

    test('没有可用候选（房内只有自己）时返回 null', () {
      final host = member(1, joinOrder: 0, isHost: true, endpoint: '10.0.0.1');

      expect(
        buildTransferPlanFromRoster(
          members: [host],
          selfMemberId: 1,
          knownEndpoints: const {},
        ),
        isNull,
      );
    });

    test('指定继任者时必须确实是候选之一', () {
      final host = member(1, joinOrder: 0, isHost: true, endpoint: '10.0.0.1');
      final peer = member(2, joinOrder: 1, endpoint: '10.0.0.2');
      final noEndpoint = member(3, joinOrder: 2);

      final plan = buildTransferPlanFromRoster(
        members: [host, peer, noEndpoint],
        selfMemberId: 1,
        knownEndpoints: const {},
        preferredSuccessorId: 2,
      );
      expect(plan!.successorId, 2);

      expect(
        buildTransferPlanFromRoster(
          members: [host, peer, noEndpoint],
          selfMemberId: 1,
          knownEndpoints: const {},
          preferredSuccessorId: 3,
        ),
        isNull,
        reason: '3 号没有已知端点，不能当继任者',
      );
    });
  });
}
