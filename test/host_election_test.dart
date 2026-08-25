import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/session/host_transfer.dart';

/// 旧的 `HostElection.electNextHost(List<Member>)` 已删除。
/// 选举规则现在在 [HostElection]（`host_transfer.dart`）里，按 joinOrder 而不是时钟。
/// 完整用例在 `test/host_transfer_test.dart`。
void main() {
  test('没有合格候选时返回 null', () {
    expect(HostElection.select(const []), isNull);
    expect(
      HostElection.select([
        const TransferCandidate(
          memberId: 2,
          joinOrder: 1,
          nickname: '离线',
          endpoint: '10.0.0.2',
          connected: false,
        ),
      ]),
      isNull,
    );
  });
}
