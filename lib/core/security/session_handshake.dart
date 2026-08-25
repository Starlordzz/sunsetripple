import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import 'session_crypto.dart';

/// 签名握手 Hello 包。
class SignedHello {
  final String publicKeyBase64;
  final String nonceBase64;
  final String signatureBase64;

  SignedHello({
    required this.publicKeyBase64,
    required this.nonceBase64,
    required this.signatureBase64,
  });

  Map<String, dynamic> toJson() => {
        'publicKey': publicKeyBase64,
        'nonce': nonceBase64,
        'signature': signatureBase64,
      };

  factory SignedHello.fromJson(Map<String, dynamic> json) => SignedHello(
        publicKeyBase64: json['publicKey'] as String,
        nonceBase64: json['nonce'] as String,
        signatureBase64: json['signature'] as String,
      );
}

/// 端到端会话密钥协商状态机。
class SessionHandshake {
  static const String protocol = 'sunset-ripple-alpha5';

  /// 发起端或接收端生成自己的 SignedHello。
  static Future<SignedHello> create({
    required DeviceIdentity identity,
    required String roomId,
    required String role,
  }) async {
    final random = Random.secure();
    final nonce = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      nonce[i] = random.nextInt(256);
    }
    final nonceBase64 = base64.encode(nonce);

    final payload = _transcript(
      roomId: roomId,
      role: role,
      publicKeyBase64: identity.publicKeyBase64,
      nonceBase64: nonceBase64,
    );

    final signature = await identity.sign(payload);
    final signatureBase64 = base64.encode(signature);

    return SignedHello(
      publicKeyBase64: identity.publicKeyBase64,
      nonceBase64: nonceBase64,
      signatureBase64: signatureBase64,
    );
  }

  /// 结合对端的 SignedHello 与本端身份，校验对端签名并派生会话加密器。
  static Future<SessionCipher> establish({
    required DeviceIdentity localIdentity,
    required SignedHello localHello,
    required SignedHello remoteHello,
    required String remoteRole,
    required String roomId,
  }) async {
    final remoteNonce = base64.decode(remoteHello.nonceBase64);
    if (remoteNonce.length != 32) {
      throw ArgumentError('invalid handshake nonce');
    }

    final remoteTranscript = _transcript(
      roomId: roomId,
      role: remoteRole,
      publicKeyBase64: remoteHello.publicKeyBase64,
      nonceBase64: remoteHello.nonceBase64,
    );

    final remoteSig = base64.decode(remoteHello.signatureBase64);
    final isValid = await verifyDeviceSignature(
      remoteHello.publicKeyBase64,
      remoteTranscript,
      Uint8List.fromList(remoteSig),
    );

    if (!isValid) {
      throw StateError('invalid device signature');
    }

    final localNonce = base64.decode(localHello.nonceBase64);
    final nonces = [localNonce, remoteNonce];
    nonces.sort((a, b) => _compareBytes(a, b));

    final combined = <int>[
      ...utf8.encode(roomId),
      ...nonces[0],
      ...nonces[1],
    ];
    final roomContext = Uint8List.fromList(crypto.sha256.convert(combined).bytes);

    return SessionCipher.establish(
      localIdentity: localIdentity,
      remotePublicKeyBase64: remoteHello.publicKeyBase64,
      roomContext: roomContext,
    );
  }

  static Uint8List _transcript({
    required String roomId,
    required String role,
    required String publicKeyBase64,
    required String nonceBase64,
  }) {
    final parts = [protocol, roomId, role, publicKeyBase64, nonceBase64];
    final joined = parts.join('\u0000');
    return Uint8List.fromList(utf8.encode(joined));
  }

  static int _compareBytes(List<int> left, List<int> right) {
    final len = min(left.length, right.length);
    for (int i = 0; i < len; i++) {
      final comp = (left[i] & 0xFF).compareTo(right[i] & 0xFF);
      if (comp != 0) return comp;
    }
    return left.length.compareTo(right.length);
  }
}

/// 安全信封编解码器：将普通 [Frame] 密封打包为 [FrameType.sealed] 帧，或反向解封。
class SecureFrameCodec {
  static const int nonceBytes = 12;
  static const int tagBytes = 16;
  static const int protocolVersion = 1;

  /// 内层明文载荷上限（外层 512 字节减去 6 字节帧头与 28 字节 Nonce+Tag）。
  static const int maxPlaintextPayload =
      Frame.maxPayloadSize - Frame.headerSize - nonceBytes - tagBytes;

  final SessionCipher cipher;

  SecureFrameCodec(this.cipher);

  /// 将明文帧包装密封为 SEALED 帧。
  Future<Frame> seal(Frame frame) async {
    if (frame.type == FrameType.sealed) {
      throw ArgumentError('frame is already sealed');
    }

    final encoded = frame.encode();
    final aad = _associatedData(frame.senderId, frame.seq);
    final packet = await cipher.encrypt(encoded, associatedData: aad);

    final payload = Uint8List(packet.nonce.length + packet.ciphertext.length);
    payload.setRange(0, packet.nonce.length, packet.nonce);
    payload.setRange(packet.nonce.length, payload.length, packet.ciphertext);

    if (payload.length > Frame.maxPayloadSize) {
      throw StateError('sealed frame exceeds transport limit');
    }

    return Frame(
      type: FrameType.sealed,
      senderId: frame.senderId,
      seq: frame.seq,
      payload: payload,
    );
  }

  /// 解封 SEALED 帧还原出明文帧。
  Future<Frame> open(Frame frame) async {
    if (frame.type != FrameType.sealed) {
      throw ArgumentError('sealed frame required');
    }
    if (frame.payload.length < nonceBytes + tagBytes) {
      throw ArgumentError('sealed frame is truncated');
    }

    final nonce = Uint8List.sublistView(frame.payload, 0, nonceBytes);
    final ciphertext = Uint8List.sublistView(frame.payload, nonceBytes);
    final aad = _associatedData(frame.senderId, frame.seq);

    final packet = EncryptedPacket(nonce: nonce, ciphertext: ciphertext);
    final plaintext = await cipher.decrypt(packet, associatedData: aad);

    final decoded = Frame.decode(plaintext);
    if (decoded == null) {
      throw const FormatException('failed to decode decrypted frame');
    }
    if (decoded.senderId != frame.senderId || decoded.seq != frame.seq) {
      throw StateError('sealed frame header mismatch');
    }

    return decoded;
  }

  static Uint8List _associatedData(int senderId, int sequence) {
    final buffer = Uint8List(5);
    final byteData = ByteData.sublistView(buffer);
    byteData.setUint8(0, FrameType.sealed.value);
    byteData.setUint8(1, senderId);
    byteData.setUint16(2, sequence, Endian.big);
    byteData.setUint8(4, protocolVersion);
    return buffer;
  }
}

