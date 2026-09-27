/// 更新清单的解析、字段校验与签名验证。
/// # 与生成端（`scripts/SignUpdateManifest.java`）的契约
///
/// 清单是一个**扁平**的 JSON 对象，字段顺序固定、**不含任何空白**；被签名的正是
/// 这段规范化 JSON 的 UTF-8 字节，`signature` 字段本身**不参与**签名。Java 生成端的
/// `manifestJson(...)` 与这里的 [UpdateManifest.canonicalJson] 必须逐字节一致：
///
/// ```text
/// {"versionCode":16,"versionName":"0.1.0-alpha.15","channel":"prerelease",
///  "minimumVersionCode":15,"packageName":"host.msknet.sunsetripple",
///  "apkUrl":"https://github.com/.../SunsetRipple-v0.1.0-alpha.15.apk",
///  "apkSha256":"<64 位小写 hex>","certificateSha256":"<64 位小写 hex>",
///  "summary":"...","signature":"<base64 DER>"}
/// ```
///
/// （真实输出没有换行与缩进，上面折行只为阅读。Dart 侧字段名与 Java 侧的 JSON
/// 键**逐字相同**，不做任何改名映射，避免两侧漂移。）
///
/// 签名字段之外的落盘顺序与 [canonicalJson] 完全一致，`signature` 永远追加在末尾。
///
/// # 签名算法
///
/// ECDSA **P-256 (secp256r1) + SHA-256**，DER 编码后 base64 —— 即 Java 的
/// `Signature.getInstance("SHA256withECDSA")`，配套
/// `GenerateUpdateSigningKey.java` 生成并写进 `.update-signing/` 的那对密钥。
/// 公钥内置为 [kUpdateManifestPublicKeyBase64]，私钥永不入库（只存在于发布机与
/// CI secret 中）。
///
/// 校验用 `package:pointycastle`（已是直接依赖）而不是 `package:cryptography`：
/// cryptography 2.9.0 的纯 Dart `Ecdsa.p256` 直接 `throw UnimplementedError()`，
/// 只有原生后端 `cryptography_flutter` 才真正实现 ECDSA。在 `flutter test` 与应用
/// 自身运行时的 Dart VM 里那条路都走不通，pointycastle 的 `ECDSASigner` 是纯 Dart
/// 实现，行为与 Java 的 SHA256withECDSA 一致且可离线测试。
///
/// **失败即拒绝**：任何一步（公钥非法、签名字段非 base64、DER 结构非法、曲线点不在
/// 曲线上、签名不匹配）都抛异常或返回 false，绝不放行。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../diagnostics/app_log.dart';

/// 内置的清单验签公钥：X.509 SubjectPublicKeyInfo（DER）的 base64，P-256。
///
/// 由 `scripts/GenerateUpdateSigningKey.java` 生成，输出里的
/// `sunsetRipple.updatePublicKey` 一行即为该值（也就是项目 `.update-signing/`
/// 下 `gradle-public-key.properties` 的内容）。CI 的 `UPDATE_PUBLIC_KEY_BASE64`
/// secret 必须与它**逐字节相同**，`release.yml` 会比对两者，不一致直接让发布失败：
/// 否则用户会拿到一份本应用永远验不过的清单，等于更新链路彻底失效。
/// 对应的私钥只存在于发布机与 CI secret（`UPDATE_PRIVATE_KEY_PKCS8_BASE64`），永不入库。
const String kUpdateManifestPublicKeyBase64 =
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4hliMc0CtZBiY5G++U2M2Bm9OPFUU33t4BS5'
    '/ZoOdFeIJwyjcIRQYPQ0ejNrWIhUE+SjPHFFc8JNe+Wt6Pztaw==';

/// 清单里 `packageName` 必须等于本应用的包名，防止拿到别的 App 的更新包。
const String kUpdatePackageName = 'host.msknet.sunsetripple';

/// APK 下载域名白名单。GitHub Release 资产的真实下载地址只会落在这些域名上：
///   1. `github.com/.../releases/download/...` —— 用户点开的跳转地址；
///   2. `objects.githubusercontent.com` —— Release 资产的直链；
///   3. `github-releases.githubusercontent.com` —— 旧版资产直链。
const Set<String> kTrustedApkHosts = <String>{
  'github.com',
  'objects.githubusercontent.com',
  'github-releases.githubusercontent.com',
};

/// 允许的下载端口：只允许 https 默认端口，杜绝 `:8443` 之类的旁路。
const int kTrustedApkPort = 443;

/// 下载体积上限：150 MiB。Release APK 目前约 60 MB，留出余量的同时防止
/// 被中间人换成超大文件把内存/磁盘打满。
const int kUpdateDownloadMaxBytes = 150 * 1024 * 1024;

/// `update.json` 的体积上限：64 KiB。清单只有几百字节，给足余量即可；
/// 上限存在的意义是不让服务端用超大响应把内存吃穿。
const int kUpdateManifestMaxBytes = 64 * 1024;

/// 拉取 `update.json` 的整体超时。
const Duration kUpdateManifestFetchTimeout = Duration(seconds: 30);

/// 单次下载的整体超时。
const Duration kUpdateDownloadTimeout = Duration(minutes: 5);

/// 下载临时文件所在的固定子目录名（位于应用缓存目录下）。
///
/// Android 侧用 `FileProvider` 把这一小段目录暴露给系统安装器，
/// `android/app/src/main/res/xml/file_paths.xml` 里的 `<cache-path>` 必须与它一致。
const String kUpdateDownloadDirectoryName = 'update-downloads';

/// 更新清单相关错误的基类。任何一条都不允许被吞掉后继续走安装流程。
class UpdateManifestException implements Exception {
  const UpdateManifestException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// 清单结构/字段不合法（缺字段、多字段、类型不对、格式不对）。
class UpdateManifestFormatException extends UpdateManifestException {
  const UpdateManifestFormatException(super.message);
}

/// 验签失败，或公钥本身不可用。
class UpdateManifestSignatureException extends UpdateManifestException {
  const UpdateManifestSignatureException(super.message);
}

/// 下载地址不满足 HTTPS + 域名白名单策略。
class UntrustedUpdateUrlException extends UpdateManifestException {
  const UntrustedUpdateUrlException(super.message);
}

/// 发布渠道，与 Java 侧 `channel must be stable or prerelease` 一致。
const Set<String> _channels = <String>{'stable', 'prerelease'};

final RegExp _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// 一份**已通过字段校验**的更新清单。
///
/// 字段名与 `scripts/SignUpdateManifest.java` 的 JSON 键逐字相同；构造它请走
/// [UpdateManifest.parse]（只校验字段）或 [UpdateManifest.verify]（校验 + 验签）。
class UpdateManifest {
  const UpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.channel,
    required this.minimumVersionCode,
    required this.packageName,
    required this.apkUrl,
    required this.apkSha256,
    required this.certificateSha256,
    required this.summary,
    required this.signature,
  });

  /// 参与签名的字段，顺序即 Java `manifestJson` 的拼接顺序。
  static const List<String> signedFieldOrder = <String>[
    'versionCode',
    'versionName',
    'channel',
    'minimumVersionCode',
    'packageName',
    'apkUrl',
    'apkSha256',
    'certificateSha256',
    'summary',
  ];

  /// 签名字段名；它排在规范化 JSON 的最后，且不参与签名。
  static const String signatureField = 'signature';

  /// 构建号，与 `pubspec.yaml` `version:` 的 `+N` 对应。
  final int versionCode;

  /// 语义化版本名。
  final String versionName;

  /// `stable` / `prerelease`。
  final String channel;

  /// 允许安装该包的最低 versionCode。
  final int minimumVersionCode;

  /// APK 的 applicationId（`host.msknet.sunsetripple`）。
  final String packageName;

  /// APK 的 HTTPS 下载地址。
  final String apkUrl;

  /// APK 的 SHA-256（64 位 hex，小写；比较时大小写不敏感）。
  final String apkSha256;

  /// APK 签名证书的 SHA-256（64 位 hex，小写）。
  final String certificateSha256;

  /// 本次更新的摘要（就是 Java 侧的 `summary`，来自 release notes）。
  final String summary;

  /// 签名（base64，DER 编码的 ECDSA P-256/SHA-256 签名）。
  final String signature;

  /// 解析并校验字段，**不验签**。只用于需要先把清单读进内存的场景，
  /// 例如 `release.yml` 的自检；应用侧请一律使用 [verify]。
  static UpdateManifest parse(String rawJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (e) {
      throw UpdateManifestFormatException('清单不是合法 JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateManifestFormatException('清单顶层必须是 JSON 对象');
    }

    final keys = decoded.keys.toSet();
    final unknown =
        keys.difference({...signedFieldOrder, signatureField}).toList()..sort();
    if (unknown.isNotEmpty) {
      // 不在签名范围内的字段一律拒绝：否则攻击者可以往里塞未经签名的内容。
      throw UpdateManifestFormatException('清单含未知字段: ${unknown.join(', ')}');
    }
    final missing =
        signedFieldOrder.where((field) => !keys.contains(field)).toList();
    if (missing.isNotEmpty) {
      throw UpdateManifestFormatException('清单缺少字段: ${missing.join(', ')}');
    }
    if (!keys.contains(signatureField)) {
      throw const UpdateManifestFormatException('清单缺少签名字段: signature');
    }

    final manifest = UpdateManifest(
      versionCode: _requireInt(decoded, 'versionCode'),
      versionName: _requireString(decoded, 'versionName'),
      channel: _requireString(decoded, 'channel'),
      minimumVersionCode: _requireInt(decoded, 'minimumVersionCode'),
      packageName: _requireString(decoded, 'packageName'),
      apkUrl: _requireString(decoded, 'apkUrl'),
      apkSha256: _requireString(decoded, 'apkSha256'),
      certificateSha256: _requireString(decoded, 'certificateSha256'),
      summary: _requireString(decoded, 'summary'),
      signature: _requireString(decoded, signatureField),
    );
    manifest._validateFields();
    return manifest;
  }

  /// 解析 + 校验字段 + 验签。任何一步不通过都抛异常，**不会**返回一个可疑的清单。
  ///
  /// [publicKeyBase64] 默认取内置公钥 [kUpdateManifestPublicKeyBase64]；
  /// 只有测试与 `tools/` 里的自检才应该显式传入别的公钥。
  static UpdateManifest verify(
    String rawJson, {
    String publicKeyBase64 = kUpdateManifestPublicKeyBase64,
    String expectedPackageName = kUpdatePackageName,
  }) {
    final manifest = parse(rawJson);
    if (manifest.packageName != expectedPackageName) {
      throw UpdateManifestSignatureException(
        '清单包名 ${manifest.packageName} 与本应用 $expectedPackageName 不一致',
      );
    }
    final reason = manifest.signatureFailureReason(publicKeyBase64);
    if (reason != null) {
      throw UpdateManifestSignatureException(reason);
    }
    return manifest;
  }

  /// 清单里的包下载地址（已解析）。
  Uri get apkUri => Uri.parse(apkUrl);

  /// [apkUri] 是否满足 [isTrustedUpdateUrl] 的策略。
  bool get hasTrustedUpdateUrl => isTrustedUpdateUrl(apkUri);

  /// [hasTrustedUpdateUrl] 的断言版本，不满足即抛 [UntrustedUpdateUrlException]。
  void assertTrustedUpdateUrl() {
    final uri = apkUri;
    if (!isTrustedUpdateUrl(uri)) {
      throw UntrustedUpdateUrlException(
        '拒绝下载非白名单地址: $apkUrl（必须为 https 且域名为 '
        '${kTrustedApkHosts.join(' / ')}，端口 $kTrustedApkPort）',
      );
    }
  }

  /// 更新相关的一切下载（`update.json` 清单与 APK 本体）共用的地址策略：
  /// `https` + 白名单域名 + 默认端口 + 无 `user@`。
  ///
  /// `https://github.com@evil.com/x` 这类把域名塞进 userInfo 的写法会被
  /// `userInfo` 与 `host` 两道检查同时拦下（`Uri.host` 是 `evil.com`）。
  static bool isTrustedUpdateUrl(Uri uri) =>
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.userInfo.isEmpty &&
      uri.port == kTrustedApkPort &&
      kTrustedApkHosts.contains(uri.host);

  /// 被签名的规范化 JSON（**不含** `signature`），UTF-8 编码后即签名内容。
  ///
  /// 转义规则与 Java 侧 `quote(...)` 逐字对齐：`"` `\` 与 8 种转义字符走短转义，
  /// 其余 `< 0x20` 的控制字符写 `\u00xx`（小写 hex），非 ASCII 原样输出。
  String canonicalJson() => _encode(signatureIncluded: false);

  /// 落盘形态：规范化 JSON + `,"signature":"..."`，与 Java 写出的 `update.json` 一致。
  String signedJson() => _encode(signatureIncluded: true);

  String _encode({required bool signatureIncluded}) {
    final buffer = StringBuffer('{');
    for (var index = 0; index < signedFieldOrder.length; index++) {
      if (index > 0) buffer.write(',');
      final field = signedFieldOrder[index];
      buffer.write(_quote(field));
      buffer.write(':');
      switch (field) {
        case 'versionCode':
          buffer.write(versionCode);
        case 'minimumVersionCode':
          buffer.write(minimumVersionCode);
        default:
          buffer.write(_quote(_stringField(field)));
      }
    }
    if (signatureIncluded) {
      buffer.write(',${_quote(signatureField)}:${_quote(signature)}');
    }
    buffer.write('}');
    return buffer.toString();
  }

  /// 验签失败的原因；`null` 表示通过。
  ///
  /// 区分「公钥不可用」与「签名不匹配」两类原因，便于把问题定位到发布侧还是篡改侧。
  String? signatureFailureReason(
      [String publicKeyBase64 = kUpdateManifestPublicKeyBase64]) {
    final ECPublicKey publicKey;
    try {
      publicKey = _p256PublicKeyFromSpki(publicKeyBase64);
    } on UpdateManifestSignatureException catch (e) {
      return e.message;
    }

    final ECSignature signature;
    try {
      signature = _decodeDerSignature(base64.decode(this.signature));
    } on FormatException {
      return 'signature 不是合法 base64';
    } on UpdateManifestSignatureException catch (e) {
      return e.message;
    }

    try {
      final signer = ECDSASigner(SHA256Digest());
      signer.init(false, PublicKeyParameter<ECPublicKey>(publicKey));
      final message = Uint8List.fromList(utf8.encode(canonicalJson()));
      if (!signer.verifySignature(message, signature)) {
        return '清单签名与内置公钥不匹配（内容被篡改或签名来自别的密钥）';
      }
    } catch (e) {
      return '验签过程出错: $e';
    }
    return null;
  }

  /// 即 [signatureFailureReason] 的布尔形态，失败原因会写进诊断日志。
  bool verifySignature(
      [String publicKeyBase64 = kUpdateManifestPublicKeyBase64]) {
    final reason = signatureFailureReason(publicKeyBase64);
    if (reason != null) {
      AppLog.warn('UpdateManifest', '清单验签失败: $reason');
      return false;
    }
    return true;
  }

  void _validateFields() {
    if (versionCode <= 0) {
      throw const UpdateManifestFormatException('versionCode 必须为正整数');
    }
    if (minimumVersionCode <= 0) {
      throw const UpdateManifestFormatException('minimumVersionCode 必须为正整数');
    }
    if (versionName.trim().isEmpty) {
      throw const UpdateManifestFormatException('versionName 不能为空');
    }
    if (!_channels.contains(channel)) {
      throw UpdateManifestFormatException(
          'channel 必须是 stable 或 prerelease，实际 $channel');
    }
    if (packageName.trim().isEmpty) {
      throw const UpdateManifestFormatException('packageName 不能为空');
    }
    if (summary.trim().isEmpty) {
      throw const UpdateManifestFormatException('summary 不能为空');
    }
    if (!apkUrl.startsWith('https://')) {
      throw const UpdateManifestFormatException('apkUrl 必须使用 HTTPS');
    }
    if (!_sha256Pattern.hasMatch(apkSha256)) {
      throw UpdateManifestFormatException(
          'apkSha256 必须是 64 位 hex，实际 "$apkSha256"');
    }
    if (!_sha256Pattern.hasMatch(certificateSha256)) {
      throw UpdateManifestFormatException(
          'certificateSha256 必须是 64 位 hex，实际 "$certificateSha256"');
    }
    if (signature.trim().isEmpty) {
      throw const UpdateManifestFormatException('signature 不能为空');
    }
  }

  String _stringField(String field) => switch (field) {
        'versionName' => versionName,
        'channel' => channel,
        'packageName' => packageName,
        'apkUrl' => apkUrl,
        'apkSha256' => apkSha256,
        'certificateSha256' => certificateSha256,
        'summary' => summary,
        _ => throw UpdateManifestFormatException('未知的签名字段: $field'),
      };

  static int _requireInt(Map<String, dynamic> decoded, String field) {
    final value = decoded[field];
    if (value is! int) {
      throw UpdateManifestFormatException(
          '$field 必须是整数，实际 ${value.runtimeType}');
    }
    return value;
  }

  static String _requireString(Map<String, dynamic> decoded, String field) {
    final value = decoded[field];
    if (value is! String) {
      throw UpdateManifestFormatException(
          '$field 必须是字符串，实际 ${value.runtimeType}');
    }
    return value;
  }
}

/// P-256 的域参数（`y² = x³ + ax + b (mod p)`）。
final BigInt _p256P = BigInt.parse(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    radix: 16);
final BigInt _p256A = _p256P - BigInt.from(3);
final BigInt _p256B = BigInt.parse(
    '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
    radix: 16);

/// 把 `GenerateUpdateSigningKey.java` 写出的 X.509 SubjectPublicKeyInfo（DER，base64）
/// 解成 pointycastle 的公钥对象。
///
/// Java `KeyFactory.getInstance("EC").generatePublic(new X509EncodedKeySpec(...))`
/// 对 secp256r1 的输出是**固定 91 字节**的 DER：
///
/// ```text
/// 30 59                                     SEQUENCE, 89 字节
///   30 13                                   SEQUENCE, 19 字节
///     06 07 2a 86 48 ce 3d 02 01            OID 1.2.840.10045.2.1 (ecPublicKey)
///     06 08 2a 86 48 ce 3d 03 01 07         OID 1.2.840.10045.3.1.7 (prime256v1)
///   03 42 00 04                             BIT STRING, 66 字节, 未压缩点
///     X(32) || Y(32)
/// ```
///
/// 所以这里直接钉死前缀（含曲线 OID，等于同时验证了曲线就是 P-256），
/// 再校验坐标落在域内且在曲线上。任何不符都抛 [UpdateManifestSignatureException]。
ECPublicKey _p256PublicKeyFromSpki(String publicKeyBase64) {
  const spkiPrefix = <int>[
    0x30, 0x59, //
    0x30, 0x13, //
    0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, //
    0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, //
    0x03, 0x42, 0x00, 0x04, //
  ];
  final spkiLength = spkiPrefix.length + 64;

  final Uint8List der;
  try {
    der = base64.decode(publicKeyBase64.trim());
  } on FormatException {
    throw const UpdateManifestSignatureException('更新公钥不是合法 base64');
  }
  if (der.length != spkiLength) {
    throw UpdateManifestSignatureException(
        '更新公钥长度 ${der.length} 不是 P-256 SPKI 的 $spkiLength 字节');
  }
  for (var index = 0; index < spkiPrefix.length; index++) {
    if (der[index] != spkiPrefix[index]) {
      throw const UpdateManifestSignatureException(
          '更新公钥不是 prime256v1 的 SPKI 编码');
    }
  }

  final x =
      _bigIntFromBytes(der.sublist(spkiPrefix.length, spkiPrefix.length + 32));
  final y = _bigIntFromBytes(der.sublist(spkiPrefix.length + 32));
  if (x <= BigInt.zero || x >= _p256P || y <= BigInt.zero || y >= _p256P) {
    throw const UpdateManifestSignatureException('更新公钥坐标超出 P-256 域');
  }
  if ((y * y - (x * x * x + _p256A * x + _p256B)) % _p256P != BigInt.zero) {
    throw const UpdateManifestSignatureException('更新公钥不在 P-256 曲线上');
  }

  final domainParameters = ECCurve_secp256r1();
  final ecCurve = domainParameters.curve;
  return ECPublicKey(ecCurve.createPoint(x, y), domainParameters);
}

/// 解析 ECDSA 签名的 DER 编码：`SEQUENCE { INTEGER r, INTEGER s }`。
ECSignature _decodeDerSignature(List<int> der) {
  final reader = _DerReader(der);
  reader.readExpectedTag(0x30, 'SEQUENCE');
  final bodyLength = reader.readLength();
  if (bodyLength != reader.remaining) {
    throw const UpdateManifestSignatureException('签名 DER 长度与实际内容不一致');
  }
  final r = reader.readInteger('r');
  final s = reader.readInteger('s');
  if (reader.remaining != 0) {
    throw const UpdateManifestSignatureException('签名 DER 尾部有多余字节');
  }
  if (r <= BigInt.zero || s <= BigInt.zero) {
    throw const UpdateManifestSignatureException('签名值 r/s 必须为正整数');
  }
  return ECSignature(r, s);
}

/// 最小 DER 读取器：只接受定长编码与最短长度形式（DER 的要求），
/// 任何不合规的字节都直接抛异常而不是猜。
class _DerReader {
  _DerReader(this._bytes);

  final List<int> _bytes;
  int _offset = 0;

  int get remaining => _bytes.length - _offset;

  void readExpectedTag(int tag, String label) {
    if (remaining <= 0) {
      throw UpdateManifestSignatureException('签名 DER 截断：缺少 $label');
    }
    final actual = _bytes[_offset++];
    if (actual != tag) {
      throw UpdateManifestSignatureException(
          '签名 DER 期望 $label(0x${tag.toRadixString(16)})，实际 0x${actual.toRadixString(16)}');
    }
  }

  int readLength() {
    if (remaining <= 0) {
      throw const UpdateManifestSignatureException('签名 DER 截断：缺少长度');
    }
    final first = _bytes[_offset++];
    if (first < 0x80) return first;
    final count = first & 0x7f;
    if (count == 0) {
      throw const UpdateManifestSignatureException('签名 DER 不支持不定长编码');
    }
    if (count > 4 || count > remaining) {
      throw const UpdateManifestSignatureException('签名 DER 长度字段非法');
    }
    var value = 0;
    for (var index = 0; index < count; index++) {
      value = (value << 8) | _bytes[_offset++];
    }
    if (value < 0x80) {
      throw const UpdateManifestSignatureException('签名 DER 长度未使用最短形式');
    }
    return value;
  }

  BigInt readInteger(String label) {
    readExpectedTag(0x02, 'INTEGER($label)');
    final length = readLength();
    if (length == 0 || length > remaining) {
      throw UpdateManifestSignatureException('签名 DER 的 $label 长度非法');
    }
    final body = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    if (body.first & 0x80 != 0) {
      throw UpdateManifestSignatureException('签名 DER 的 $label 是负数');
    }
    if (body.length > 1 && body[0] == 0x00 && body[1] & 0x80 == 0) {
      throw UpdateManifestSignatureException('签名 DER 的 $label 有冗余前导零');
    }
    return _bigIntFromBytes(body);
  }
}

BigInt _bigIntFromBytes(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

/// 与 Java `SignUpdateManifest.quote` 逐字对齐的字符串字面量编码。
String _quote(String value) => '"${_quoteEscape(value)}"';

String _quoteEscape(String value) {
  final buffer = StringBuffer();
  for (final unit in value.codeUnits) {
    buffer.write(_escapeCodeUnit(unit));
  }
  return buffer.toString();
}

String _escapeCodeUnit(int unit) {
  switch (unit) {
    case 0x22:
      return r'\"';
    case 0x5c:
      return r'\\';
    case 0x08:
      return r'\b';
    case 0x0c:
      return r'\f';
    case 0x0a:
      return r'\n';
    case 0x0d:
      return r'\r';
    case 0x09:
      return r'\t';
  }
  if (unit < 0x20) {
    return '\\u${unit.toRadixString(16).padLeft(4, '0')}';
  }
  return String.fromCharCode(unit);
}
