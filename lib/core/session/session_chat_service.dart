import '../clock.dart';
import '../diagnostics/app_log.dart';
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import '../protocol/payloads/chat_delete.dart';
import '../protocol/payloads/chat_message.dart';
import '../protocol/payloads/chat_sync.dart';
import 'chat_message.dart';
import 'device_code.dart';
import 'member.dart';
import 'session_chat_hub.dart';

/// 房间文字聊天的**帧层业务**，从 `RoomSession` 外提。
///
/// 为什么单独成类：`SessionChatHub` 管的是本地状态与规则（历史表、去重窗口、
/// 撤回），但「聊天帧怎么解、怎么鉴权、什么时候回发」这一层仍留在会话里，
/// 占掉近 250 行——改一句文案也要在话权、房主选举、心跳之间穿行。这里把
/// 编解码 + 鉴权 + 发帧收成一个对象，会话只剩转发与成员表查询。
///
/// 职责边界：
///   - 解码/编码聊天族帧（chat / chatSync / chatDelete），维护本地历史写入
///   - 鉴权：发送者是否在册、历史同步是否来自房主、撤回是否本人所为
///   - **不**持有成员表（用注入的 [memberOf] 查询）、**不**碰传输层
///     （用注入的 [send] 发帧）、**不**管未读数之外的 UI 状态
class SessionChatService {
  SessionChatService({
    required SessionChatHub hub,
    required this.selfNickname,
    required this.clock,
    required int Function() selfMemberId,
    required bool Function() isHost,
    required bool Function() isInRoom,
    required bool Function() acceptsHistorySync,
    required Member? Function(int memberId) memberOf,
    required int Function() nextSeq,
    required Future<void> Function(Frame frame) send,
  })  : _hub = hub,
        _selfMemberId = selfMemberId,
        _isHost = isHost,
        _isInRoom = isInRoom,
        _acceptsHistorySync = acceptsHistorySync,
        _memberOf = memberOf,
        _nextSeq = nextSeq,
        _send = send;

  final SessionChatHub _hub;

  /// 本机会话昵称（成员表里查不到自己时的兜底）。
  final String selfNickname;

  /// 消息时间戳与「缺省时间」用的时钟，可注入。
  final Clock clock;

  final int Function() _selfMemberId;
  final bool Function() _isHost;
  final bool Function() _isInRoom;

  /// 是否处于可接收历史同步的状态（`inRoom` 或正在入房）。
  final bool Function() _acceptsHistorySync;
  final Member? Function(int memberId) _memberOf;
  final int Function() _nextSeq;
  final Future<void> Function(Frame frame) _send;

  /// 发送一条文字消息：发帧 + 本地立即回显。
  ///
  /// 未进房或文本为空时抛错而不是静默丢弃——这两种都是调用方的程序错误，
  /// 静默丢弃只会让 UI 看起来「点了没反应」。
  Future<void> sendText(String text) async {
    if (!_isInRoom()) {
      throw StateError('Cannot send chat message when not in room.');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError(
          'Chat message text cannot be empty or whitespace-only.');
    }

    final selfId = _selfMemberId();
    final fullNickname = _memberOf(selfId)?.nickname ?? selfNickname;
    final rawCode = DeviceCode.split(fullNickname).$2 ?? DeviceCode.current;
    final code = DeviceCode.toNumeric(rawCode);
    final now = clock.now();
    final timestampMs = now.millisecondsSinceEpoch;
    final seq = _nextSeq();
    final messageId = SessionChatHub.buildMessageId(
      code: code,
      timestampMs: timestampMs,
      seq: seq,
    );

    // ChatMessagePayload 会校验共享文本预算，超长直接抛出 ArgumentError
    final frame = Frame(
      type: FrameType.chat,
      senderId: selfId,
      seq: seq,
      payload: ChatMessagePayload(
        text: trimmed,
        timestampMs: timestampMs,
        senderCode: code,
      ).encode(),
    );

    // 记录本机发送键值，防止因广播回送导致重复追加
    _hub.markSeen(selfId, seq);

    // 经由会话的 sendFrame 发送（配置了 secureCodec 时会自动加密为 sealed 帧）
    await _send(frame);

    _hub.recordIdentity(code, fullNickname);
    _hub.append(
      ChatMessage(
        messageId: messageId,
        senderId: selfId,
        senderCode: code,
        senderNickname:
            _hub.nicknameOf(code) ?? DeviceCode.split(fullNickname).$1,
        previousNickname: _hub.previousNicknamesOf(code),
        seq: seq,
        text: trimmed,
        timestamp: now,
        isLocal: true,
        isHost: _isHost(),
      ),
      isIncoming: false,
    );
  }

  /// 处理对端聊天帧。
  void handleChatFrame(Frame frame) {
    if (!_isInRoom()) return;

    // 1. 过滤本机回送帧
    if (frame.senderId == _selfMemberId()) return;

    // 2. 过滤未在册成员的帧（鉴权留在这一层：hub 不认识成员表）
    final sender = _memberOf(frame.senderId);
    if (sender == null) {
      AppLog.warn('RoomSession', '收到未在册成员 #${frame.senderId} 的聊天帧，已忽略');
      return;
    }

    // 3. 有界去重检查 (senderId, seq)
    if (_hub.isDuplicate(frame.senderId, frame.seq)) return;
    _hub.markSeen(frame.senderId, frame.seq);

    // 4. 解码 Payload
    final payload = ChatMessagePayload.decode(frame.payload);
    if (payload == null) {
      AppLog.warn('RoomSession', '来自成员 #${frame.senderId} 的聊天帧载荷格式损坏，已忽略');
      return;
    }

    // 5. 身份与曾用名关联
    final split = DeviceCode.split(sender.nickname);
    final senderCode =
        (payload.senderCode != '0000' && payload.senderCode.isNotEmpty)
            ? DeviceCode.toNumeric(payload.senderCode)
            : (split.$2 ?? 'M${frame.senderId}');
    _hub.recordIdentity(senderCode, sender.nickname);

    final timestamp = payload.timestampMs != 0
        ? DateTime.fromMillisecondsSinceEpoch(payload.timestampMs)
        : clock.now();

    // 6. 组装并追加消息
    _hub.append(
      ChatMessage(
        messageId: SessionChatHub.buildMessageId(
          code: senderCode,
          timestampMs: timestamp.millisecondsSinceEpoch,
          seq: frame.seq,
        ),
        senderId: frame.senderId,
        senderCode: senderCode,
        senderNickname: _hub.nicknameOf(senderCode) ?? split.$1,
        previousNickname: _hub.previousNicknamesOf(senderCode),
        seq: frame.seq,
        text: payload.text,
        timestamp: timestamp,
        isLocal: false,
        isHost: sender.isHost,
      ),
      isIncoming: true,
    );
  }

  /// 房主向新加入成员补发现存的历史聊天记录。
  ///
  /// 不 await 发帧：补发可能有上百条，等完再让新成员进房只会拖慢入房；帧本身
  /// 由传输层按序送出，顺序不会乱。
  void syncHistoryTo(int targetMemberId) {
    if (!_isHost()) return;
    for (final msg in _hub.messages) {
      if (msg.isRecalled) continue;
      _send(Frame(
        type: FrameType.chatSync,
        senderId: _selfMemberId(),
        seq: _nextSeq(),
        payload: ChatSyncPayload(
          targetMemberId: targetMemberId,
          senderId: msg.senderId,
          senderCode: msg.senderCode,
          timestampMs: msg.timestamp.millisecondsSinceEpoch,
          messageId: msg.messageId,
          nickname: msg.senderNickname,
          text: msg.text,
        ).encode(),
      ));
    }
  }

  /// 处理历史同步帧。
  void handleChatSyncFrame(Frame frame) {
    if (!_acceptsHistorySync()) return;
    final payload = ChatSyncPayload.decode(frame.payload);
    if (payload == null) return;

    // 历史同步是房主的特权帧：payload 里的 senderId/senderCode 都是自报的，
    // 不校验实际发送者的话，任何成员都能伪造「历史消息」冒充他人发言。
    final sender = _memberOf(frame.senderId);
    if (sender == null || !sender.isHost) {
      AppLog.warn('RoomSession', '拒绝来自非房主 #${frame.senderId} 的历史同步帧');
      return;
    }

    // 仅接收定向发给本机或广播的历史同步帧
    if (payload.targetMemberId != 0 &&
        payload.targetMemberId != _selfMemberId()) {
      return;
    }

    // 根据 messageId 去重，防止重复同步
    if (_hub.containsMessageId(payload.messageId)) return;

    _hub.recordIdentity(payload.senderCode, payload.nickname);

    _hub.append(
      ChatMessage(
        messageId: payload.messageId,
        senderId: payload.senderId,
        senderCode: payload.senderCode,
        senderNickname: _hub.nicknameOf(payload.senderCode) ?? payload.nickname,
        previousNickname: _hub.previousNicknamesOf(payload.senderCode),
        seq: 0,
        text: payload.text,
        timestamp: DateTime.fromMillisecondsSinceEpoch(payload.timestampMs),
        isLocal: payload.senderCode == DeviceCode.current,
        isHost: payload.senderId == 1,
      ),
      // 补发的历史不计未读：它是进房时的一次性回填，不该弹红点。
      isIncoming: false,
    );
  }

  /// 撤回 / 为所有人删除自己发送的消息。
  Future<void> recall(String messageId) async {
    final target =
        _hub.messages.where((m) => m.messageId == messageId).firstOrNull;
    if (target == null) return;

    final myCode = DeviceCode.toNumeric(
        DeviceCode.split(selfNickname).$2 ?? DeviceCode.current);
    // 权限校验：只能删除自己发送的消息
    if (!target.isLocal && DeviceCode.toNumeric(target.senderCode) != myCode) {
      throw StateError('Cannot delete messages sent by other members.');
    }

    _hub.recall(messageId);

    await _send(Frame(
      type: FrameType.chatDelete,
      senderId: _selfMemberId(),
      seq: _nextSeq(),
      payload:
          ChatDeletePayload(senderCode: myCode, messageId: messageId).encode(),
    ));
  }

  /// 处理撤回帧。
  void handleChatDeleteFrame(Frame frame) {
    final payload = ChatDeletePayload.decode(frame.payload);
    if (payload == null) return;
    if (!_hub.containsMessageId(payload.messageId)) return;

    // 权限校验：只比对 payload 里的 senderCode 不够——设备码在聊天界面
    // 可见且仅 3 位数字，任何成员都能冒填。改为取「帧的实际发送者」在
    // 名单里的设备码与消息作者比对，冒用他人短码的撤回请求一律无效。
    final sender = _memberOf(frame.senderId);
    if (sender == null) {
      AppLog.warn('RoomSession', '收到不在册成员 #${frame.senderId} 的撤回请求，已忽略');
      return;
    }
    final senderCode = DeviceCode.toNumeric(
      DeviceCode.split(sender.nickname).$2 ?? 'M${frame.senderId}',
    );
    final target = _hub.messages
        .where((m) => m.messageId == payload.messageId)
        .firstOrNull;
    if (target == null) return;

    if (senderCode != DeviceCode.toNumeric(target.senderCode)) {
      AppLog.warn(
        'RoomSession',
        '收到非法撤回请求：发起方 #${frame.senderId}（$senderCode）试图撤回 ${target.senderCode} 的消息',
      );
      return;
    }

    _hub.recall(payload.messageId);
  }
}
