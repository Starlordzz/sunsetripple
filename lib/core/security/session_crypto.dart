import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as crypt;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/prime256v1.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/ec_key_generator.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import '../diagnostics/app_log.dart';

const String _tag = '加密';

final ECDomainParameters _domainParams = ECCurve_prime256v1();

/// 设备指纹计算工具。与 Kotlin 版 DeviceFingerprint 完全一致。
class DeviceFingerprint {
  /// 全量指纹：SHA-256 摘要，十六进制大写，冒号分隔（如 "3A:5F:..."）。
  static String full(List<int> publicKey) {
    final digest = crypto.sha256.convert(publicKey).bytes;
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  }

  /// 6 位安全短码：取 SHA-256 前 4 字节大端无符号整数模 1,000,000，分成三三两段（如 "123 456"）。
  static String shortCode(List<int> publicKey) {
    final digest = crypto.sha256.convert(publicKey).bytes;
    final byteData = ByteData.sublistView(Uint8List.fromList(digest));
    final value = byteData.getUint32(0, Endian.big) % 1000000;
    final padded = value.toString().padLeft(6, '0');
    return '${padded.substring(0, 3)} ${padded.substring(3, 6)}';
  }
}

/// 设备身份信息（ECDH / ECDSA P-256 密钥对）。
class DeviceIdentity {
  final ECPrivateKey privateKey;
  final ECPublicKey publicKey;
  final Uint8List publicKeyBytes;
  final String publicKeyBase64;
  final String fingerprint;
  final String shortCode;

  DeviceIdentity._({
    required this.privateKey,
    required this.publicKey,
    required this.publicKeyBytes,
    required this.publicKeyBase64,
    required this.fingerprint,
    required this.shortCode,
  });

  /// 生成新的设备 EC P-256 身份密钥对。
  static Future<DeviceIdentity> generate() async {
    final secureRandom = FortunaRandom();
    final seed = Uint8List(32);
    final random = Random.secure();
    for (int i = 0; i < 32; i++) {
      seed[i] = random.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seed));

    final keyGen = ECKeyGenerator();
    keyGen.init(ParametersWithRandom(
      ECKeyGeneratorParameters(_domainParams),
      secureRandom,
    ));

    final pair = keyGen.generateKeyPair();
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;

    // 转换为标准 65 字节非压缩公钥 (0x04 || X[32] || Y[32])
    final pkBytes = pub.Q!.getEncoded(false);
    final base64Str = base64.encode(pkBytes);

    return DeviceIdentity._(
      privateKey: priv,
      publicKey: pub,
      publicKeyBytes: pkBytes,
      publicKeyBase64: base64Str,
      fingerprint: DeviceFingerprint.full(pkBytes),
      shortCode: DeviceFingerprint.shortCode(pkBytes),
    );
  }

  /// 使用设备私钥对载荷签名 (ECDSA with SHA-256, DER 编码)。
  Future<Uint8List> sign(Uint8List payload) async {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64));
    signer.init(true, PrivateKeyParameter(privateKey));
    final sig = signer.generateSignature(payload) as ECSignature;

    final seq = ASN1Sequence(elements: [
      ASN1Integer(sig.r),
      ASN1Integer(sig.s),
    ]);
    return seq.encode();
  }
}

/// 验证设备签名 (ECDSA with SHA-256, DER 编码)。
Future<bool> verifyDeviceSignature(
  String publicKeyBase64,
  Uint8List payload,
  Uint8List signatureBytes,
) async {
  try {
    final pkBytes = base64.decode(publicKeyBase64);
    if (pkBytes.length < 65 || pkBytes[0] != 0x04) {
      return false;
    }

    final point = _domainParams.curve.decodePoint(pkBytes);
    if (point == null) return false;
    final pubKey = ECPublicKey(point, _domainParams);

    final parser = ASN1Parser(signatureBytes);
    final seq = parser.nextObject() as ASN1Sequence;
    final r = (seq.elements![0] as ASN1Integer).integer!;
    final s = (seq.elements![1] as ASN1Integer).integer!;

    final signer = ECDSASigner(SHA256Digest());
    signer.init(false, PublicKeyParameter(pubKey));
    return signer.verifySignature(payload, ECSignature(r, s));
  } catch (e) {
    AppLog.warn(_tag, '验证设备签名失败：$e');
    return false;
  }
}

/// 密文数据包：12 字节 Nonce + 密文 (含 16 字节 Auth Tag)。
class EncryptedPacket {
  final Uint8List nonce;
  final Uint8List ciphertext;

  EncryptedPacket({required this.nonce, required this.ciphertext});
}

/// 基于 AES-256-GCM 的会话加密器。
///
/// 具备 12 字节 Nonce、128 位认证标签、65536 深度 Nonce 防重放窗口。
class SessionCipher {
  static const int nonceBytes = 12;
  static const int tagBits = 128;
  static const int tagBytes = 16;
  static const int maxSeenNonces = 65536;

  final crypt.SecretKey _secretKey;
  final crypt.AesGcm _aesGcm = crypt.AesGcm.with256bits(nonceLength: nonceBytes);
  final Set<String> _seenNonces = <String>{};
  final List<String> _nonceOrder = <String>[];
  final Random _random = Random.secure();

  SessionCipher._(this._secretKey);

  /// 直接从 32 字节原始密钥构造加密器。
  static Future<SessionCipher> fromKey(Uint8List keyBytes) async {
    if (keyBytes.length != 32) {
      throw ArgumentError('AES-256 key required (must be 32 bytes)');
    }
    final secretKey = crypt.SecretKeyData(keyBytes);
    return SessionCipher._(secretKey);
  }

  /// 通过 ECDH 密钥协商与 HKDF-SHA256 派生会话加密器。
  static Future<SessionCipher> establish({
    required DeviceIdentity localIdentity,
    required String remotePublicKeyBase64,
    required Uint8List roomContext,
  }) async {
    final pkBytes = base64.decode(remotePublicKeyBase64);
    final remotePoint = _domainParams.curve.decodePoint(pkBytes);
    if (remotePoint == null) {
      throw ArgumentError('invalid remote EC public key point');
    }

    // ECDH: S = d_local * Q_remote
    final sharedPoint = remotePoint * localIdentity.privateKey.d!;
    if (sharedPoint == null || sharedPoint.isInfinity) {
      throw StateError('invalid ECDH shared point');
    }

    final xBigInt = sharedPoint.x!.toBigInteger()!;
    final sharedSecret = Uint8List(32);
    final rawX = _bigIntToBytes(xBigInt);
    if (rawX.length > 32) {
      sharedSecret.setRange(0, 32, rawX.sublist(rawX.length - 32));
    } else {
      sharedSecret.setRange(32 - rawX.length, 32, rawX);
    }

    final keyBytes = _hkdf(
      secret: sharedSecret,
      salt: roomContext,
      info: Uint8List.fromList(utf8.encode('sunset-ripple-session')),
      length: 32,
    );

    return SessionCipher.fromKey(keyBytes);
  }

  static Uint8List _bigIntToBytes(BigInt number) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    final len = hex.length ~/ 2;
    final result = Uint8List(len);
    for (int i = 0; i < len; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// HKDF-SHA256 (Extract & Expand) 派生函数。
  static Uint8List _hkdf({
    required Uint8List secret,
    required Uint8List salt,
    required Uint8List info,
    required int length,
  }) {
    final actualSalt = salt.isEmpty ? Uint8List(32) : salt;
    final hmacExtract = crypto.Hmac(crypto.sha256, actualSalt);
    final prk = Uint8List.fromList(hmacExtract.convert(secret).bytes);

    final output = Uint8List(length);
    var previous = <int>[];
    var offset = 0;
    var counter = 1;

    final hmacExpand = crypto.Hmac(crypto.sha256, prk);
    while (offset < length) {
      final input = <int>[...previous, ...info, counter];
      previous = hmacExpand.convert(input).bytes;
      final count = min(previous.length, length - offset);
      output.setRange(offset, offset + count, previous.sublist(0, count));
      offset += count;
      counter++;
    }

    return output;
  }

  /// 加密明文，附加关联数据 AAD。
  Future<EncryptedPacket> encrypt(
    Uint8List plaintext, {
    Uint8List? associatedData,
  }) async {
    final nonce = Uint8List(nonceBytes);
    for (int i = 0; i < nonceBytes; i++) {
      nonce[i] = _random.nextInt(256);
    }

    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: _secretKey,
      nonce: nonce,
      aad: associatedData ?? Uint8List(0),
    );

    // secretBox.cipherText + secretBox.mac.bytes (16 bytes tag)
    final ciphertext = Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
    ciphertext.setRange(0, secretBox.cipherText.length, secretBox.cipherText);
    ciphertext.setRange(
      secretBox.cipherText.length,
      ciphertext.length,
      secretBox.mac.bytes,
    );

    return EncryptedPacket(nonce: nonce, ciphertext: ciphertext);
  }

  /// 解密密文并校验防重放及认证标签。
  Future<Uint8List> decrypt(
    EncryptedPacket packet, {
    Uint8List? associatedData,
  }) async {
    final nonceId = base64.encode(packet.nonce);
    if (_seenNonces.contains(nonceId)) {
      throw StateError('replayed encrypted frame');
    }

    _seenNonces.add(nonceId);
    _nonceOrder.add(nonceId);
    if (_nonceOrder.length > maxSeenNonces) {
      final oldest = _nonceOrder.removeAt(0);
      _seenNonces.remove(oldest);
    }

    if (packet.ciphertext.length < tagBytes) {
      _seenNonces.remove(nonceId);
      _nonceOrder.remove(nonceId);
      throw ArgumentError('ciphertext is shorter than authentication tag');
    }

    final ctLen = packet.ciphertext.length - tagBytes;
    final cipherTextOnly = packet.ciphertext.sublist(0, ctLen);
    final macBytes = packet.ciphertext.sublist(ctLen);

    try {
      final secretBox = crypt.SecretBox(
        cipherTextOnly,
        nonce: packet.nonce,
        mac: crypt.Mac(macBytes),
      );

      final decrypted = await _aesGcm.decrypt(
        secretBox,
        secretKey: _secretKey,
        aad: associatedData ?? Uint8List(0),
      );

      return Uint8List.fromList(decrypted);
    } catch (e) {
      // 校验失败时将 nonce 移除，避免损坏包占用合法重试窗口
      _seenNonces.remove(nonceId);
      _nonceOrder.remove(nonceId);
      rethrow;
    }
  }
}

