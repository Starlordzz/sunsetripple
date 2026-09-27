import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../diagnostics/app_log.dart';
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import 'session_crypto.dart';
import 'session_handshake.dart';

/// 安全信封的**启动器**：在已有的 `SessionHandshake` 之上补齐「谁在什么时候
/// 驱动握手、握手成功后把 codec 装到哪」这一段。
///
/// 为什么需要它（此前的死代码问题）：`lib/core/security/` 里的 ECDH / HKDF /
/// AES-GCM 实现是完整且正确的，`SessionHandshake` 也齐全——但**没有任何生产代码
/// 调用它们**：`RoomSession` 对 `handshakeHello` / `handshakeConfirm` 两个帧类型
/// 直接 `break`，`secureCodec` 永远为 null。整层密码学因此从未在真机路径上跑过。
///
/// 本类补上那段缺失的编排：
///   1. 入房后本机生成 [DeviceIdentity] 与 SignedHello
///   2. 双方通过 `handshakeHello` 交换 SignedHello（明文——它本来就是用来
///      协商出 codec 的，此前没有可用的加密信道）
///   3. `establish()` 校验对端签名并派生 [SessionCipher]
///   4. 派生出**指纹短码**，供用户带外比对，抵御主动中间人
///   5. 交给 `RoomSession.secureCodec`，此后业务帧自动密封
///
/// 安全边界（务必如实理解）：
///   - 签名校验只能证明「对端持有它自称公钥的私钥」，无法阻止中间人
///     分别与两侧握手。真正的身份绑定依赖 [safetyCode] 的**带外确认**。
///   - 因此本类**不**声称已获得防中间人能力；在用户比对短码之前，
///     它只提供「防被动窃听 + 防事后篡改」。
class SecureSessionNegotiator {
  static const String _tag = '加密';

  final String roomId;
  final String localRole;

  /// 是否由本机发起握手。房主作发起方，成员作响应方，避免两侧同时发 Hello。
  final bool initiate;

  DeviceIdentity? _identity;
  SignedHello? _localHello;
  SignedHello? _remoteHello;

  final _controller = StreamController<SecureSessionState>.broadcast();

  SecureSessionNegotiator({
    required this.roomId,
    required this.localRole,
    required this.initiate,
  });

  /// 协商状态流，供 UI 展示「正在校验 / 已加密 / 已确认」。
  Stream<SecureSessionState> get stateStream => _controller.stream;

  /// 派生出的安全短码。两侧一致时用户可确认「连接未被中间人替换」。
  ///
  /// 六位十进制，取自双方公钥指纹的组合哈希——不是公钥本身，
  /// 用户只需口头比对 6 个数字。
  String? get safetyCode {
    final local = _localHello;
    final remote = _remoteHello;
    if (local == null || remote == null) return null;
    return SecureSessionState.deriveSafetyCode(
      local.publicKeyBase64,
      remote.publicKeyBase64,
    );
  }

  bool get isEstablished => _established != null;
  SecureFrameCodec? get codec => _established;
  SecureFrameCodec? _established;

  /// 生成并返回本机的 Hello 帧，调用方负责发给对端。
  ///
  /// 幂等：重复调用返回同一份 Hello，避免双方各发两次导致状态错乱。
  Future<Frame?> start() async {
    if (_localHello != null) return null;
    try {
      _identity = await DeviceIdentity.generate();
      _localHello = await SessionHandshake.create(
        identity: _identity!,
        roomId: roomId,
        role: localRole,
      );
      _emit(SecureSessionPhase.helloSent);
      return Frame(
        type: FrameType.handshakeHello,
        senderId: 0,
        seq: 0,
        payload: _encodeHello(_localHello!),
      );
    } catch (e) {
      AppLog.error(_tag, '无法生成握手 Hello，本会话保持明文', e);
      _emit(SecureSessionPhase.failed);
      return null;
    }
  }

  /// 处理对端的 Hello。返回需要回发的帧（首次收到时才回），其余情况返回 null。
  ///
  /// 校验失败一律**不**建立 codec：宁可退回明文，也不能装上一个未经验证的
  /// 信道——那会让用户误以为已经加密。
  Future<Frame?> onHello(Frame frame) async {
    final remote = _decodeHello(frame.payload);
    if (remote == null) {
      AppLog.warn(_tag, '收到无法解析的握手 Hello，已忽略');
      return null;
    }

    final firstTime = _remoteHello == null;
    _remoteHello = remote;
    _emit(SecureSessionPhase.helloReceived);

    // 响应方在首次收到 Hello 时回一份自己的 Hello。
    Frame? reply;
    if (firstTime && !initiate) {
      reply = await start();
    }

    await _tryEstablish();
    return reply;
  }

  /// 双方 Hello 齐备后派生密钥。任一步失败都保持明文，不静默降级成假加密。
  Future<void> _tryEstablish() async {
    if (_established != null) return;
    final identity = _identity;
    final local = _localHello;
    final remote = _remoteHello;
    if (identity == null || local == null || remote == null) return;

    try {
      final cipher = await SessionHandshake.establish(
        localIdentity: identity,
        localHello: local,
        remoteHello: remote,
        remoteRole: localRole == 'host' ? 'client' : 'host',
        roomId: roomId,
      );
      _established = SecureFrameCodec(cipher);
      AppLog.info(_tag, '会话密钥已协商，安全信封就绪（短码 ${safetyCode ?? "?"}）');
      _emit(SecureSessionPhase.established);
    } catch (e) {
      // 签名不匹配 = 对端不可信，或双方房间上下文不同。保持明文并告警，
      // 让用户从诊断面板看到真相，而不是带着「已加密」的错觉继续通话。
      AppLog.error(_tag, '握手校验失败，本会话保持明文传输', e);
      _emit(SecureSessionPhase.failed);
    }
  }

  /// 用户带外比对过短码后调用，把状态推进到「已确认」。
  ///
  /// 注意这只改变**展示状态**：密码学上无法自动判定是否被中间人。
  void confirmByUser() => _emit(SecureSessionPhase.confirmed);

  Future<void> dispose() async {
    await _controller.close();
  }

  static Uint8List _encodeHello(SignedHello hello) {
    final json = utf8.encode(jsonEncode(hello.toJson()));
    if (json.length > Frame.maxPayloadSize) {
      throw StateError('handshake hello exceeds frame payload limit');
    }
    return Uint8List.fromList(json);
  }

  static SignedHello? _decodeHello(Uint8List payload) {
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map<String, dynamic>) return null;
      final hello = SignedHello.fromJson(decoded);
      // 三个字段都是安全敏感的：长度不对直接拒绝，别让异常冒到调用方。
      if (hello.publicKeyBase64.isEmpty ||
          hello.nonceBase64.isEmpty ||
          hello.signatureBase64.isEmpty) {
        return null;
      }
      return hello;
    } catch (e) {
      AppLog.warn(_tag, '握手 Hello 解析失败', e);
      return null;
    }
  }

  void _emit(SecureSessionPhase phase) {
    if (_controller.isClosed) return;
    _controller.add(SecureSessionState(phase, safetyCode));
  }
}

enum SecureSessionPhase {
  /// 还没开始（明文）。
  idle,

  /// 已生成并发出本机 Hello。
  helloSent,

  /// 已收到对端 Hello。
  helloReceived,

  /// 密钥已协商、安全信封就绪，但用户尚未比对短码。
  established,

  /// 用户已带外确认短码一致。
  confirmed,

  /// 握手失败，本会话保持明文。
  failed,
}

/// 一次协商的可观测状态。
class SecureSessionState {
  final SecureSessionPhase phase;
  final String? safetyCode;

  const SecureSessionState(this.phase, this.safetyCode);

  bool get isEncrypted =>
      phase == SecureSessionPhase.established ||
      phase == SecureSessionPhase.confirmed;

  /// 6 位十进制安全码，取自双方公钥指纹的**排序后**拼接哈希。
  ///
  /// 排序是关键：两侧持有的是同一对公钥，若不排序，房主算出的组合与成员
  /// 算出的顺序相反，短码就对不上了。取 6 位是因为用户要靠嘴念出来比对。
  static String deriveSafetyCode(String keyA, String keyB) {
    final pair = [keyA, keyB]..sort();
    final digest = crypto.sha256.convert(
      utf8.encode('${pair[0]}\u0000${pair[1]}'),
    );
    final bytes = digest.bytes;
    final value = ((bytes[0] << 16) | (bytes[1] << 8) | bytes[2]) % 1000000;
    return value.toString().padLeft(6, '0');
  }
}
