import 'dart:async';

import 'chat_message.dart';
import 'device_code.dart';

/// 房间文字聊天的**状态与规则**，从 `RoomSession` 外提。
///
/// 为什么单独成类：聊天在 `RoomSession` 里占了近一半的私有方法（历史表、
/// 去重窗口、撤回、历史同步、同人识别），却几乎不依赖会话状态机的其它部分。
/// 把它们留在 1500+ 行的上帝对象里，任何一次聊天改动都要在话权、房主选举、
/// 心跳、重连之间穿行，认知负荷与回归面积都被放大。
///
/// 职责边界：
///   - 仅维护**本地**聊天状态与去重/排序/上限规则
///   - **不**发帧、不读传输层（编解码后交给上层发送）
///   - **不**判定发送者是否在册（那是会话层的鉴权职责，见 `RoomSession`）
class SessionChatHub {
  /// 纯内存聊天历史上限。
  static const int maxHistory = 100;

  /// `(senderId, seq)` 有界去重队列容量。
  static const int maxDeduplicationKeys = 512;

  final List<ChatMessage> _messages = [];
  final Set<String> _seenKeys = <String>{};
  final List<String> _seenKeyOrder = <String>[];

  int _unreadCount = 0;

  /// 跨进退房同人身份追踪（基于设备短码）。
  final Map<String, String> _currentNicknameByCode = {};
  final Map<String, Set<String>> _previousNicknamesByCode = {};

  final _messageController =
      StreamController<ChatMessage>.broadcast(sync: true);
  final _listController =
      StreamController<List<ChatMessage>>.broadcast(sync: true);
  final _unreadController = StreamController<int>.broadcast(sync: true);

  Stream<ChatMessage> get messageStream => _messageController.stream;
  Stream<List<ChatMessage>> get listStream => _listController.stream;
  Stream<int> get unreadStream => _unreadController.stream;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  int get unreadCount => _unreadCount;

  // ------------------------------------------------------------ 身份追踪

  /// 记录某设备短码当前使用的昵称，并把旧昵称归档为「曾用名」。
  ///
  /// 改名时同步回填该短码已发出的历史消息（`senderNickname` /
  /// `previousNickname`），让同一人的旧消息在新名字下仍能正确署名——这正是
  /// 之前散落在 `RoomSession._recordMemberIdentity` 里的那段循环。
  /// 返回是否发生了改名（调用方据此决定要不要额外提示）。
  bool recordIdentity(String code, String fullNickname) {
    if (code.isEmpty || fullNickname.isEmpty) return false;
    final (base, _) = DeviceCode.split(fullNickname);
    final clean = base.isEmpty ? fullNickname : base;

    if (!_currentNicknameByCode.containsKey(code)) {
      _currentNicknameByCode[code] = clean;
      return false;
    }

    final previous = _currentNicknameByCode[code]!;
    if (previous == clean) return false;

    (_previousNicknamesByCode[code] ??= <String>{}).add(previous);
    _currentNicknameByCode[code] = clean;

    final joinedPrevious = _previousNicknamesByCode[code]?.join('、');
    var changed = false;
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].senderCode == code) {
        _messages[i] = _messages[i].copyWith(
          senderNickname: clean,
          previousNickname: joinedPrevious,
        );
        changed = true;
      }
    }
    if (changed) _emitList();
    return true;
  }

  /// 该短码当前记录的昵称（没有记录时返回 null）。
  String? nicknameOf(String code) => _currentNicknameByCode[code];

  /// 该短码的曾用名列表（没有记录时返回 null）。
  String? previousNicknamesOf(String code) =>
      _previousNicknamesByCode[code]?.join('、');

  // -------------------------------------------------------------- 去重

  /// `(senderId, seq)` 是否已见过。
  bool isDuplicate(int senderId, int seq) =>
      _seenKeys.contains('$senderId:$seq');

  /// 标记 `(senderId, seq)` 已处理，并按容量上限淘汰最旧的键。
  void markSeen(int senderId, int seq) {
    final key = '$senderId:$seq';
    if (_seenKeys.add(key)) {
      _seenKeyOrder.add(key);
      while (_seenKeyOrder.length > maxDeduplicationKeys) {
        _seenKeys.remove(_seenKeyOrder.removeAt(0));
      }
    }
  }

  // ------------------------------------------------------------ 消息写入

  /// 追加一条消息并按时间排序、按 [maxHistory] 截断，随后推流。
  ///
  /// 入站消息会累加未读数；本地消息（`isLocal`）不计未读。
  void append(ChatMessage message, {required bool isIncoming}) {
    _messages.add(message);
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    while (_messages.length > maxHistory) {
      _messages.removeAt(0);
    }

    if (!_messageController.isClosed) _messageController.add(message);
    _emitList();

    if (isIncoming) {
      _unreadCount++;
      _emitUnread();
    }
  }

  /// 按消息 ID 撤回。返回被撤回的消息，未找到时返回 null。
  ChatMessage? recall(String messageId) {
    final index = _messages.indexWhere((m) => m.messageId == messageId);
    if (index < 0) return null;
    final removed = _messages.removeAt(index);
    _emitList();
    return removed;
  }

  /// 该消息 ID 是否已存在（历史同步的幂等依据）。
  bool containsMessageId(String messageId) =>
      _messages.any((m) => m.messageId == messageId);

  /// 未读清零。
  void markAllRead() {
    if (_unreadCount == 0) return;
    _unreadCount = 0;
    _emitUnread();
  }

  /// 清空全部聊天状态（离房时调用）。身份映射一并重置——
  /// 同人识别只在本房间生命周期内有效。
  void clear() {
    _messages.clear();
    _seenKeys.clear();
    _seenKeyOrder.clear();
    _currentNicknameByCode.clear();
    _previousNicknamesByCode.clear();
    _unreadCount = 0;
    _emitList();
    _emitUnread();
  }

  /// 生成消息 ID。
  ///
  /// 形态 `<设备码>_<毫秒时间戳>_<seq>`，最坏长度由
  /// `ChatMessagePayload.fixedMessageIdBytes`（23 字节）约束；两侧必须一致，
  /// 否则 368 字节的文本预算推导就不成立。
  static String buildMessageId({
    required String code,
    required int timestampMs,
    required int seq,
  }) =>
      '${code}_${timestampMs}_$seq';

  bool get isDisposed => _messageController.isClosed;

  Future<void> dispose() async {
    await _messageController.close();
    await _listController.close();
    await _unreadController.close();
  }

  void _emitList() {
    if (_listController.isClosed) return;
    _listController.add(List.unmodifiable(_messages));
  }

  void _emitUnread() {
    if (_unreadController.isClosed) return;
    _unreadController.add(_unreadCount);
  }
}
