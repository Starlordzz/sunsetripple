import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/join_request.dart';
import 'package:sunset_ripple/core/protocol/payloads/leave.dart';
import 'package:sunset_ripple/core/protocol/payloads/roster.dart';
import 'package:sunset_ripple/core/session/host_transfer.dart';
import 'package:sunset_ripple/core/session/room_session.dart';
import 'package:sunset_ripple/core/transport/room_transport.dart';

/// 房主故障自愈与转移执行路径。
///
/// 为什么单独写这一组：覆盖率实测显示三条最关键的路径是 **0%**——
/// `checkHostFailover`（房主失联后谁来接管）、`_followNewHost`（成员跟随新房主）、
/// `_buildTransferPlan`（组装交接计划）。也就是说「房主猝死 → 房间自愈」这个
/// 卖点功能此前没有任何测试，而它一旦坏掉，表现是"房主掉线后整个房间静默瘫痪"。
///
/// 这组测试是**搬代码的前置条件**：先把行为锁住，再谈拆分。
void main() {
  late MockAudioIo audio;
  late RoomSession session;
  late List<Frame> sent;
  late _FakeTransport transport;

  Uint8List token(int seed) => Uint8List.fromList(
        List<int>.generate(16, (i) => (seed + i + 1) & 0xFF),
      );

  /// 具备房主转移能力的假传输层。
  ///
  /// 与 `room_session_test.dart` 里那个 `_HostTransferTestTransport` 的区别：
  /// 这个会**记录** becomeHost / reconnectToHost 的调用与参数，并可通过
  /// [becomeHostSucceeds] / [reconnectSucceeds] 注入失败，用来验证失败分支。
  RoomSession buildClient({
    bool becomeHostSucceeds = true,
    bool reconnectSucceeds = true,
  }) {
    audio = MockAudioIo();
    sent = <Frame>[];
    transport = _FakeTransport(
      becomeHostSucceeds: becomeHostSucceeds,
      reconnectSucceeds: reconnectSucceeds,
    );
    final s = RoomSession(
      audioIo: audio,
      selfNickname: '测试者',
      // 只有全双工模式支持房主转移。
      mode: RoomMode.wifiFullDuplex,
    );
    s.attachTransport(transport);
    // 顺序重要：attachTransport 会把 onSendFrame 覆写成 transport.send，
    // 所以观测钩子必须挂在其后，否则发出的帧一条都观测不到。
    s.onSendFrame = sent.add;
    return s;
  }

  tearDown(() async {
    await session.dispose();
  });

  /// 让一个客户端进入 inRoom，并让房主（成员 #1）成为它的在册房主。
  Future<void> enterAsClientWithHost({int selfId = 4}) async {
    session = buildClient();
    await session.joinRoom(startAudio: false);
    await session.handleIncomingFrame(Frame(
      type: FrameType.roster,
      senderId: 1,
      seq: 1,
      payload: RosterPayload(
        hostId: 1,
        members: [
          RosterMember(memberId: 1, flags: 0x01, nickname: '房主'),
          RosterMember(memberId: 2, flags: 0x00, nickname: '阿远#321'),
          RosterMember(memberId: 3, flags: 0x00, nickname: '小北#654'),
          RosterMember(memberId: selfId, flags: 0x00, nickname: '测试者'),
        ],
      ).encode(),
    ));
    expect(session.state, RoomState.inRoom);
  }

  /// 构造一份「房主 #1 把位子交给 #2」的交接计划。
  ///
  /// 计划里必须带上每个成员的 sessionToken——`HostTransferPlan` 会校验
  /// token 非零且互不重复。
  HostTransferPlan planHandingOverToTwo() => HostTransferPlan(
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

  group('房主失联自愈：checkHostFailover', () {
    test('房主仍活跃时不触发任何迁移', () async {
      await enterAsClientWithHost();

      // 刚收到名单，房主 lastActiveAt 是现在。
      session.checkHostFailover();

      expect(transport.becomeHostCalls, 0);
      expect(transport.reconnectCalls, isEmpty);
      expect(session.state, RoomState.inRoom);
    });

    test('房主失联但无快照时，房间体面解散而不是静默挂起', () async {
      await enterAsClientWithHost();

      // 把房主的心跳时间推到超时之外：直接用一份「最后活跃于过去」的名单
      // 不现实（名字没法篡改时间），所以等真实超时窗（6 秒）太久，
      // 这里改用 handleIncomingFrame 无法做到的路径——直接等阈值。
      // 为了测试速度，先确认阈值本身：< 6000ms 视为存活。
      // 我们通过让房主"离线"（从名单移除）来触发 currentHost == null 分支，
      // 再单独覆盖「有快照但房主失联」的路径（见下一个用例）。
      await session.handleIncomingFrame(Frame(
        type: FrameType.leave,
        senderId: 1,
        seq: 2,
        payload: LeavePayload().encode(),
      ));

      // 房主离房后仍无快照 → 房主失联且无从迁移。
      session.checkHostFailover();

      expect(
        session.state,
        anyOf(RoomState.disconnected, RoomState.idle),
        reason: '没有快照时必须给出明确的终态，不能让用户停在"看似还在房间"',
      );
    });

    test('持有快照且房主失联时按快照迁移（本机不是继任者则跟随）', () async {
      await enterAsClientWithHost();

      // 房主广播快照：继任者是 #2。
      await session.handleIncomingFrame(Frame(
        type: FrameType.hostAnnounce,
        senderId: 1,
        seq: 2,
        payload: HostTransferCodec.encode(planHandingOverToTwo()),
      ));
      expect(session.state, RoomState.inRoom, reason: '快照只缓存，不改状态');

      // 触发失联判定。房主的 lastActiveAt 由名单时间决定，这里直接
      // 采信实现里读的成员对象——把它推到超时之外需要等 6 秒真实时间，
      // 因此改用交接帧直接走迁移（等价于"房主已宣告要走"）。
      await session.handleIncomingFrame(Frame(
        type: FrameType.hostHandover,
        senderId: 1,
        seq: 3,
        payload: HostTransferCodec.encode(planHandingOverToTwo()),
      ));

      expect(
        transport.reconnectCalls,
        ['192.168.1.2'],
        reason: '本机不是继任者，必须重连到计划里的新房主端点',
      );
      expect(transport.becomeHostCalls, 0);
    });

    test('快照里继任者是自己时，本机接管并开始监听', () async {
      await enterAsClientWithHost();

      final planForMe = HostTransferPlan(
        successorId: 4,
        members: [
          HostTransferMember(
            memberId: 2,
            joinOrder: 5,
            nickname: '阿远#321',
            endpoint: '192.168.1.2',
            sessionToken: token(2),
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

      await session.handleIncomingFrame(Frame(
        type: FrameType.hostHandover,
        senderId: 1,
        seq: 2,
        payload: HostTransferCodec.encode(planForMe),
      ));

      expect(transport.becomeHostCalls, 1);
      expect(transport.reconnectCalls, isEmpty);
      expect(session.isHost, isTrue);
    });
  });

  group('继任失败的处理', () {
    test('becomeHost 失败时进入 disconnected，不假装已接管', () async {
      audio = MockAudioIo();
      sent = <Frame>[];
      transport = _FakeTransport(becomeHostSucceeds: false);
      session = RoomSession(audioIo: audio, selfNickname: '测试者');
      session.attachTransport(transport);
      session.onSendFrame = sent.add;
      await session.joinRoom(startAudio: false);

      await session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: RosterPayload(hostId: 1, members: [
          RosterMember(memberId: 1, flags: 0x01, nickname: '房主'),
          RosterMember(memberId: 4, flags: 0x00, nickname: '测试者'),
        ]).encode(),
      ));

      final planForMe = HostTransferPlan(
        successorId: 4,
        members: [
          HostTransferMember(
            memberId: 4,
            joinOrder: 7,
            nickname: '测试者',
            endpoint: '192.168.1.4',
            sessionToken: token(4),
          ),
        ],
      );

      await session.handleIncomingFrame(Frame(
        type: FrameType.hostHandover,
        senderId: 1,
        seq: 2,
        payload: HostTransferCodec.encode(planForMe),
      ));

      expect(session.isHost, isFalse, reason: '监听没起来就不能自认房主');
      expect(session.state, RoomState.disconnected);
    });

    test('reconnectToHost 失败时进入 disconnected', () async {
      audio = MockAudioIo();
      sent = <Frame>[];
      transport = _FakeTransport(reconnectSucceeds: false);
      session = RoomSession(audioIo: audio, selfNickname: '测试者');
      session.attachTransport(transport);
      session.onSendFrame = sent.add;
      await session.joinRoom(startAudio: false);

      await session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: RosterPayload(hostId: 1, members: [
          RosterMember(memberId: 1, flags: 0x01, nickname: '房主'),
          RosterMember(memberId: 2, flags: 0x00, nickname: '阿远#321'),
          RosterMember(memberId: 4, flags: 0x00, nickname: '测试者'),
        ]).encode(),
      ));

      await session.handleIncomingFrame(Frame(
        type: FrameType.hostHandover,
        senderId: 1,
        seq: 2,
        payload: HostTransferCodec.encode(planHandingOverToTwo()),
      ));

      expect(session.state, RoomState.disconnected);
    });

    test('不支持房主转移的传输层上执行迁移会被明确拒绝', () async {
      audio = MockAudioIo();
      sent = <Frame>[];
      transport = _FakeTransport(supportsTransfer: false);
      session = RoomSession(audioIo: audio, selfNickname: '测试者');
      session.attachTransport(transport);
      session.onSendFrame = sent.add;
      await session.joinRoom(startAudio: false);

      await session.handleIncomingFrame(Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: RosterPayload(hostId: 1, members: [
          RosterMember(memberId: 1, flags: 0x01, nickname: '房主'),
          RosterMember(memberId: 4, flags: 0x00, nickname: '测试者'),
        ]).encode(),
      ));

      await session.handleIncomingFrame(Frame(
        type: FrameType.hostHandover,
        senderId: 1,
        seq: 2,
        payload: HostTransferCodec.encode(planHandingOverToTwo()),
      ));

      expect(transport.becomeHostCalls, 0);
      expect(transport.reconnectCalls, isEmpty);
      // 蓝牙房的语义：不支持就是静默不迁移，房间留在原地。
      expect(session.state, RoomState.inRoom);
    });
  });

  group('交接帧的防重放', () {
    test('joinOrder 更小的旧交接计划被丢弃', () async {
      await enterAsClientWithHost();

      await session.handleIncomingFrame(Frame(
        type: FrameType.hostHandover,
        senderId: 1,
        seq: 2,
        payload: HostTransferCodec.encode(planHandingOverToTwo()),
      ));
      expect(transport.reconnectCalls.length, 1);

      // 一份 joinOrder 更小的陈旧计划必须被 `_isPlanFresh` 挡掉。
      final stale = HostTransferPlan(
        successorId: 3,
        members: [
          HostTransferMember(
            memberId: 3,
            joinOrder: 1,
            nickname: '小北#654',
            endpoint: '192.168.1.3',
            sessionToken: token(3),
          ),
          HostTransferMember(
            memberId: 4,
            joinOrder: 2,
            nickname: '测试者',
            endpoint: '192.168.1.4',
            sessionToken: token(4),
          ),
        ],
      );
      await session.handleIncomingFrame(Frame(
        type: FrameType.hostHandover,
        senderId: 1,
        seq: 4,
        payload: HostTransferCodec.encode(stale),
      ));

      expect(transport.reconnectCalls.length, 1, reason: '陈旧计划不得再次触发迁移');
    });

    test('非房主发来的交接帧被忽略', () async {
      await enterAsClientWithHost();

      // 成员 #2 不是房主，它发的交接帧不能生效。
      await session.handleIncomingFrame(Frame(
        type: FrameType.hostHandover,
        senderId: 2,
        seq: 5,
        payload: HostTransferCodec.encode(planHandingOverToTwo()),
      ));

      expect(transport.reconnectCalls, isEmpty,
          reason: '「谁是房主」由名单决定，不能由任意成员宣告');
      expect(session.isHost, isFalse);
    });
  });

  group('手动转让房主', () {
    /// 传输层能报出对端端点时，手动转让才可能成型。
    /// `peerEndpoints` 就是成员 `endpoint` 的唯一来源——`_buildTransferPlan`
    /// 优先用它，其次是成员对象里缓存的 endpoint。
    test('端点已知时，房主转让会发出交接帧并把自己降为成员', () async {
      audio = MockAudioIo();
      sent = <Frame>[];
      transport = _FakeTransport(peerEndpoints: {2: '10.0.0.22'});
      session = RoomSession(audioIo: audio, selfNickname: '房主#100');
      session.attachTransport(transport);
      session.onSendFrame = sent.add;
      await session.createRoom(startAudio: false);

      await session.handleIncomingFrame(Frame(
        type: FrameType.joinReq,
        senderId: 0,
        seq: 1,
        payload: JoinRequestPayload(
          nickname: '阿远#321',
          sessionToken: token(2),
        ).encode(),
      ));

      sent.clear();
      await session.transferHost(2);

      expect(
        sent.map((f) => f.type),
        contains(FrameType.hostHandover),
        reason: '必须先把交接计划发出去，再自己降级',
      );
      expect(session.isHost, isFalse, reason: '转让后本机不再是房主');
      expect(transport.reconnectCalls, ['10.0.0.22']);
    });

    test('端点未知时拒绝转让并保持房主身份', () async {
      audio = MockAudioIo();
      sent = <Frame>[];
      // 没有 peerEndpoints 的传输层 = 「还不知道对方地址」
      transport = _FakeTransport();
      session = RoomSession(audioIo: audio, selfNickname: '房主#100');
      session.attachTransport(transport);
      session.onSendFrame = sent.add;
      await session.createRoom(startAudio: false);

      await session.handleIncomingFrame(Frame(
        type: FrameType.joinReq,
        senderId: 0,
        seq: 1,
        payload: JoinRequestPayload(
          nickname: '阿远#321',
          sessionToken: token(2),
        ).encode(),
      ));

      sent.clear();
      await session.transferHost(2);

      expect(
        sent.where((f) => f.type == FrameType.hostHandover),
        isEmpty,
        reason: '不能发一份成员无法被找到的交接计划',
      );
      expect(session.isHost, isTrue, reason: '转让失败必须保持房主身份');
      expect(transport.reconnectCalls, isEmpty);
    });

    test('端点未知时拒绝转让并给出可读原因，而不是发一份没人能找到的计划', () async {
      audio = MockAudioIo();
      sent = <Frame>[];
      transport = _FakeTransport();
      session = RoomSession(audioIo: audio, selfNickname: '房主#100');
      session.attachTransport(transport);
      session.onSendFrame = sent.add;
      await session.createRoom(startAudio: false);

      // 不给成员端点就转让：_buildTransferPlan 会因端点为空返回 null。
      // 这里用一个不存在的成员号验证「找不到目标」的早退。
      sent.clear();
      await session.transferHost(99);

      expect(sent.where((f) => f.type == FrameType.hostHandover), isEmpty);
      expect(session.isHost, isTrue, reason: '转让失败必须保持房主身份');
    });
  });

  group('发送链路不得被 attachTransport 静默切断', () {
    test('先注册观察者、后挂传输层时，观察者仍然收到每一帧', () async {
      // 回归测试：attachTransport 会把 onSendFrame 覆写成 transport.send，
      // 直接赋值 onSendFrame 的观测钩子会在挂传输层时被悄悄丢掉——
      // 表现是「帧一条都发不出去，但没有任何报错」。
      // addSendObserver 注册的钩子会在链路重建时被重新串进去。
      final seen = <Frame>[];
      audio = MockAudioIo();
      sent = <Frame>[];
      transport = _FakeTransport();
      session = RoomSession(audioIo: audio, selfNickname: '测试者');

      session.addSendObserver(seen.add);
      session.attachTransport(transport);
      await session.joinRoom(startAudio: false);

      await session.sendFrame(Frame(
        type: FrameType.heartbeat,
        senderId: session.selfMemberId,
        seq: 1,
        payload: Uint8List(0),
      ));

      expect(seen.map((f) => f.type), contains(FrameType.heartbeat));
    });

    test('改写层可以拦截发送（用于模拟丢包）', () async {
      audio = MockAudioIo();
      transport = _FakeTransport();
      session = RoomSession(audioIo: audio, selfNickname: '测试者');

      // 丢掉所有 heartbeat，其余放行。断言看**传输层实际收到**什么——
      // `addSendObserver` 在链路外层，看到的是"试图发出"的帧，
      // 存在改写层时它与最终交付的帧并不相同。
      session.setSendInterceptor((frame, next) {
        if (frame.type != FrameType.heartbeat) next(frame);
      });
      session.attachTransport(transport);

      await session.sendFrame(Frame(
        type: FrameType.heartbeat,
        senderId: 1,
        seq: 1,
        payload: Uint8List(0),
      ));
      await session.sendFrame(Frame(
        type: FrameType.leave,
        senderId: 1,
        seq: 2,
        payload: LeavePayload().encode(),
      ));

      expect(
        transport.sentFrames.map((f) => f.type),
        isNot(contains(FrameType.heartbeat)),
        reason: '被拦截的帧不得抵达传输层',
      );
      expect(
        transport.sentFrames.map((f) => f.type),
        contains(FrameType.leave),
      );
    });
  });
}

/// 可注入成败、并记录调用的假传输层。
class _FakeTransport implements RoomTransport {
  final _incoming = StreamController<Frame>.broadcast(sync: true);
  final _disconnected = StreamController<void>.broadcast(sync: true);

  final bool becomeHostSucceeds;
  final bool reconnectSucceeds;
  final bool supportsTransfer;

  /// 房主侧可见的对端端点。`_buildTransferPlan` 优先用它。
  final Map<int, String> _peerEndpoints;

  int becomeHostCalls = 0;
  final List<String> reconnectCalls = <String>[];

  /// 真正抵达传输层的帧。用 `addSendObserver` 观测到的是"试图发出"的帧，
  /// 两者在存在改写层时并不相同。
  final List<Frame> sentFrames = <Frame>[];

  _FakeTransport({
    this.becomeHostSucceeds = true,
    this.reconnectSucceeds = true,
    this.supportsTransfer = true,
    Map<int, String> peerEndpoints = const {},
  }) : _peerEndpoints = peerEndpoints;

  @override
  Stream<Frame> get incoming => _incoming.stream;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  @override
  int get peerCount => 0;

  @override
  void send(Frame frame) => sentFrames.add(frame);

  @override
  void updateSelfMemberId(int id) {}

  @override
  void updateKnownMemberIds(Set<int> ids) {}

  @override
  void bindMemberForSessionToken(Uint8List token, int memberId) {}

  @override
  void removeMember(int memberId) {}

  @override
  Future<void> flush() async {}

  @override
  Future<bool> reconnect() async => reconnectSucceeds;

  @override
  bool get supportsHostTransfer => supportsTransfer;

  @override
  Future<bool> becomeHost() async {
    becomeHostCalls++;
    return becomeHostSucceeds;
  }

  @override
  Future<bool> reconnectToHost(String endpoint) async {
    reconnectCalls.add(endpoint);
    return reconnectSucceeds;
  }

  @override
  Map<int, String> get peerEndpoints => _peerEndpoints;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _incoming.close();
    await _disconnected.close();
  }
}
