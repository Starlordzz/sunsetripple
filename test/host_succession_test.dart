import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/session/host_transfer.dart';

/// `HostSuccession.build` 是从 `RoomSession._becomeHost` 里抽出来的**纯逻辑**：
/// 「接任房主之后，本机的成员表长什么样」。
///
/// 抽它出来的动机很实际：这段逻辑原先夹在 `await t.becomeHost()` 与
/// `_broadcastRoster()` 之间，要验证「成员表拼得对不对」必须**先把监听真的起起来**。
/// 抽成纯函数后可以直接断言，而这些断言正是当初 `_buildTransferPlan` /
/// `checkHostFailover` 能安全改动的底气。
void main() {
  Uint8List token(int seed) => Uint8List.fromList(
        List<int>.generate(16, (i) => (seed + i + 1) & 0xFF),
      );

  HostTransferPlan plan({
    required int successorId,
    required List<HostTransferMember> members,
  }) =>
      HostTransferPlan(successorId: successorId, members: members);

  /// 一份典型计划：旧房主要把位子交给 #2，房里还有 #3、#4。
  HostTransferPlan typicalPlan() => plan(
        successorId: 2,
        members: [
          HostTransferMember(
            memberId: 2,
            joinOrder: 5,
            nickname: '阿远#321',
            endpoint: '192.168.1.2',
            sessionToken: token(2),
          ),
          HostTransferMember(
            memberId: 3,
            joinOrder: 6,
            nickname: '小北#654',
            endpoint: '192.168.1.3',
            sessionToken: token(3),
          ),
          HostTransferMember(
            memberId: 4,
            joinOrder: 7,
            nickname: '测试者',
            endpoint: '192.168.1.4',
            sessionToken: token(4),
          ),
        ],
      );

  group('HostSuccession.build', () {
    test('接任者占据 #1 房主席位，且用本地身份覆盖计划里的自述', () {
      final result = HostSuccession.build(
        plan: typicalPlan(),
        selfNickname: '本机的名字',
        selfSessionToken: token(9),
      );

      final self = result.members[HostSuccession.successorMemberId]!;
      expect(self.memberId, 1);
      expect(self.isHost, isTrue, reason: '接任者必须是房主');
      expect(
        self.nickname,
        '本机的名字',
        reason: '计划里对「自己」的描述不可信，必须用本地真值',
      );
      expect(self.sessionToken, token(9));
    });

    test('继任者自己不会作为普通成员重复出现', () {
      final result = HostSuccession.build(
        plan: typicalPlan(),
        selfNickname: '阿远#321',
        selfSessionToken: token(2),
      );

      // 计划里 #2 是继任者：它应该只以「房主 #1」的身份存在，不能同时留在 #2。
      expect(result.members.containsKey(2), isFalse);
      expect(result.members.length, 3, reason: '#1 房主 + #3 + #4');
    });

    test('其余成员按原成员号保留，并带上端点与 token', () {
      final result = HostSuccession.build(
        plan: typicalPlan(),
        selfNickname: '阿远#321',
        selfSessionToken: token(2),
      );

      final three = result.members[3]!;
      expect(three.nickname, '小北#654');
      expect(three.endpoint, '192.168.1.3');
      expect(three.sessionToken, token(3));
      expect(three.isHost, isFalse);
      expect(three.joinOrder, 6);

      final four = result.members[4]!;
      expect(four.endpoint, '192.168.1.4');
    });

    test('计划里出现成员号 1 时被忽略并记录，不覆盖接任者身份', () {
      // 正常计划不含 #1（1 是房主席位），但恶意/损坏的计划可能有。
      final malicious = plan(
        successorId: 2,
        members: [
          HostTransferMember(
            memberId: 2,
            joinOrder: 5,
            nickname: '阿远#321',
            endpoint: '192.168.1.2',
            sessionToken: token(2),
          ),
          HostTransferMember(
            memberId: 1,
            joinOrder: 6,
            nickname: '冒充者',
            endpoint: '192.168.1.99',
            sessionToken: token(1),
          ),
        ],
      );

      final result = HostSuccession.build(
        plan: malicious,
        selfNickname: '本机的名字',
        selfSessionToken: token(9),
      );

      expect(result.conflictedMemberIds, [1]);
      expect(
        result.members[1]!.nickname,
        '本机的名字',
        reason: '冲突的 #1 绝不能覆盖接任者的本地身份',
      );
      expect(result.members[1]!.sessionToken, token(9));
      expect(result.members.length, 1);
    });

    test('nextJoinOrder 接在所有人的 joinOrder 之后', () {
      final result = HostSuccession.build(
        plan: typicalPlan(),
        selfNickname: '本机的名字',
        selfSessionToken: token(9),
      );

      // 计划里最大 joinOrder 是 7，新成员不能插到别人前面。
      expect(result.nextJoinOrder, greaterThan(7));
    });

    test('单成员计划（只有继任者自己）也能成型', () {
      final solo = plan(
        successorId: 2,
        members: [
          HostTransferMember(
            memberId: 2,
            joinOrder: 5,
            nickname: '阿远#321',
            endpoint: '192.168.1.2',
            sessionToken: token(2),
          ),
        ],
      );

      final result = HostSuccession.build(
        plan: solo,
        selfNickname: '阿远#321',
        selfSessionToken: token(2),
      );

      expect(result.members.length, 1);
      expect(result.members[1]!.isHost, isTrue);
      expect(result.conflictedMemberIds, isEmpty);
    });
  });

  group('HostElection 与 HostSuccession 的接续', () {
    test('选举出的继任者接任后成为 #1，其余成员顺序不乱', () {
      final candidates = [
        TransferCandidate(
          memberId: 2,
          joinOrder: 9,
          nickname: '晚来的',
          endpoint: '10.0.0.2',
          sessionToken: token(2),
        ),
        TransferCandidate(
          memberId: 3,
          joinOrder: 4,
          nickname: '资深的',
          endpoint: '10.0.0.3',
          sessionToken: token(3),
        ),
        TransferCandidate(
          memberId: 4,
          joinOrder: 7,
          nickname: '中间的',
          endpoint: '10.0.0.4',
          sessionToken: token(4),
        ),
      ];

      final elected = HostElection.plan(candidates);
      expect(elected, isNotNull);
      expect(elected!.successorId, 3, reason: 'joinOrder 最小的当继任者');

      final succession = HostSuccession.build(
        plan: elected,
        selfNickname: '资深的',
        selfSessionToken: token(3),
      );

      expect(succession.members[1]!.isHost, isTrue);
      expect(succession.members.containsKey(3), isFalse,
          reason: '继任者升格为 #1，不该再占着 #3');
      expect(succession.members.keys.toSet(), {1, 2, 4});
    });
  });
}
