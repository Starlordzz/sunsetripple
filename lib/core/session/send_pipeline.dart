import '../protocol/frame.dart';

/// 发送链路与协议序号计数器，从 `RoomSession` 外提。
///
/// 为什么单独成类：这条链路出过一个静默的坑——`attachTransport` 会把发送出口
/// 覆写成 `transport.send`，任何在那之前赋值的观测钩子都会被悄悄丢掉，表现为
/// 「帧一条都发不出去，且没有任何报错」。把「最内层出口 / 改写层 / 观察者」的
/// 串联规则收进一个对象后，重建链路只有一处实现：观察者与改写层在换传输层时
/// 按注册顺序重新串好，不再依赖赋值先后。
///
/// 职责边界：
///   - 只做帧的**转发链**与序号分配
///   - **不**做安全信封编解码（那是会话层 `RoomSession.sendFrame` 的职责）
class SendPipeline {
  SendPipeline({void Function(Frame frame)? sink}) {
    if (sink != null) replaceSink(sink);
  }

  void Function(Frame frame)? _sink;
  void Function(Frame frame)? _output;

  /// 每次发送都会调用的观察者（测试、埋点用）。只读，不参与改写。
  final List<void Function(Frame frame)> _observers = [];

  /// 可选的改写层（例如测试里模拟丢包）。设置后由它决定是否放行。
  void Function(Frame frame, void Function(Frame) next)? _interceptor;

  int _seq = 0;

  /// 链路出口。没有接任何出口时为 null（帧被丢弃）。
  void Function(Frame frame)? get output => _output;

  /// 是否已经接上传输层出口。
  bool get isAttached => _sink != null;

  /// 下一个协议序号（16 位回绕）。可靠与不可靠通道共用这一个计数器。
  int nextSeq() {
    _seq = (_seq + 1) & 0xFFFF;
    return _seq;
  }

  /// 替换最内层出口（通常是传输层的 `send`）。已注册的观察者与改写层会被重新串上。
  void replaceSink(void Function(Frame frame)? sink) {
    _sink = sink;
    _rebuild();
  }

  /// 注册一个只读观察者，观察每次实际发出的帧。
  ///
  /// 相比 [replaceSink]，它**不会**被换传输层抹掉——`attachTransport` 重建链路时
  /// 会把观察者重新串进去，这正是它存在的理由。
  void addObserver(void Function(Frame frame) observer) {
    _observers.add(observer);
    if (_sink != null) _rebuild();
  }

  /// 注册一个改写层（例如测试里模拟丢包）。传 null 移除。
  void setInterceptor(
    void Function(Frame frame, void Function(Frame) next)? interceptor,
  ) {
    _interceptor = interceptor;
    if (_sink != null) _rebuild();
  }

  /// 把一帧交给链路出口。没接出口时静默丢弃（调用方看到的是「什么都没发生」，
  /// 与旧行为一致：旧实现里 `onSendFrame` 为 null 就是不发）。
  void emit(Frame frame) => _output?.call(frame);

  void _rebuild() {
    final sink = _sink;
    if (sink == null) {
      _output = null;
      return;
    }

    void Function(Frame) chain = sink;

    // 改写层紧贴出口：由它决定这一帧最终是否落到传输层。
    final interceptor = _interceptor;
    if (interceptor != null) {
      final next = chain;
      chain = (frame) => interceptor(frame, next);
    }

    // 观察者串在最外层，只读不改写：调用顺序是 观察者 → 改写层 → 出口。
    // 也就是说观察者看到的是「尝试发出」的每一帧，改写层丢掉的帧也会被它记到，
    // 这是旧实现的既有语义（埋点关心的是会话想发什么，不是网卡收到了什么）。
    for (final observer in _observers.reversed) {
      final next = chain;
      chain = (frame) {
        observer(frame);
        next(frame);
      };
    }

    _output = chain;
  }
}
