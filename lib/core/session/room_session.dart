import 'dart:async';
import 'dart:typed_data';
import '../audio/audio_io.dart';
import '../diagnostics/app_log.dart';
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import '../protocol/payloads/join_request.dart';
import '../protocol/payloads/leave.dart';
import '../protocol/payloads/ptt_state.dart';
import '../protocol/payloads/roster.dart';
import '../security/session_handshake.dart';
import '../transport/room_transport.dart';
import 'host_transfer.dart';
import 'member.dart';
import 'reconnect_controller.dart';

enum RoomMode { wifiFullDuplex, bluetoothPtt }
enum RoomState { idle, connecting, inRoom, reconnecting, disconnected }

/// Full Feature-Parity Central Room Session Controller.
class RoomSession {
  /// 全双工模式下没有 PTT 的「松手」事件，只能靠音频停流判断对方说完了。
  static const Duration _speakingTimeout = Duration(milliseconds: 400);

  /// 上行 Opus 码率。蓝牙房必须压低——BLE L2CAP 扛不住 24k 再乘以转发份数。
  static const int _wifiBitrate = 24000;
  static const int _bluetoothBitrate = 16000;

  final AudioIo audioIo;
  final String selfNickname;
  final Uint8List sessionToken;
  final RoomMode mode;

  /// 端到端 AES-GCM 安全信封编解码器。
  ///
  /// **默认为 null，即默认不加密。** 这是刻意的：已发布的 Kotlin 版 alpha.7
  /// 线上也没有默认开启强制加密，如果这一版单方面默认加密，升级到 alpha.8 的
  /// 用户就会和还没升级的人连不上。
  ///
  /// 帧类型 0x09/0x0a/0x0b 与旧版的 HANDSHAKE_HELLO/HANDSHAKE_CONFIRM/SEALED
  /// 一一对应，握手与密封的能力已经就位，等两版都具备后再协商开启。
  SecureFrameCodec? secureCodec;

  RoomState _state = RoomState.idle;
  bool _isHost = false;
  int _selfMemberId = 1;
  int _seq = 0;

  /// 传输层。房主转移要靠它取对端端点、接任监听、重连到新房主。
  RoomTransport? transport;

  /// 房主分配 joinOrder 用的单调计数器（房主自己是 0）。
  int _nextJoinOrder = 1;

  /// 最近一次收到的交接快照。房主猝死时全靠它自行迁移——
  /// 这正是旧版 HOST_SNAPSHOT(8) 存在的意义。
  HostTransferPlan? _cachedPlan;

  /// 见过的最大 joinOrder，用来丢弃迟到或被重放的旧计划。
  /// joinOrder 由房主单调分配，所以更新的计划一定不会更小。
  int _highestSeenJoinOrder = 0;

  /// 交接执行中，避免 2 秒一次的心跳把同一次迁移重复触发。
  bool _transferInProgress = false;

  final Map<int, Member> _members = {};

  /// 每个成员最后一次送到音频帧的时间，用来判断说话是否已经结束。
  final Map<int, DateTime> _lastAudioAt = {};
  Timer? _speakingWatchTimer;
  Timer? _heartbeatTimer;

  /// 麦克风/扬声器是否已经打开，[startAudio] 用它做幂等。
  bool _audioStarted = false;
  late ReconnectController _reconnectController;

  // UI Reactive Streams
  final _stateController = StreamController<RoomState>.broadcast();
  final _membersController = StreamController<List<Member>>.broadcast();
  final _waveController = StreamController<double>.broadcast();

  Stream<RoomState> get stateStream => _stateController.stream;
  Stream<List<Member>> get membersStream => _membersController.stream;
  Stream<double> get waveStream => _waveController.stream;

  RoomState get state => _state;
  bool get isHost => _isHost;
  bool get isMuted => audioIo.isMuted;
  bool isPttPressed = false;
  int get selfMemberId => _selfMemberId;
  List<Member> get members => _members.values.toList();
  bool get isFullDuplex => mode == RoomMode.wifiFullDuplex;

  RoomSession({
    required this.audioIo,
    required this.selfNickname,
    this.mode = RoomMode.wifiFullDuplex,
    Uint8List? sessionToken,
  }) : sessionToken = sessionToken ?? Uint8List(16) {
    _reconnectController = ReconnectController(
      onAttemptReconnect: _attemptReconnect,
      onMaxRetriesReached: () {
        _updateState(RoomState.disconnected);
      },
    );
  }

  /// Create a new room as Host.
  ///
  /// [startAudio] 为 false 时不开麦，需要之后手动调用 [startAudio]。
  /// 进房转场期间要用它把开麦推迟到动画结束——原因见 [startAudio] 的说明。
  Future<void> createRoom({bool startAudio = true}) async {
    _isHost = true;
    _selfMemberId = 1;
    _members.clear();
    _nextJoinOrder = 1;
    _cachedPlan = null;
    _highestSeenJoinOrder = 0;

    final selfMember = Member(
      memberId: _selfMemberId,
      nickname: selfNickname,
      sessionToken: sessionToken,
      joinOrder: 0, // 房主永远是资历最老的那个
      isHost: true,
    );
    _members[_selfMemberId] = selfMember;

    _updateState(RoomState.inRoom);
    _notifyMembers();

    if (startAudio) await this.startAudio();
    _startHeartbeat();
  }

  /// Join an existing room as Client.
  Future<void> joinRoom({bool startAudio = true}) async {
    _isHost = false;
    _selfMemberId = 0;
    _members.clear();

    _updateState(RoomState.connecting);

    final joinPayload = JoinRequestPayload(
      nickname: selfNickname,
      sessionToken: sessionToken,
    );
    final joinFrame = Frame(
      type: FrameType.joinReq,
      senderId: 0,
      seq: _nextSeq(),
      payload: joinPayload.encode(),
    );
    sendFrame(joinFrame);

    if (startAudio) await this.startAudio();
    _startHeartbeat();
  }

  /// 打开麦克风与扬声器。可重复调用，只生效一次。
  ///
  /// 之所以能和建房/加入分开：`AudioRecord` / `AudioTrack` 的构造、AEC/NS/AGC
  /// 挂载、前台服务启动全都发生在 **Android 主线程**上，一次上百毫秒。
  /// 如果压在 560ms 的进房转场里，UI 线程和平台线程互相抢，动画必然掉帧。
  /// 所以进房时先只建房、跑完动画再开麦。
  Future<void> startAudio() async {
    if (_audioStarted) return;
    _audioStarted = true;
    await _startAudioPipeline();
  }

  /// Process incoming binary frames
  Future<void> handleIncomingFrame(Frame frame) async {
    if (frame.type == FrameType.sealed) {
      if (secureCodec == null) {
        AppLog.warn('RoomSession', '收到加密帧但未配置安全编解码器，已丢弃');
        return;
      }
      try {
        final opened = await secureCodec!.open(frame);
        await handleIncomingFrame(opened);
      } catch (e) {
        AppLog.error('RoomSession', '解封加密帧失败，可能为伪造或重放帧', e);
      }
      return;
    }

    switch (frame.type) {
      case FrameType.audio:
        _handleAudioFrame(frame);
        break;
      case FrameType.joinReq:
        _handleJoinReq(frame);
        break;
      case FrameType.roster:
        _handleRoster(frame);
        break;
      case FrameType.pttState:
        _handlePttState(frame);
        break;
      case FrameType.heartbeat:
        _handleHeartbeat(frame);
        break;
      case FrameType.leave:
        _handleLeave(frame);
        break;
      case FrameType.hostHandover:
        await _handleHostHandover(frame);
        break;
      case FrameType.hostAnnounce:
        _handleHostAnnounce(frame);
        break;
      case FrameType.handshakeHello:
      case FrameType.handshakeConfirm:
      case FrameType.sealed:
        break;
    }
  }

  void _handleAudioFrame(Frame frame) {
    if (frame.senderId == _selfMemberId) return;

    // 只收在册成员的音频：否则任何陌生或伪造的 senderId 都能在原生侧
    // 凭空建出一路抖动缓冲和解码器，且永远不会被回收。
    final sender = _members[frame.senderId];
    if (sender == null) return;

    // 整帧原样交给原生播放管线：那边从帧头解析发送方与序号，
    // 分流进各自的抖动缓冲，再解码混音。
    audioIo.submitRemoteFrame(frame.encode());

    _lastAudioAt[frame.senderId] = DateTime.now();
    if (!sender.isSpeaking) {
      sender.isSpeaking = true;
      _notifyMembers();
    }
  }

  /// 全双工模式下把已经停止送音频的成员的「正在说话」熄灭。
  ///
  /// 缺了这一步，WiFi 房里的说话指示灯一旦亮起就永远不会灭——
  /// 只有 PTT 帧会复位它，而全双工模式根本不发 PTT 帧。
  void _expireSpeakingStates() {
    if (!isFullDuplex) return; // PTT 模式由 pttState 帧驱动，不能靠音频超时

    final now = DateTime.now();
    var changed = false;

    for (final member in _members.values) {
      if (member.memberId == _selfMemberId) continue;
      if (!member.isSpeaking) continue;

      final last = _lastAudioAt[member.memberId];
      if (last == null || now.difference(last) > _speakingTimeout) {
        member.isSpeaking = false;
        changed = true;
      }
    }

    if (changed) _notifyMembers();
  }

  void _handleJoinReq(Frame frame) {
    if (!_isHost) return;
    final payload = JoinRequestPayload.decode(frame.payload);
    if (payload == null) return;

    // Check if rejoining with existing token
    int allocatedId = 0;
    for (final entry in _members.entries) {
      if (entry.value.nickname == payload.nickname) {
        allocatedId = entry.key;
        break;
      }
    }

    if (allocatedId == 0) {
      int newId = 2;
      while (_members.containsKey(newId) && newId <= 6) {
        newId++;
      }
      if (newId > 6) return; // Room is full (max 6)
      allocatedId = newId;
    }

    final existing = _members[allocatedId];
    _members[allocatedId] = Member(
      memberId: allocatedId,
      nickname: payload.nickname,
      sessionToken: payload.sessionToken,
      // 重连回来的老成员保留原有资历，不能因为断线重连就变成最年轻的。
      joinOrder: existing?.joinOrder ?? _nextJoinOrder++,
      endpoint: existing?.endpoint ?? '',
    );

    _broadcastRoster();
    _notifyMembers();
  }

  void _handleRoster(Frame frame) {
    final payload = RosterPayload.decode(frame.payload);
    if (payload == null) return;

    _members.clear();
    for (final rm in payload.members) {
      _members[rm.memberId] = Member(
        memberId: rm.memberId,
        nickname: rm.nickname,
        isHost: rm.isHost,
        isMuted: rm.isMuted,
        isSpeaking: rm.isSpeaking,
      );
      if (rm.nickname == selfNickname && !isHost) {
        _selfMemberId = rm.memberId;
        transport?.updateSelfMemberId(_selfMemberId);
      }
    }

    if (_state != RoomState.inRoom) {
      _updateState(RoomState.inRoom);
    }

    // 名单换了以后，已经不在房里的人的音频流留着只会占内存。
    final gone =
        _lastAudioAt.keys.where((id) => !_members.containsKey(id)).toList();
    for (final id in gone) {
      _lastAudioAt.remove(id);
      audioIo.removeRemoteMember(id);
    }

    _notifyMembers();
  }

  void _handlePttState(Frame frame) {
    final payload = PttStatePayload.decode(frame.payload);
    if (payload == null) return;

    final member = _members[frame.senderId];
    if (member != null) {
      member.isSpeaking = payload.isPressed;
      _notifyMembers();
    }
  }

  void _handleHeartbeat(Frame frame) {
    final member = _members[frame.senderId];
    if (member != null) {
      member.lastActiveAt = DateTime.now();
    }
  }

  void _handleLeave(Frame frame) {
    _members.remove(frame.senderId);
    _lastAudioAt.remove(frame.senderId);
    audioIo.removeRemoteMember(frame.senderId);
    _notifyMembers();

    if (_isHost) {
      _broadcastRoster();
    }
  }

  /// 收到交接帧（0x07）：立刻执行迁移。
  Future<void> _handleHostHandover(Frame frame) async {
    final plan = _decodePlan(frame, '交接帧');
    if (plan == null) return;
    if (!_isPlanFresh(plan)) return;

    _cachedPlan = plan;
    await _runTransfer(plan);
  }

  /// 收到交接快照（0x08）：只缓存，不改变当前房主。
  ///
  /// 快照是房主定期广播的「万一我挂了，你们照这个迁」。真正触发迁移的是
  /// 交接帧或房主超时，所以这里绝不能动 isHost——否则一条迟到的快照
  /// 就能把现任房主顶下去。
  void _handleHostAnnounce(Frame frame) {
    if (_isHost) return;
    final plan = _decodePlan(frame, '交接快照');
    if (plan == null) return;
    if (!_isPlanFresh(plan)) return;

    _cachedPlan = plan;
  }

  HostTransferPlan? _decodePlan(Frame frame, String what) {
    try {
      return HostTransferCodec.decode(frame.payload);
    } catch (e) {
      AppLog.warn('RoomSession', '收到无法解析的$what，已忽略', e);
      return null;
    }
  }

  bool _isPlanFresh(HostTransferPlan plan) {
    final maxOrder =
        plan.members.map((m) => m.joinOrder).reduce((a, b) => a > b ? a : b);
    if (maxOrder < _highestSeenJoinOrder) return false;
    _highestSeenJoinOrder = maxOrder;
    return true;
  }

  /// 房主超时后自动迁移。
  void checkHostFailover() {
    if (_isHost || _transferInProgress || _state != RoomState.inRoom) return;

    final currentHost = _members.values.cast<Member?>().firstWhere(
          (m) => m?.isHost == true,
          orElse: () => null,
        );

    // 如果刚进房间名单里还没标出房主，先等待名单帧，不误判失联
    if (currentHost == null) return;

    final now = DateTime.now();
    final hostAlive =
        now.difference(currentHost.lastActiveAt).inMilliseconds < 6000;
    if (hostAlive) return;

    final plan = _cachedPlan;
    if (plan == null) {
      // 没有快照就无从得知谁该接任、别人在哪，只能散会。
      AppLog.warn('RoomSession', '房主已失联，且没有可用的交接快照，房间解散');
      _updateState(RoomState.disconnected);
      return;
    }

    AppLog.info('RoomSession', '房主已失联，按快照迁移到 ${plan.successor.nickname}');
    _transferInProgress = true;
    _runTransfer(plan).whenComplete(() => _transferInProgress = false);
  }

  Future<void> _runTransfer(HostTransferPlan plan) async {
    final t = transport;
    if (t == null || !t.supportsHostTransfer) {
      AppLog.error('RoomSession', '当前房型不支持房主转移');
      return;
    }
    if (plan.successorId == _selfMemberId) {
      await _becomeHost(plan, t);
    } else {
      await _followNewHost(plan, t);
    }
  }

  Future<void> _becomeHost(HostTransferPlan plan, RoomTransport t) async {
    final seed = HostTransferSeed.from(plan);
    _updateState(RoomState.reconnecting);

    if (!await t.becomeHost()) {
      AppLog.error('RoomSession', '接任房主失败：无法开始监听');
      _updateState(RoomState.disconnected);
      return;
    }

    // 交接后所有人的成员号都会变：继任者取 1，其余按 joinOrder 顺延。
    // 传输层必须跟着更新，否则语音会被转发到错的端点。
    _members.clear();
    _lastAudioAt.clear();
    for (final m in seed.members) {
      final id = m.newId + 1; // seed 里继任者是 0，房主统一用 1
      _members[id] = Member(
        memberId: id,
        nickname: m.nickname,
        joinOrder: m.joinOrder,
        endpoint: m.endpoint,
        isHost: id == 1,
      );
    }

    _selfMemberId = 1;
    _nextJoinOrder = seed.nextJoinOrder;
    _isHost = true;
    t.updateSelfMemberId(_selfMemberId);

    _updateState(RoomState.inRoom);
    _broadcastRoster();
    _notifyMembers();
    AppLog.info('RoomSession', '已接任房主，房内 ${_members.length} 人');
  }

  Future<void> _followNewHost(HostTransferPlan plan, RoomTransport t) async {
    _isHost = false;
    _updateState(RoomState.reconnecting);

    if (!await t.reconnectToHost(plan.successor.endpoint)) {
      AppLog.error('RoomSession', '重连新房主失败');
      _updateState(RoomState.disconnected);
      return;
    }

    // 成员号由新房主重新分配，所以重新走一次入房；音频管线不重启，
    // 否则会有一段可听见的断音。
    await joinRoom(startAudio: false);
    AppLog.info('RoomSession', '已跟随新房主 ${plan.successor.nickname} 重连');
  }

  /// 用当前成员表和传输层已知的端点组装一份交接计划。
  ///
  /// 端点未知的成员不能当继任者——别人找不到他。
  HostTransferPlan? _buildTransferPlan({int? preferredSuccessorId}) {
    final known = transport?.peerEndpoints ?? const <int, String>{};
    final candidates = <TransferCandidate>[];

    for (final m in _members.values) {
      if (m.memberId == _selfMemberId) continue; // 房主自己不是继任候选
      final endpoint = known[m.memberId] ?? m.endpoint;
      if (endpoint.trim().isEmpty) continue;
      m.endpoint = endpoint;
      candidates.add(TransferCandidate(
        memberId: m.memberId,
        joinOrder: m.joinOrder,
        nickname: m.nickname,
        endpoint: endpoint,
      ));
    }

    if (candidates.isEmpty) return null;
    if (preferredSuccessorId == null) return HostElection.plan(candidates);

    if (!candidates.any((c) => c.memberId == preferredSuccessorId)) return null;
    try {
      return HostTransferPlan(
        successorId: preferredSuccessorId,
        members: candidates
            .map((c) => HostTransferMember(
                  memberId: c.memberId,
                  joinOrder: c.joinOrder,
                  nickname: c.nickname,
                  endpoint: c.endpoint,
                ))
            .toList(),
      );
    } catch (e) {
      AppLog.error('RoomSession', '交接计划校验未通过', e);
      return null;
    }
  }

  /// 房主定期广播交接快照，让每个人手里都有「房主没了该怎么办」的答案。
  Future<void> _broadcastSnapshot() async {
    if (!_isHost) return;
    if (transport?.supportsHostTransfer != true) return;

    final plan = _buildTransferPlan();
    if (plan == null) return;

    _cachedPlan = plan;
    await sendFrame(Frame(
      type: FrameType.hostAnnounce,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: HostTransferCodec.encode(plan),
    ));
  }

  void _broadcastRoster() {
    if (!_isHost) return;

    final rosterMembers = _members.values.map((m) {
      int flags = 0;
      if (m.isHost) flags |= 0x01;
      if (m.isMuted) flags |= 0x02;
      if (m.isSpeaking) flags |= 0x04;
      return RosterMember(memberId: m.memberId, flags: flags, nickname: m.nickname);
    }).toList();

    final payload = RosterPayload(hostId: _selfMemberId, members: rosterMembers);
    final frame = Frame(
      type: FrameType.roster,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: payload.encode(),
    );
    sendFrame(frame);
  }

  Future<void> _startAudioPipeline() async {
    // 重连会再次走到这里。不先停掉上一轮的采集，回调会叠加成两份，
    // 每帧音频都会被发送两遍。
    await audioIo.stopCapture();
    await audioIo.clearRemoteMembers();

    await audioIo.startCapture(
      (opusPacket, level) {
        // 全双工：没静音就一直发；PTT：还要按住才发。
        final shouldTransmit = isFullDuplex
            ? !audioIo.isMuted
            : (!audioIo.isMuted && isPttPressed);
        if (!shouldTransmit) return;

        if (!_waveController.isClosed) {
          _waveController.add(level);
        }

        sendFrame(Frame(
          type: FrameType.audio,
          senderId: _selfMemberId,
          seq: _nextSeq(),
          payload: opusPacket,
        ));
      },
      bitrateBps: isFullDuplex ? _wifiBitrate : _bluetoothBitrate,
    );

    // 播放不再需要 Dart 定时器：抖动缓冲、解码、混音、送扬声器全在原生侧，
    // 由 AudioTrack 的写阻塞天然定速（原来的 Timer.periodic(20ms) 有调度漂移）。
    // 这里只剩「谁还在说话」的超时判定，100ms 一次足够。
    _speakingWatchTimer?.cancel();
    _speakingWatchTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _expireSpeakingStates(),
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final frame = Frame(
        type: FrameType.heartbeat,
        senderId: _selfMemberId,
        seq: _nextSeq(),
        payload: Uint8List(0),
      );
      sendFrame(frame);

      // 房主定期广播交接快照；成员则检查房主是不是已经失联。
      // 这一步之前被漏掉了，导致房主掉线后没有任何人接管。
      if (_isHost) {
        _broadcastSnapshot();
      } else {
        checkHostFailover();
      }
    });
  }

  /// PTT 按住/松开切换。
  void setPtt(bool isPressed) {
    isPttPressed = isPressed;
    final self = _members[_selfMemberId];
    if (self != null) {
      self.isSpeaking = isPressed;
      _notifyMembers();
    }

    final payload = PttStatePayload(isPressed: isPressed);
    final frame = Frame(
      type: FrameType.pttState,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: payload.encode(),
    );
    sendFrame(frame);
  }

  void toggleMute() {
    final nextMuted = !audioIo.isMuted;
    audioIo.setMuted(nextMuted);
    final self = _members[_selfMemberId];
    if (self != null) {
      self.isMuted = nextMuted;
      _notifyMembers();
    }
  }

  void setSpeakerphone(bool enabled) {
    audioIo.setSpeakerphone(enabled);
  }

  Future<bool> _attemptReconnect() async {
    _updateState(RoomState.reconnecting);
    // 不重开麦：音频管线与传输层是独立的，重连期间它一直在跑，
    // 重启一次反而会造成一段可听见的断音。
    await joinRoom(startAudio: false);
    return _state == RoomState.inRoom;
  }

  void triggerDisconnect() {
    _updateState(RoomState.reconnecting);
    _reconnectController.start();
  }

  /// Hook for network transmission
  void Function(Frame frame)? onSendFrame;

  Future<void> sendFrame(Frame frame) async {
    Frame outFrame = frame;
    if (secureCodec != null &&
        frame.type != FrameType.sealed &&
        frame.type != FrameType.handshakeHello &&
        frame.type != FrameType.handshakeConfirm) {
      try {
        outFrame = await secureCodec!.seal(frame);
      } catch (e) {
        AppLog.error('RoomSession', '密封加密帧失败，已放弃发送', e);
      }
    }
    onSendFrame?.call(outFrame);
  }

  /// 房主主动把房主身份转移给目标成员。
  Future<void> transferHost(int targetMemberId) async {
    if (!_isHost) return;

    final t = transport;
    if (t == null || !t.supportsHostTransfer) {
      AppLog.error('RoomSession', '当前房型不支持房主转移');
      return;
    }

    final target = _members[targetMemberId];
    if (target == null) return;

    final plan = _buildTransferPlan(preferredSuccessorId: targetMemberId);
    if (plan == null) {
      AppLog.error(
        'RoomSession',
        '还不知道「${target.nickname}」的连接地址，等对方说过话后再试',
      );
      return;
    }

    await sendFrame(Frame(
      type: FrameType.hostHandover,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: HostTransferCodec.encode(plan),
    ));
    AppLog.info('RoomSession', '把房主转移给「${target.nickname}」');

    // 留一点时间让交接帧真的发出去，再自己降为普通成员重连过去。
    await Future.delayed(const Duration(milliseconds: 300));
    _transferInProgress = true;
    try {
      await _followNewHost(plan, t);
    } finally {
      _transferInProgress = false;
    }
  }

  bool get useBuiltinMic => audioIo.useBuiltinMic;

  void setUseBuiltinMic(bool useBuiltin) {
    audioIo.setUseBuiltinMic(useBuiltin);
  }

  Future<void> leave() async {
    final leavePayload = LeavePayload();
    final frame = Frame(
      type: FrameType.leave,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: leavePayload.encode(),
    );
    sendFrame(frame);

    _speakingWatchTimer?.cancel();
    _speakingWatchTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _audioStarted = false;
    _reconnectController.cancel();

    await audioIo.stopCapture();
    await audioIo.stopPlayback();
    await audioIo.clearRemoteMembers();
    await transport?.stop();

    _members.clear();
    _lastAudioAt.clear();
    _cachedPlan = null;
    _highestSeenJoinOrder = 0;
    _transferInProgress = false;
    _nextJoinOrder = 1;
    _updateState(RoomState.idle);
    _notifyMembers();
  }

  int _nextSeq() {
    _seq = (_seq + 1) & 0xFFFF;
    return _seq;
  }

  void _updateState(RoomState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void _notifyMembers() {
    if (!_membersController.isClosed) {
      _membersController.add(_members.values.toList());
    }
  }

  /// 必须 await。
  ///
  /// 原来是同步调用 `leave()` 之后立刻 close 三个 controller：`leave()` 跑到
  /// 第一个 await（stopCapture）就挂起了，等它恢复执行时再去 `_updateState`
  /// 和 `_notifyMembers`，写的已经是关掉的 controller，直接抛 StateError。
  Future<void> dispose() async {
    await leave();
    await _stateController.close();
    await _membersController.close();
    await _waveController.close();
  }
}
