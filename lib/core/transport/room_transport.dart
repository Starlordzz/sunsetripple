import 'dart:async';

import '../protocol/frame.dart';

/// 房间传输层的统一契约。
///
/// WiFi 房（[LanTransport]）和蓝牙房（[BleL2capTransport]）在上层看来必须
/// 长得一样：[RoomSession] 只认「把帧发出去」和「收到帧」这两件事，
/// 具体是 TCP/UDP 还是 BLE L2CAP CoC 由实现决定。
abstract class RoomTransport {
  /// 收到的、需要交给 `RoomSession.handleIncomingFrame` 的帧。
  Stream<Frame> get incoming;

  /// 当前连接上的对端数量。
  int get peerCount;

  /// `RoomSession.onSendFrame` 挂到这里。
  void send(Frame frame);

  /// 把还没写出的待发帧推到底层链路。
  ///
  /// leave 场景专用：`stop()` 会直接销毁链路，socket 发缓冲里的字节会
  /// 一起被丢掉，离房帧可能到不了对方。flush 是 I/O 完成事件而非定时器，
  /// 在测试的 FakeAsync 时区里也能正常完成。
  Future<void> flush() async {}

  /// 成员号由房主通过名单帧分配，拿到后同步进来。
  void updateSelfMemberId(int id);

  /// 房主侧：把当前在册成员号同步进来（名单每次变化都会调用）。
  ///
  /// UDP 是无连接的，帧头里的 senderId 全凭自报；不用在册名单过滤的话，
  /// 局域网内任何设备都能用伪造的成员号抢先注册语音端点、借房主转发。
  /// 没有成员号概念的传输层（蓝牙按链路寻址）可以不覆写。
  void updateKnownMemberIds(Set<int> ids) {}

  /// 本传输层是否支持房主转移。
  ///
  /// 蓝牙房返回 false：L2CAP 的 PSM 由系统在开监听时分配，换房主意味着
  /// 整套「重新广播 + 全员重新扫描发现新 PSM」的流程，一期不做。
  bool get supportsHostTransfer;

  /// 房主转移：本机接任新房主，开始监听/广播。
  Future<bool> becomeHost();

  /// 房主转移：作为成员重连到新房主。[endpoint] 取自交接计划。
  Future<bool> reconnectToHost(String endpoint);

  /// 已知的对端端点，按成员号索引。房主用它填交接计划。
  Map<int, String> get peerEndpoints;

  /// 断开当前连接，但保持实例可复用。
  ///
  /// 离开房间走这个而不是 [dispose]：蓝牙侧的原生插件是引擎级单例，
  /// 整个 Dart 侧只能有一个 [BleL2capTransport] 实例，关掉它的流之后
  /// 就没法再扫描下一次了。
  Future<void> stop();

  /// 断开并释放全部资源，之后不可再用。
  Future<void> dispose();
}
