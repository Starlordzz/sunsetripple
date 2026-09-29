import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/session/room_session.dart';
import 'package:sunset_ripple/core/transport/ble_l2cap_transport.dart';
import 'package:sunset_ripple/core/transport/lan_discovery.dart';
import 'package:sunset_ripple/core/transport/lan_transport.dart';
import 'package:sunset_ripple/core/transport/room_transport.dart';
import 'package:sunset_ripple/core/transport/wifi_direct_manager.dart';
import 'package:sunset_ripple/ui/services/room_launcher.dart';

/// 四条启动路径（WiFi 建房 / 蓝牙建房 / 局域网入房 / Wi-Fi Direct 直连）的
/// **装配失败回滚**回归测试。
///
/// 为什么必须单独锁住：回滚原先只覆盖「启动返回 false」分支，`createRoom` /
/// `joinRoom` / `startAdvertising` 抛异常时，已经占住的 TCP 8988 / UDP 8989
/// 端口和发现广播定时器就留在地上没人收。用户在真机上只会看到「怎么都开不了房，
/// 重启一下就好了」——这类泄漏没法靠肉眼回归，只能靠替身计数断言。
///
/// 断言口径：第 N 步失败后，**每个已经获取到的资源恰好被释放一次**，
/// **没获取到的资源一次都不许释放**（尤其是首页共享的蓝牙传输层）。
void main() {
  group('createWifiRoom（WiFi 建房）', () {
    const cases = <_Case>[
      _Case('startHost 返回 false → 释放传输层与会话',
          _Plan(_Step.lanStartHost, mode: _FailMode.returnsFalse)),
      _Case('startHost 抛异常 → 释放传输层与会话', _Plan(_Step.lanStartHost)),
      _Case('attachTransport 抛异常 → 释放传输层与会话', _Plan(_Step.attachTransport)),
      _Case('createRoom 抛异常 → 释放传输层与会话', _Plan(_Step.createRoom)),
      _Case('startAdvertising 抛异常 → 释放传输层与会话（广播没起来过，不发解散通知）',
          _Plan(_Step.startAdvertising)),
    ];

    for (final c in cases) {
      test(c.label, () async {
        final rig = _Rig(c.plan);
        final result = await rig.launcher.createWifiRoom(
          selfNickname: '阿凉',
          roomName: '海边',
          roomId: 'room-1',
        );

        _expectRollback(rig, c, result, 'wifi_host_start_failed');
      });
    }

    test('全部装配成功 → RoomLaunchSuccess 且零释放', () async {
      final rig = _Rig(const _Plan(_Step.none, mode: _FailMode.none));
      final result = await rig.launcher.createWifiRoom(
        selfNickname: '阿凉',
        roomName: '海边',
        roomId: 'room-1',
      );

      expect(result, isA<RoomLaunchSuccess>());
      final success = result as RoomLaunchSuccess;
      expect(success.session, same(rig.session));
      expect(success.roomName, '海边');
      expect(success.discovery, same(rig.discovery));
      expect(rig.requestedModes, <RoomMode>[RoomMode.wifiFullDuplex]);
      expect(rig.lan.startHostCount, 1);
      expect(rig.session.attachCount, 1);
      expect(rig.session.createCount, 1);
      expect(rig.session.lastStartAudio, isFalse, reason: '开麦必须推迟到转场结束');
      expect(rig.discovery.startCount, 1);
      expect(rig.discovery.stopCount, 0);
      expect(rig.lan.disposeCount, 0);
      expect(rig.session.disposeCount, 0);
    });

    test('某个释放动作自己抛异常 → 其余资源照样释放，且不顶掉原始失败原因', () async {
      // createRoom 失败时，回滚顺序是「传输层 → 会话」；让传输层的 dispose 抛异常，
      // 验证会话仍被释放、且返回的 cause 还是 createRoom 那个原始异常。
      final rig = _Rig(const _Plan(_Step.createRoom, disposeThrows: true));
      final result = await rig.launcher.createWifiRoom(
        selfNickname: '阿凉',
        roomName: '海边',
        roomId: 'room-1',
      );

      expect(result, isA<RoomLaunchFailure>());
      final failure = result as RoomLaunchFailure;
      expect(failure.reason, 'wifi_host_start_failed');
      expect(rig.lan.disposeCount, 1);
      expect(rig.session.disposeCount, 1, reason: '前一个释放动作抛异常不能跳过后面的释放');
      expect((failure.cause! as StateError).message, contains('createRoom'),
          reason: '不能把 release 自己的异常当成失败原因抛给用户');
    });
  });

  group('createBleRoom（蓝牙建房）', () {
    const cases = <_Case>[
      _Case('startHost 返回 false → 释放会话，不碰共享传输层',
          _Plan(_Step.bleStartHost, mode: _FailMode.returnsFalse),
          transportBuilt: false),
      _Case('startHost 抛异常 → 释放会话，不碰共享传输层', _Plan(_Step.bleStartHost),
          transportBuilt: false),
      _Case('attachTransport 抛异常 → 释放会话', _Plan(_Step.attachTransport),
          transportBuilt: false),
      _Case('createRoom 抛异常 → 释放会话', _Plan(_Step.createRoom),
          transportBuilt: false),
    ];

    for (final c in cases) {
      test(c.label, () async {
        final rig = _Rig(c.plan);
        final result = await rig.launcher.createBleRoom(
          selfNickname: '阿凉',
          roomName: '海边',
        );

        _expectRollback(rig, c, result, 'ble_host_start_failed');
        expect(rig.ble.startCount, 1);
      });
    }

    test('全部装配成功 → RoomLaunchSuccess 且零释放', () async {
      final rig = _Rig(const _Plan(_Step.none, mode: _FailMode.none));
      final result = await rig.launcher.createBleRoom(
        selfNickname: '阿凉',
        roomName: '海边',
      );

      expect(result, isA<RoomLaunchSuccess>());
      final success = result as RoomLaunchSuccess;
      expect(success.session, same(rig.session));
      expect(success.roomName, '海边');
      expect(success.discovery, isNull, reason: '蓝牙房不广播');
      expect(rig.requestedModes, <RoomMode>[RoomMode.bluetoothPtt]);
      expect(rig.ble.startCount, 1);
      expect(rig.session.attachCount, 1);
      expect(rig.session.createCount, 1);
      expect(rig.session.lastStartAudio, isFalse, reason: '开麦必须推迟到转场结束');
      expect(rig.session.disposeCount, 0);
      expect(rig.ble.disposeCount, 0, reason: '蓝牙传输层归首页所有，成功路径也不许动它');
    });
  });

  group('joinBleRoom（蓝牙入房）', () {
    const cases = <_Case>[
      _Case('connectToHost 返回 false → 释放会话，不碰共享传输层',
          _Plan(_Step.bleConnectToHost, mode: _FailMode.returnsFalse),
          transportBuilt: false),
      _Case('connectToHost 抛异常 → 释放会话，不碰共享传输层', _Plan(_Step.bleConnectToHost),
          transportBuilt: false),
      _Case('attachTransport 抛异常 → 释放会话', _Plan(_Step.attachTransport),
          transportBuilt: false),
      _Case('joinRoom 抛异常 → 释放会话', _Plan(_Step.joinRoom),
          transportBuilt: false),
    ];

    for (final c in cases) {
      test(c.label, () async {
        final rig = _Rig(c.plan);
        final result = await rig.launcher.joinBleRoom(
          room: _discoveredBleRoom(),
          selfNickname: '阿凉',
        );

        _expectRollback(rig, c, result, 'ble_join_failed');
        expect(rig.ble.connectCount, 1);
      });
    }

    test('全部装配成功 → RoomLaunchSuccess 且零释放', () async {
      final rig = _Rig(const _Plan(_Step.none, mode: _FailMode.none));
      final result = await rig.launcher.joinBleRoom(
        room: _discoveredBleRoom(),
        selfNickname: '阿凉',
      );

      expect(result, isA<RoomLaunchSuccess>());
      final success = result as RoomLaunchSuccess;
      expect(success.session, same(rig.session));
      expect(success.roomName, '海边');
      expect(success.discovery, isNull, reason: '蓝牙房不广播');
      expect(rig.requestedModes, <RoomMode>[RoomMode.bluetoothPtt]);
      expect(rig.ble.connectCount, 1);
      expect(rig.session.attachCount, 1);
      expect(rig.session.joinCount, 1);
      expect(rig.session.lastStartAudio, isFalse, reason: '开麦必须推迟到转场结束');
      expect(rig.session.disposeCount, 0);
      expect(rig.ble.disposeCount, 0, reason: '蓝牙传输层归首页所有，成功路径也不许动它');
    });
  });

  group('joinLanRoom（局域网入房）', () {
    const cases = <_Case>[
      _Case('startClient 返回 false → 释放传输层与会话',
          _Plan(_Step.lanStartClient, mode: _FailMode.returnsFalse)),
      _Case('startClient 抛异常 → 释放传输层与会话', _Plan(_Step.lanStartClient)),
      _Case('attachTransport 抛异常 → 释放传输层与会话', _Plan(_Step.attachTransport)),
      _Case('joinRoom 抛异常 → 释放传输层与会话', _Plan(_Step.joinRoom)),
    ];

    for (final c in cases) {
      test(c.label, () async {
        final rig = _Rig(c.plan);
        final result = await rig.launcher.joinLanRoom(
          room: _discoveredRoom(),
          selfNickname: '阿凉',
        );

        _expectRollback(rig, c, result, 'lan_join_failed');
        expect(rig.lan.startClientCount, 1);
      });
    }

    test('全部装配成功 → RoomLaunchSuccess 且零释放', () async {
      final rig = _Rig(const _Plan(_Step.none, mode: _FailMode.none));
      final result = await rig.launcher.joinLanRoom(
        room: _discoveredRoom(),
        selfNickname: '阿凉',
      );

      expect(result, isA<RoomLaunchSuccess>());
      final success = result as RoomLaunchSuccess;
      expect(success.session, same(rig.session));
      expect(success.roomName, '海边');
      expect(success.discovery, isNull, reason: '入房方不广播');
      expect(rig.requestedModes, <RoomMode>[RoomMode.wifiFullDuplex]);
      expect(rig.lan.startHostCount, 0, reason: '入房只连不监听，否则会白占 8988');
      expect(rig.lan.startClientCount, 1);
      expect(rig.session.attachCount, 1);
      expect(rig.session.joinCount, 1);
      expect(rig.session.lastStartAudio, isFalse, reason: '开麦必须推迟到转场结束');
      expect(rig.lan.disposeCount, 0);
      expect(rig.session.disposeCount, 0);
    });
  });

  group('joinWifiDirectPeer（Wi-Fi Direct 直连入房）', () {
    const cases = <_Case>[
      _Case('P2P 直连抛异常 → 只释放会话（传输层还没建）', _Plan(_Step.wifiDirectThrows),
          transportBuilt: false),
      _Case('P2P 直连返回 null → 只释放会话',
          _Plan(_Step.wifiDirectReturnsNull, mode: _FailMode.returnsFalse),
          transportBuilt: false),
      _Case(
          'P2P 组已建立但拿不到 group owner 地址 → 只释放会话',
          _Plan(_Step.wifiDirectNoGroupOwnerAddress,
              mode: _FailMode.returnsFalse),
          transportBuilt: false),
      _Case('startClient 返回 false → 释放传输层与会话',
          _Plan(_Step.lanStartClient, mode: _FailMode.returnsFalse)),
      _Case('startClient 抛异常 → 释放传输层与会话', _Plan(_Step.lanStartClient)),
      _Case('attachTransport 抛异常 → 释放传输层与会话', _Plan(_Step.attachTransport)),
      _Case('joinRoom 抛异常 → 释放传输层与会话', _Plan(_Step.joinRoom)),
    ];

    for (final c in cases) {
      test(c.label, () async {
        final rig = _Rig(c.plan);
        final peer = _p2pPeer();
        final result = await rig.launcher.joinWifiDirectPeer(
          peer: peer,
          selfNickname: '阿凉',
        );

        _expectRollback(rig, c, result, 'lan_join_failed');
        expect(rig.connectedAddresses, <String>[peer.address]);
      });
    }

    test('全部装配成功 → RoomLaunchSuccess 且零释放', () async {
      final rig = _Rig(const _Plan(_Step.none, mode: _FailMode.none));
      final peer = _p2pPeer();
      final result = await rig.launcher.joinWifiDirectPeer(
        peer: peer,
        selfNickname: '阿凉',
      );

      expect(result, isA<RoomLaunchSuccess>());
      final success = result as RoomLaunchSuccess;
      expect(success.session, same(rig.session));
      expect(success.roomName, peer.name);
      expect(rig.requestedModes, <RoomMode>[RoomMode.wifiFullDuplex]);
      expect(rig.connectedAddresses, <String>[peer.address]);
      expect(rig.lan.startClientCount, 1);
      expect(rig.session.attachCount, 1);
      expect(rig.session.joinCount, 1);
      expect(rig.session.lastStartAudio, isFalse, reason: '开麦必须推迟到转场结束');
      expect(rig.lan.disposeCount, 0);
      expect(rig.session.disposeCount, 0);
    });
  });
}

// ----------------------------------------------------------------- 断言

/// 失败路径的统一断言：正确的失败原因 + 每个已获取资源恰好释放一次。
void _expectRollback(
  _Rig rig,
  _Case c,
  RoomLaunchResult result,
  String reason,
) {
  expect(rig.sessionBuilds, 1, reason: '会话必须由注入的工厂产出（否则真实 RoomSession 会漏进来）');

  expect(result, isA<RoomLaunchFailure>(), reason: '失败必须返回 RoomLaunchFailure');
  final failure = result as RoomLaunchFailure;
  expect(failure.reason, reason);
  if (c.expectsCause) {
    expect(failure.cause, isNotNull, reason: '抛异常的分支要带上原始 cause 给上层记录');
  } else {
    expect(failure.cause, isNull, reason: '返回 false 的分支没有异常可带（保持原有返回值）');
  }

  expect(rig.lanBuilds, c.transportBuilt ? 1 : 0);
  expect(rig.lan.disposeCount, c.transportBuilt ? 1 : 0,
      reason: '传输层占着 TCP 8988 / UDP 8989，失败路径漏释放就是下一次建房失败的原因');
  expect(rig.session.disposeCount, 1, reason: '会话持有可能已订阅的流，必须释放');
  expect(rig.session.lastStartAudio, isNot(isTrue), reason: '开麦必须推迟到转场结束');
  expect(rig.discovery.stopCount, 0, reason: '没有一条失败路径该发出广播或解散通知');
  expect(rig.ble.disposeCount, 0, reason: '蓝牙传输层是首页的，任何回滚都不许 dispose 它');
}

// ----------------------------------------------------------------- 注入点

/// 装配过程中的注入点：在哪一步失败。
enum _Step {
  none,
  lanStartHost,
  lanStartClient,
  bleStartHost,
  bleConnectToHost,
  attachTransport,
  createRoom,
  joinRoom,
  startAdvertising,
  wifiDirectThrows,
  wifiDirectReturnsNull,
  wifiDirectNoGroupOwnerAddress,
}

/// 启动类步骤的失败方式。返回 false 与抛异常在上层是两条不同的分支
/// （前者没有 cause），必须分别覆盖。
enum _FailMode { none, returnsFalse, throws }

/// 一次注入：在第 [step] 步按 [mode] 失败。
///
/// [disposeThrows] 用来验证「某个释放动作自己失败，也不能连累其余释放，
/// 也不能顶掉原始失败原因」。
class _Plan {
  const _Plan(
    this.step, {
    this.mode = _FailMode.throws,
    this.disposeThrows = false,
  });

  final _Step step;
  final _FailMode mode;
  final bool disposeThrows;
}

/// 一条失败用例：注入点 + 该注入下资源获取到了什么程度。
class _Case {
  const _Case(this.label, this.plan, {this.transportBuilt = true});

  final String label;
  final _Plan plan;

  /// 失败发生时局域网传输层是否已经建出来：建了就**必须**被释放，
  /// 没建就一次都不该释放。
  final bool transportBuilt;

  /// 抛异常的注入才有原始 cause。
  bool get expectsCause => plan.mode == _FailMode.throws;
}

// ----------------------------------------------------------------- 替身

/// 一次启动尝试的全部替身与观测点。
class _Rig {
  _Rig(this.plan)
      : discovery = _FakeDiscovery(plan),
        lan = _FakeLanTransport(plan),
        ble = _FakeBleTransport(plan) {
    launcher = RoomLauncher(
      audioIo: audio,
      discovery: discovery,
      bleTransport: ble,
      sessionFactory: ({required String selfNickname, required RoomMode mode}) {
        sessionBuilds++;
        requestedModes.add(mode);
        session = _FakeSession(plan, selfNickname: selfNickname, mode: mode);
        return session;
      },
      lanTransportFactory: () {
        lanBuilds++;
        return lan;
      },
      wifiDirectConnector: _connect,
    );
  }

  final _Plan plan;
  final MockAudioIo audio = MockAudioIo();
  final _FakeDiscovery discovery;
  final _FakeLanTransport lan;
  final _FakeBleTransport ble;

  late final RoomLauncher launcher;

  /// 会话工厂被调用的次数。四条路径都必须走工厂，否则真实 `RoomSession`
  /// 会漏进来（真实 dispose 会顺带释放传输层，计数就不可信了）。
  int sessionBuilds = 0;
  int lanBuilds = 0;
  late _FakeSession session;
  final List<RoomMode> requestedModes = <RoomMode>[];
  final List<String> connectedAddresses = <String>[];

  Future<WifiP2pConnectionInfo?> _connect(String address) async {
    connectedAddresses.add(address);
    switch (plan.step) {
      case _Step.wifiDirectThrows:
        throw StateError('注入失败：Wi-Fi Direct 直连');
      case _Step.wifiDirectReturnsNull:
        return null;
      case _Step.wifiDirectNoGroupOwnerAddress:
        return const WifiP2pConnectionInfo(
          isConnected: true,
          isGroupOwner: false,
          groupFormed: true,
          groupOwnerAddress: '',
        );
      default:
        return const WifiP2pConnectionInfo(
          isConnected: true,
          isGroupOwner: false,
          groupFormed: true,
          groupOwnerAddress: '192.168.49.1',
        );
    }
  }
}

/// 假会话：只记录 launcher 有没有叫它装配、有没有释放它。
///
/// 故意**不**把 [attachTransport] / [dispose] 转发给父类：真实
/// `RoomSession.dispose()` 会顺带 `transport?.dispose()`，转发的话就分不清
/// 传输层到底是被 launcher 释放的还是被会话顺带释放的——本组测试要锁的正是
/// launcher 自己的回滚职责。
class _FakeSession extends RoomSession {
  _FakeSession(this._plan, {required super.selfNickname, required super.mode})
      : super(audioIo: MockAudioIo());

  final _Plan _plan;

  int attachCount = 0;
  int createCount = 0;
  int joinCount = 0;
  int disposeCount = 0;
  bool? lastStartAudio;

  @override
  void attachTransport(RoomTransport value) {
    attachCount++;
    _failIf(_Step.attachTransport);
  }

  @override
  Future<void> createRoom({bool startAudio = true}) async {
    createCount++;
    lastStartAudio = startAudio;
    _failIf(_Step.createRoom);
  }

  @override
  Future<void> joinRoom({bool startAudio = true}) async {
    joinCount++;
    lastStartAudio = startAudio;
    _failIf(_Step.joinRoom);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  void _failIf(_Step step) {
    if (_plan.step == step) throw StateError('注入失败：${step.name}');
  }
}

/// 只统计广播调用的假发现器。
class _FakeDiscovery extends LanRoomDiscovery {
  _FakeDiscovery(this._plan);

  final _Plan _plan;

  int startCount = 0;
  int stopCount = 0;

  @override
  void startAdvertising({
    required String roomId,
    required String roomName,
    required String hostNickname,
    required int tcpPort,
    required int Function() getMemberCount,
  }) {
    startCount++;
    if (_plan.step == _Step.startAdvertising) {
      throw StateError('注入失败：startAdvertising');
    }
  }

  @override
  void stopAdvertising({bool sendGoodbye = true}) {
    stopCount++;
  }
}

/// 只统计启动结果与释放次数的假传输层。真实 socket 一律不碰。
class _FakeLanTransport extends LanTransport {
  _FakeLanTransport(this._plan);

  final _Plan _plan;

  int startHostCount = 0;
  int startClientCount = 0;
  int disposeCount = 0;

  @override
  Future<bool> startHost(
      {int port = LanTransport.controlPort, int? udpPort}) async {
    startHostCount++;
    return _started(_Step.lanStartHost);
  }

  @override
  Future<bool> startClient({
    required InternetAddress hostAddress,
    int port = LanTransport.controlPort,
    int? hostAudioPort,
    bool silent = false,
  }) async {
    startClientCount++;
    return _started(_Step.lanStartClient);
  }

  /// 没被注入失败的启动一律成功。
  bool _started(_Step step) {
    if (_plan.step != step) return true;
    if (_plan.mode == _FailMode.throws) {
      throw StateError('注入失败：${step.name}');
    }
    return false;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    if (_plan.disposeThrows) throw StateError('注入失败：dispose');
  }
}

/// 假蓝牙传输层。它的 `dispose` 计数应该永远是 0——引擎级单例归首页所有。
class _FakeBleTransport extends BleL2capTransport {
  _FakeBleTransport(this._plan);

  final _Plan _plan;

  int startCount = 0;
  int connectCount = 0;
  int disposeCount = 0;

  @override
  Future<bool> startHost(
      {required String roomName, int memberCount = 1}) async {
    startCount++;
    return _started(_Step.bleStartHost);
  }

  @override
  Future<bool> connectToHost(DiscoveredBleRoom room) async {
    connectCount++;
    return _started(_Step.bleConnectToHost);
  }

  bool _started(_Step step) {
    if (_plan.step != step) return true;
    if (_plan.mode == _FailMode.throws) {
      throw StateError('注入失败：${step.name}');
    }
    return false;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

// ----------------------------------------------------------------- 素材

DiscoveredRoom _discoveredRoom() => DiscoveredRoom(
      roomId: 'room-1',
      roomName: '海边',
      hostNickname: '阿凉',
      hostAddress: InternetAddress.loopbackIPv4,
      port: LanTransport.controlPort,
      memberCount: 1,
      lastSeen: DateTime(2026, 9, 29),
    );

DiscoveredBleRoom _discoveredBleRoom() => DiscoveredBleRoom(
      address: 'AA:BB:CC:DD:EE:FF',
      roomName: '海边',
      psm: 0x1001,
      memberCount: 1,
      rssi: -40,
      lastSeen: DateTime(2026, 9, 29),
    );

WifiP2pPeer _p2pPeer() => const WifiP2pPeer(
      name: '阿凉的热点',
      address: '02:00:00:00:00:00',
      status: 0,
      isGroupOwner: false,
    );
