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
  final BleL2capTransport bleTransport;

  RoomLauncher({
    required this.audioIo,
    required this.discovery,
    required this.bleTransport,
  });

  static const String _tag = 'RoomLauncher';

  /// 房主：开 WiFi 房（局域网/热点/Wi-Fi Direct 全双工）。
  Future<RoomLaunchResult> createWifiRoom({
    required String selfNickname,
    required String roomName,
    required String roomId,
  }) async {
    final session = RoomSession(
      audioIo: audioIo,
      selfNickname: selfNickname,
      mode: RoomMode.wifiFullDuplex,
    );
    final transport = LanTransport();

    if (!await transport.startHost()) {
      // 倒序拆：会话持有可能已订阅的流，先释放会话再丢传输层。
      await transport.dispose();
      await session.dispose();
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
      session: RoomSession(
        audioIo: audioIo,
        selfNickname: selfNickname,
        mode: RoomMode.wifiFullDuplex,
      ),
      roomName: room.roomName,
      connect: () async {
        final transport = LanTransport();
        final ok = await transport.startClient(
          hostAddress: room.hostAddress,
          port: room.port,
        );
        return ok ? transport : null;
      },
    );
  }

  /// 客户端：加入 Wi-Fi Direct 直连房间（免路由）。
  Future<RoomLaunchResult> joinWifiDirectPeer({
    required WifiP2pPeer peer,
    required String selfNickname,
  }) async {
    return _joinWithTransport(
      session: RoomSession(
        audioIo: audioIo,
        selfNickname: selfNickname,
        mode: RoomMode.wifiFullDuplex,
      ),
      roomName: peer.name,
      connect: () async {
        // 先谈好 P2P 组，拿到 group owner 的实际 IP，再走 TCP。
        // connectAndWait 自带 15 秒超时，返回 null 表示没谈成。
        final info =
            await WifiDirectManager.instance.connectAndWait(peer.address);
        if (info == null || !info.isConnected) return null;
        if (info.groupOwnerAddress.isEmpty) {
          AppLog.warn(_tag, 'P2P 组已建立但拿不到 group owner 地址');
          return null;
        }
        final transport = LanTransport();
        final ok = await transport.startClient(
          hostAddress: InternetAddress(info.groupOwnerAddress),
          port: LanTransport.controlPort,
        );
        return ok ? transport : null;
      },
    );
  }

  /// 客户端：加入蓝牙 PTT 房。
  Future<RoomLaunchResult> joinBleRoom({
    required DiscoveredBleRoom room,
    required String selfNickname,
  }) async {
    final session = RoomSession(
      audioIo: audioIo,
      selfNickname: selfNickname,
      mode: RoomMode.bluetoothPtt,
    );

    if (!await bleTransport.connectToHost(room)) {
      await session.dispose();
      return const RoomLaunchFailure('ble_join_failed');
    }
    session.attachTransport(bleTransport);
    await session.joinRoom(startAudio: false);

    return RoomLaunchSuccess(session: session, roomName: room.roomName);
  }

  /// 房主：开蓝牙房。
  Future<RoomLaunchResult> createBleRoom({
    required String selfNickname,
    required String roomName,
  }) async {
    final session = RoomSession(
      audioIo: audioIo,
      selfNickname: selfNickname,
      mode: RoomMode.bluetoothPtt,
    );

    if (!await bleTransport.startHost(roomName: roomName)) {
      await session.dispose();
      return const RoomLaunchFailure('ble_host_start_failed');
    }
    session.attachTransport(bleTransport);
    await session.createRoom(startAudio: false);

    return RoomLaunchSuccess(session: session, roomName: roomName);
  }

  /// 局域网/Wi-Fi Direct 入房的共用尾部：接传输层 → 入房 → 失败回滚。
  Future<RoomLaunchResult> _joinWithTransport({
    required RoomSession session,
    required String roomName,
    required Future<LanTransport?> Function() connect,
  }) async {
    final LanTransport? transport;
    try {
      transport = await connect();
    } catch (e) {
      AppLog.error(_tag, '连接房间失败', e);
      await session.dispose();
      return RoomLaunchFailure('lan_join_failed', cause: e);
    }

    if (transport == null) {
      await session.dispose();
      return const RoomLaunchFailure('lan_join_failed');
    }

    session.attachTransport(transport);
    await session.joinRoom(startAudio: false);
    return RoomLaunchSuccess(session: session, roomName: roomName);
  }

  /// 把用户输入的昵称规范化成带设备短码的身份串。
  static String identityName(String nickname) => DeviceCode.attach(nickname);
}
