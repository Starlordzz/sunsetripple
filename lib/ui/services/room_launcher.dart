import 'dart:async';
import 'dart:io';

import '../../core/audio/audio_io.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/session/device_code.dart';
import '../../core/session/room_session.dart';
import '../../core/transport/ble_l2cap_transport.dart';
import '../../core/transport/lan_discovery.dart';
import '../../core/transport/lan_transport.dart';
import '../../core/transport/wifi_direct_manager.dart';

/// 建房/入房的结果。成功时带上已接好传输层的会话，失败时带上给用户看的原因。
sealed class RoomLaunchResult {
  const RoomLaunchResult();
}

class RoomLaunchSuccess extends RoomLaunchResult {
  final RoomSession session;
  final LanRoomDiscovery? discovery;
  final String roomName;

  const RoomLaunchSuccess({
    required this.session,
    required this.roomName,
    this.discovery,
  });
}

class RoomLaunchFailure extends RoomLaunchResult {
  /// 给用户看的一句话。调用方负责本地化展示，服务本身不碰 `BuildContext`。
  final String reason;
  final Object? cause;

  const RoomLaunchFailure(this.reason, {this.cause});
}

/// 建房与入房的**编排逻辑**，从 `HomeContent` 外提。
///
/// 为什么单独成类：这四种启动路径（WiFi 建房、蓝牙建房、局域网入房、
/// Wi-Fi Direct 直连入房）各自要按顺序装配 2~3 个对象——`RoomSession`、
/// 传输层、发现广播——失败时还要**逆序拆掉**已建好的部分。这段逻辑原本夹在
/// 1000 行的 Widget 里，既不能单测，又和 `setState`/`mounted` 纠缠在一起，
/// 很容易在某个失败分支漏掉一次 `dispose()` 而泄漏 socket 与监听端口。
///
/// 职责边界：
///   - 只负责对象装配、失败回滚与返回结果
///   - **不**碰 `BuildContext`、**不**弹 UI、**不**管动画时序
///   - 音频启动时机由调用方控制（进房转场期间不应当开麦）
class RoomLauncher {
  final AudioIo audioIo;

  /// 当前房间发现器。只有房主需要开始广播，所以由调用方持有并传入。
  final LanRoomDiscovery discovery;

  /// 蓝牙传输层由首页复用（原生插件是引擎级单例，整个 Dart 侧只能有一个）。
  ///
  /// **所有权属于调用方**：这里只借用它收发，任何失败回滚都**不**释放它——
  /// 一旦 dispose，底座原生插件就回到不可用状态，首页再也开不了蓝牙房。
  /// 回滚能动的只有本类自己新建的 [RoomSession] 与 [LanTransport]。
  final BleL2capTransport bleTransport;

  /// 会话构造器。默认造真实的 [RoomSession]（音频走注入的 [audioIo]）。
  ///
  /// 为什么留这个口子：装配失败回滚的正确性只能靠"注入替身 + 数释放次数"
  /// 来验证——真实 [RoomSession] 的 dispose 会顺带释放它持有的传输层，
  /// 分不清传输层是被谁释放的。
  final RoomSession Function({
    required String selfNickname,
    required RoomMode mode,
  }) _newSession;

  /// 传输层构造器。默认造真实的 [LanTransport]。
  final LanTransport Function() _newLanTransport;

  /// Wi-Fi Direct 直连入口。默认走引擎级单例。
  final Future<WifiP2pConnectionInfo?> Function(String address)
      _connectWifiDirect;

  RoomLauncher({
    required this.audioIo,
    required this.discovery,
    required this.bleTransport,
    RoomSession Function({
      required String selfNickname,
      required RoomMode mode,
    })? sessionFactory,
    LanTransport Function()? lanTransportFactory,
    Future<WifiP2pConnectionInfo?> Function(String address)?
        wifiDirectConnector,
  })  : _newSession = sessionFactory ??
            (({required String selfNickname, required RoomMode mode}) =>
                RoomSession(
                  audioIo: audioIo,
                  selfNickname: selfNickname,
                  mode: mode,
                )),
        _newLanTransport = lanTransportFactory ?? LanTransport.new,
        _connectWifiDirect =
            wifiDirectConnector ?? WifiDirectManager.instance.connectAndWait;

  static const String _tag = 'RoomLauncher';

  /// 房主：开 WiFi 房（局域网/热点/Wi-Fi Direct 全双工）。
  Future<RoomLaunchResult> createWifiRoom({
    required String selfNickname,
    required String roomName,
    required String roomId,
  }) async {
    final session = _newSession(
      selfNickname: selfNickname,
      mode: RoomMode.wifiFullDuplex,
    );
    final transport = _newLanTransport();
    // 资源一造出来就登记：`startHost` 可能在 TCP 已经 bind 成功、UDP 才失败的
    // 情况下返回 false（或直接抛异常），那一刻只有这份列表还引用着这个对象。
    final releases = <Future<void> Function()>[
      session.dispose,
      transport.dispose,
    ];

    try {
      if (!await transport.startHost()) {
        await _unwind(releases);
        return const RoomLaunchFailure('wifi_host_start_failed');
      }
      session.attachTransport(transport);

      // 开麦推迟到转场动画结束：AudioRecord/AudioTrack 的构造与前台服务启动
      // 都在 Android 主线程上，一次上百毫秒，压在 560ms 的转场里必然掉帧。
      await session.createRoom(startAudio: false);

      // 房建好了再广播，否则别人会搜到一个还进不去的房间。
      discovery.startAdvertising(
        roomId: roomId,
        roomName: roomName,
        hostNickname: selfNickname,
        tcpPort: transport.boundControlPort,
        getMemberCount: () => session.members.length,
      );
      // 广播一旦发出去就得有人收回，否则局域网里会一直挂着一个进不去的房间
      // （每秒一次 UDP 广播）。当前它是最后一步，这条分支暂无触发路径；
      // 但装配顺序一变（比如以后要在广播后继续做别的事）忘了登记就是长期泄漏。
      releases.add(() async {
        discovery.stopAdvertising();
      });
    } catch (e) {
      AppLog.error(_tag, '开 WiFi 房失败', e);
      await _unwind(releases);
      return RoomLaunchFailure('wifi_host_start_failed', cause: e);
    }

    return RoomLaunchSuccess(
      session: session,
      roomName: roomName,
      discovery: discovery,
    );
  }

  /// 客户端：加入局域网房间。
  Future<RoomLaunchResult> joinLanRoom({
    required DiscoveredRoom room,
    required String selfNickname,
  }) async {
    return _joinWithTransport(
      session: _newSession(
        selfNickname: selfNickname,
        mode: RoomMode.wifiFullDuplex,
      ),
      roomName: room.roomName,
      connect: () => _startClientTransport(
        hostAddress: room.hostAddress,
        port: room.port,
      ),
    );
  }

  /// 客户端：加入 Wi-Fi Direct 直连房间（免路由）。
  Future<RoomLaunchResult> joinWifiDirectPeer({
    required WifiP2pPeer peer,
    required String selfNickname,
  }) async {
    return _joinWithTransport(
      session: _newSession(
        selfNickname: selfNickname,
        mode: RoomMode.wifiFullDuplex,
      ),
      roomName: peer.name,
      connect: () async {
        // 先谈好 P2P 组，拿到 group owner 的实际 IP，再走 TCP。
        // connectAndWait 自带 15 秒超时，返回 null 表示没谈成。
        final info = await _connectWifiDirect(peer.address);
        if (info == null || !info.isConnected) return null;
        if (info.groupOwnerAddress.isEmpty) {
          AppLog.warn(_tag, 'P2P 组已建立但拿不到 group owner 地址');
          return null;
        }
        return _startClientTransport(
          hostAddress: InternetAddress(info.groupOwnerAddress),
          port: LanTransport.controlPort,
        );
      },
    );
  }

  /// 客户端：加入蓝牙 PTT 房。
  ///
  /// 回滚只释放本类新建的会话：`bleTransport` 是调用方持有的引擎级单例
  /// （见字段说明），dispose 掉首页就再也开不了蓝牙房；链路的断开由首页
  /// 在自己的退房流程里统一处理。
  Future<RoomLaunchResult> joinBleRoom({
    required DiscoveredBleRoom room,
    required String selfNickname,
  }) async {
    final session = _newSession(
      selfNickname: selfNickname,
      mode: RoomMode.bluetoothPtt,
    );
    final releases = <Future<void> Function()>[session.dispose];

    try {
      if (!await bleTransport.connectToHost(room)) {
        await _unwind(releases);
        return const RoomLaunchFailure('ble_join_failed');
      }
      session.attachTransport(bleTransport);
      await session.joinRoom(startAudio: false);
    } catch (e) {
      AppLog.error(_tag, '加入蓝牙房失败', e);
      await _unwind(releases);
      return RoomLaunchFailure('ble_join_failed', cause: e);
    }

    return RoomLaunchSuccess(session: session, roomName: room.roomName);
  }

  /// 房主：开蓝牙房。
  ///
  /// 回滚规则同 [joinBleRoom]：共享的蓝牙传输层不归这里释放。
  Future<RoomLaunchResult> createBleRoom({
    required String selfNickname,
    required String roomName,
  }) async {
    final session = _newSession(
      selfNickname: selfNickname,
      mode: RoomMode.bluetoothPtt,
    );
    final releases = <Future<void> Function()>[session.dispose];

    try {
      if (!await bleTransport.startHost(roomName: roomName)) {
        await _unwind(releases);
        return const RoomLaunchFailure('ble_host_start_failed');
      }
      session.attachTransport(bleTransport);
      await session.createRoom(startAudio: false);
    } catch (e) {
      AppLog.error(_tag, '开蓝牙房失败', e);
      await _unwind(releases);
      return RoomLaunchFailure('ble_host_start_failed', cause: e);
    }

    return RoomLaunchSuccess(session: session, roomName: roomName);
  }

  /// 局域网/Wi-Fi Direct 入房的共用尾部：接传输层 → 入房 → 失败回滚。
  ///
  /// [connect] 的契约：要么返回一个已连上、可用的传输层；要么返回 null（或抛
  /// 异常）并且**自己已经把建好的传输层释放干净**——见 [_startClientTransport]。
  /// 这里只在真正拿到对象之后才登记它：拿不到的对象无从回滚。
  Future<RoomLaunchResult> _joinWithTransport({
    required RoomSession session,
    required String roomName,
    required Future<LanTransport?> Function() connect,
  }) async {
    final releases = <Future<void> Function()>[session.dispose];

    final LanTransport? transport;
    try {
      transport = await connect();
    } catch (e) {
      AppLog.error(_tag, '连接房间失败', e);
      await _unwind(releases);
      return RoomLaunchFailure('lan_join_failed', cause: e);
    }

    if (transport == null) {
      await _unwind(releases);
      return const RoomLaunchFailure('lan_join_failed');
    }
    releases.add(transport.dispose);

    try {
      session.attachTransport(transport);
      await session.joinRoom(startAudio: false);
    } catch (e) {
      AppLog.error(_tag, '加入房间失败', e);
      await _unwind(releases);
      return RoomLaunchFailure('lan_join_failed', cause: e);
    }

    return RoomLaunchSuccess(session: session, roomName: roomName);
  }

  /// 逆序释放装配过程中已获取的资源。
  ///
  /// 为什么逆序：后拿到的资源总是依赖先拿到的（会话订阅传输层的流、广播又要读
  /// 会话成员数），顺着拆会把还在被引用的东西先抽掉。
  ///
  /// 每个释放动作单独 try/catch：某个 socket 关不掉不能连累其余释放，更不能把
  /// 原始失败原因顶掉——给用户的原因必须还是"哪一步装配失败"，而不是拆的时候
  /// 顺带冒出来的第二个异常。
  Future<void> _unwind(List<Future<void> Function()> releases) async {
    for (final release in releases.reversed) {
      try {
        await release();
      } catch (e) {
        AppLog.error(_tag, '回滚已占用的资源时失败', e);
      }
    }
  }

  /// 建一个客户端传输层并连上房主。
  ///
  /// 不变量：**返回 null 或抛异常之前，一定已经释放掉自己建的传输层。**
  /// [_joinWithTransport] 只在 [connect] 返回值非空时才拿得到传输层引用；
  /// 而 `startClient` 返回 false 或半途抛异常时 socket 可能已经连上，若不在这
  /// 里兜底，这个对象就没人引用了——回滚列表也救不了不存在于列表里的资源。
  Future<LanTransport?> _startClientTransport({
    required InternetAddress hostAddress,
    required int port,
  }) async {
    final transport = _newLanTransport();
    try {
      if (await transport.startClient(hostAddress: hostAddress, port: port)) {
        return transport;
      }
    } catch (_) {
      // startClient 抛异常时 socket 可能已经连上，先收回传输层再原样抛出。
      await _unwind(<Future<void> Function()>[transport.dispose]);
      rethrow;
    }
    // 返回 false：同样可能已经 bind/connect 过，不能留残余。
    await _unwind(<Future<void> Function()>[transport.dispose]);
    return null;
  }

  /// 把用户输入的昵称规范化成带设备短码的身份串。
  static String identityName(String nickname) => DeviceCode.attach(nickname);
}
