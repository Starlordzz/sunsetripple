import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/session/host_transfer.dart';

void main() {
  HostTransferMember member(
    int id,
    int order,
    String nick,
    String endpoint,
  ) =>
      HostTransferMember(
        memberId: id,
        joinOrder: order,
        nickname: nick,
        endpoint: endpoint,
      );

  TransferCandidate candidate(
    int id,
    int order, {
    String nick = '成员',
    String endpoint = '192.168.1.2',
    bool connected = true,
  }) =>
      TransferCandidate(
        memberId: id,
        joinOrder: order,
        nickname: nick,
        endpoint: endpoint,
        connected: connected,
      );

  group('HostTransferCodec 编解码', () {
    test('往返一致', () {
      final plan = HostTransferPlan(
        successorId: 3,
        members: [
          member(2, 5, '阿远', '192.168.1.2'),
          member(3, 6, '小北', '192.168.1.3'),
        ],
      );

      final decoded = HostTransferCodec.decode(HostTransferCodec.encode(plan));

      expect(decoded.successorId, 3);
      expect(decoded.members.length, 2);
      expect(decoded.members[0].memberId, 2);
      expect(decoded.members[0].joinOrder, 5);
      expect(decoded.members[0].nickname, '阿远');
      expect(decoded.members[0].endpoint, '192.168.1.2');
      expect(decoded.members[1].nickname, '小北');
    });

    test('中文昵称按 UTF-8 截断且不会切出半个字', () {
      // 每个汉字 3 字节，上限 64 字节 → 最多 21 个字。
      final longName = '落' * 40;
      final plan = HostTransferPlan(
        successorId: 2,
        members: [member(2, 1, longName, '10.0.0.2')],
      );

      final decoded = HostTransferCodec.decode(HostTransferCodec.encode(plan));
      final nick = decoded.members.single.nickname;

      expect(nick.length, 21);
      expect(nick, '落' * 21);
      expect(nick.contains('�'), isFalse, reason: '不能切出半个多字节字符');
    });

    test('载荷不超过帧上限', () {
      final plan = HostTransferPlan(
        successorId: 2,
        members: [
          for (int i = 2; i <= 6; i++)
            member(i, i, '成员$i', '192.168.100.$i'),
        ],
      );

      expect(
        HostTransferCodec.encode(plan).length,
        lessThanOrEqualTo(Frame.maxPayloadSize),
      );
    });

    test('非 ASCII 端点被拒绝', () {
      final plan = HostTransferPlan(
        successorId: 2,
        members: [member(2, 1, '阿远', '主机地址')],
      );

      expect(() => HostTransferCodec.encode(plan), throwsArgumentError);
    });

    test('尾部多余字节被拒绝', () {
      final plan = HostTransferPlan(
        successorId: 2,
        members: [member(2, 1, '阿远', '10.0.0.2')],
      );
      final bytes = HostTransferCodec.encode(plan);
      final padded = Uint8List.fromList([...bytes, 0x00]);

      expect(() => HostTransferCodec.decode(padded), throwsArgumentError);
    });

    test('截断的载荷被拒绝', () {
      final plan = HostTransferPlan(
        successorId: 2,
        members: [member(2, 1, '阿远', '10.0.0.2')],
      );
      final bytes = HostTransferCodec.encode(plan);
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 3);

      expect(
        () => HostTransferCodec.decode(Uint8List.fromList(truncated)),
        throwsArgumentError,
      );
    });
  });

  group('HostTransferPlan 校验', () {
    test('成员 ID 重复被拒绝', () {
      expect(
        () => HostTransferPlan(
          successorId: 2,
          members: [
            member(2, 1, 'A', '10.0.0.2'),
            member(2, 2, 'B', '10.0.0.3'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('端点重复被拒绝', () {
      // 端点重复意味着重连时两个人会抢同一个身份。
      expect(
        () => HostTransferPlan(
          successorId: 2,
          members: [
            member(2, 1, 'A', '10.0.0.2'),
            member(3, 2, 'B', '10.0.0.2'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('继任者不在成员表里被拒绝', () {
      expect(
        () => HostTransferPlan(
          successorId: 9,
          members: [member(2, 1, 'A', '10.0.0.2')],
        ),
        throwsArgumentError,
      );
    });

    test('成员数超过 6 被拒绝', () {
      expect(
        () => HostTransferPlan(
          successorId: 2,
          members: [
            for (int i = 2; i <= 8; i++) member(i, i, 'M$i', '10.0.0.$i'),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('HostElection 选举规则', () {
    test('按 joinOrder 升序取最资深的', () {
      final winner = HostElection.select([
        candidate(4, 9, endpoint: '10.0.0.4'),
        candidate(2, 3, endpoint: '10.0.0.2'),
        candidate(3, 7, endpoint: '10.0.0.3'),
      ]);

      expect(winner!.memberId, 2);
    });

    test('joinOrder 相同时按 memberId 升序', () {
      final winner = HostElection.select([
        candidate(5, 4, endpoint: '10.0.0.5'),
        candidate(3, 4, endpoint: '10.0.0.3'),
      ]);

      expect(winner!.memberId, 3);
    });

    test('未连接或端点为空的候选被排除', () {
      final winner = HostElection.select([
        candidate(2, 1, endpoint: '10.0.0.2', connected: false),
        candidate(3, 2, endpoint: '   '),
        candidate(4, 3, endpoint: '10.0.0.4'),
      ]);

      expect(winner!.memberId, 4, reason: '找不到的人不能当继任者');
    });

    test('没有合格候选时返回 null', () {
      expect(HostElection.select([candidate(2, 1, connected: false)]), isNull);
      expect(HostElection.plan([]), isNull);
    });
  });

  group('HostTransferSeed 成员号重编', () {
    test('继任者排到最前，其余按 joinOrder 顺延', () {
      final plan = HostTransferPlan(
        successorId: 4,
        members: [
          member(2, 10, '甲', '10.0.0.2'),
          member(3, 20, '乙', '10.0.0.3'),
          member(4, 30, '丙', '10.0.0.4'),
        ],
      );

      final seed = HostTransferSeed.from(plan);

      expect(seed.host.previousId, 4);
      expect(seed.host.newId, 0);
      expect(seed.members.map((m) => m.previousId), [4, 2, 3]);
      expect(seed.members.map((m) => m.newId), [0, 1, 2]);
    });

    test('nextJoinOrder 接在最大值之后', () {
      final plan = HostTransferPlan(
        successorId: 2,
        members: [
          member(2, 10, '甲', '10.0.0.2'),
          member(3, 42, '乙', '10.0.0.3'),
        ],
      );

      expect(HostTransferSeed.from(plan).nextJoinOrder, 43);
    });

    test('expectedByEndpoint 不包含新房主自己', () {
      final plan = HostTransferPlan(
        successorId: 2,
        members: [
          member(2, 1, '甲', '10.0.0.2'),
          member(3, 2, '乙', '10.0.0.3'),
        ],
      );

      final byEndpoint = HostTransferSeed.from(plan).expectedByEndpoint();

      expect(byEndpoint.keys, ['10.0.0.3']);
    });
  });
}
