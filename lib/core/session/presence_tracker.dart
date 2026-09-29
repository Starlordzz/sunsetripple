import '../clock.dart';
import 'member.dart';

/// 成员「在场」状态的簿记与判定，从 `RoomSession` 外提。
///
/// 为什么单独成类：会话里散着三处**时间驱动**的判定——说话指示灯超时熄灭、
/// 心跳超时的成员清理、名单更换后丢弃已离房成员的音频时间戳。它们都是纯计算，
/// 却和话权、房主选举、传输层搅在一起，而且直接读 `DateTime.now()`，于是
/// 「400ms 不再送音频就熄灯」「10 秒没心跳就清人」这两条规则只能靠真实等待验证。
/// 外提后时钟由构造注入，两条规则都能用假时钟确定性断言。
///
/// 职责边界：
///   - 只持有「成员号 → 最后一次送来音频的时刻」与超时规则
///   - **不**碰音频设备、**不**发帧、**不**动传输层（副作用留给会话层）
class PresenceTracker {
  PresenceTracker({this.clock = const SystemClock()});

  /// 判定超时用的时钟，可注入。
  final Clock clock;

  /// 全双工模式下，多久没再收到音频帧就认为对方说完了。
  static const Duration speakingTimeout = Duration(milliseconds: 400);

  /// 心跳每 2 秒一次，超过这个时长没收到任何帧的成员视为已离开。
  ///
  /// 比房主失联阈值（`HostFailoverTracker.hostTimeout`，6 秒）长是有意的：
  /// 普通成员掉线只是少一个人；房主失联要尽快有人接管，否则全房静音。
  static const Duration memberTimeout = Duration(seconds: 10);

  final Map<int, DateTime> _lastAudioAt = <int, DateTime>{};

  /// 当前被跟踪音频时间戳的成员号（测试与诊断用）。
  Iterable<int> get trackedMemberIds => _lastAudioAt.keys;

  /// 某成员最后一次送来音频的时刻；没有记录时返回 null。
  DateTime? lastAudioAtOf(int memberId) => _lastAudioAt[memberId];

  /// 记录某成员刚送来一帧音频。
  void markAudio(int memberId) => _lastAudioAt[memberId] = clock.now();

  /// 收到任意帧即刷新该成员的活跃时间（心跳超时清理的依据）。
  void touch(Member member) => member.lastActiveAt = clock.now();

  /// 熄灭已经停止送音频的成员的说话指示灯。返回名单是否因此发生变化。
  ///
  /// 缺了这一步，WiFi 房里的说话指示灯一旦亮起就永远不会灭——只有 PTT 帧会
  /// 复位它，而全双工模式根本不发 PTT 帧。PTT 模式必须跳过：那边的开关由
  /// `pttState` 帧驱动，用音频超时判定会把「按住但这一瞬间没出声」误判成已闭嘴。
  bool expireSpeaking(
    Iterable<Member> members, {
    required int selfMemberId,
    required bool fullDuplex,
  }) {
    if (!fullDuplex) return false;

    final now = clock.now();
    var changed = false;
    for (final member in members) {
      if (member.memberId == selfMemberId) continue;
      if (!member.isSpeaking) continue;

      final last = _lastAudioAt[member.memberId];
      if (last == null || now.difference(last) > speakingTimeout) {
        member.isSpeaking = false;
        changed = true;
      }
    }
    return changed;
  }

  /// 心跳超时的成员号。房主据此清掉静默掉线的成员——不清理的话，TCP 静默断开
  /// （WiFi 切换、杀进程）的人会一直占着名额，房满 6 人后谁都进不来。
  List<int> staleMemberIds(
    Iterable<Member> members, {
    required int selfMemberId,
  }) {
    final now = clock.now();
    return members
        .where((m) =>
            m.memberId != selfMemberId &&
            now.difference(m.lastActiveAt) > memberTimeout)
        .map((m) => m.memberId)
        .toList();
  }

  /// 丢弃某个成员的音频时间戳（离房、被清理时调用）。
  void forget(int memberId) => _lastAudioAt.remove(memberId);

  /// 丢弃所有已不在 [aliveMemberIds] 里的成员的音频时间戳，返回被丢弃的成员号。
  ///
  /// 调用方负责据此停掉这些人的远端音频流——名单里没有的人留着播放管线，
  /// 只是白占内存。
  List<int> forgetAbsent(Set<int> aliveMemberIds) {
    final gone =
        _lastAudioAt.keys.where((id) => !aliveMemberIds.contains(id)).toList();
    for (final id in gone) {
      _lastAudioAt.remove(id);
    }
    return gone;
  }

  /// 清空全部簿记。入房、离房、房主接任时各调一次。
  void clear() => _lastAudioAt.clear();
}
