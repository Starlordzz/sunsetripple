import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/update/update_manifest.dart';
import 'package:sunset_ripple/core/update/update_service.dart';

/// 真实签出的更新清单：`scripts/SignUpdateManifest.java` + 项目更新私钥
/// （`.update-signing/update-private-key.pk8`，不入库）产出后**原样粘贴**。
///
/// 它的 summary 里刻意塞满了需要转义的字符（`\` `"` `\t` `\u0001` 与中文），
/// 用来证明 Dart 侧 [UpdateManifest.canonicalJson] 的转义与 Java 侧
/// `SignUpdateManifest.quote(...)` 逐字节一致 —— 只要有一处不一致，签名就验不过。
///
/// 重新生成（私钥换了就得跟 [kUpdateManifestPublicKeyBase64] 一起换）：
/// ```sh
/// java scripts/SignUpdateManifest.java \
///   --version-code 16 --version-name 0.1.0-alpha.15 --channel prerelease \
///   --minimum-version-code 15 --package-name host.msknet.sunsetripple \
///   --apk-url "https://github.com/Starlordzz/sunsetripple/releases/download/\
/// v0.1.0-alpha.15/SunsetRipple-v0.1.0-alpha.15.apk" \
///   --certificate-sha256 32b678ce045c645cea8ea6090a96f2360c3190217a389a5c7d6b6c7fc28f67ff \
///   --summary-file <把 summary 写成反斜杠/引号/制表符/0x01 各一份的文件> \
///   --apk <内容为 "_fixtureApkBody" 的文件> \
///   --private-key .update-signing/update-private-key.pk8 \
///   --public-key-base64 "$(cat .update-signing/gradle-public-key.properties | cut -d= -f2)" \
///   --output update.json
/// ```
const String _escapeFixture =
    r'''{"versionCode":16,"versionName":"0.1.0-alpha.15","channel":"prerelease","minimumVersionCode":15,"packageName":"host.msknet.sunsetripple","apkUrl":"https://github.com/Starlordzz/sunsetripple/releases/download/v0.1.0-alpha.15/SunsetRipple-v0.1.0-alpha.15.apk","apkSha256":"82c6f31133b9c797d027643860f7be3b8954a2f3d5adc787f1ebb966e4eec4a7","certificateSha256":"32b678ce045c645cea8ea6090a96f2360c3190217a389a5c7d6b6c7fc28f67ff","summary":"第 15 版更新\n- 反斜杠 \\ 与引号 \" 都必须转义\n- 制表符\t与不可见控制字符 \u0001 混排\n- 结语","signature":"MEUCIQDZEOd9O+x5OflPWDhPpRC+c6EbbZarriF8NmTlXz30twIgCV1HpDr4k/QFeh0JT8XzBTECxCcbi1RioveCDEayhrU="}''';

/// 上一条清单去掉 `,"signature":"…"` 后补回右花括号的形态 —— 也就是 Java 实际
/// 签名的那段规范化 JSON 的**独立副本**（不是由 Dart 侧算出来的）。
const String _escapeFixtureCanonical =
    r'''{"versionCode":16,"versionName":"0.1.0-alpha.15","channel":"prerelease","minimumVersionCode":15,"packageName":"host.msknet.sunsetripple","apkUrl":"https://github.com/Starlordzz/sunsetripple/releases/download/v0.1.0-alpha.15/SunsetRipple-v0.1.0-alpha.15.apk","apkSha256":"82c6f31133b9c797d027643860f7be3b8954a2f3d5adc787f1ebb966e4eec4a7","certificateSha256":"32b678ce045c645cea8ea6090a96f2360c3190217a389a5c7d6b6c7fc28f67ff","summary":"第 15 版更新\n- 反斜杠 \\ 与引号 \" 都必须转义\n- 制表符\t与不可见控制字符 \u0001 混排\n- 结语"}''';

/// 项目上一轮预演（`.update-signing/rehearsal-update.json`）签出的真实清单：
/// 指纹相同、字段不同的第二份样本，用来确认验签不是「碰巧对某一段字符串成立」。
const String _rehearsalFixture =
    r'''{"versionCode":6,"versionName":"0.1.0-alpha.5","channel":"prerelease","minimumVersionCode":1,"packageName":"host.msknet.sunsetripple","apkUrl":"https://github.com/Starlordzz/sunsetripple/releases/download/v0.1.0-alpha.5/SunsetRipple-v0.1.0-alpha.5.apk","apkSha256":"c494c2b7e58c09dd0cf95f9e307f9f36c6ffd6fd4799c4ff1567e8d5fb9ce234","certificateSha256":"32b678ce045c645cea8ea6090a96f2360c3190217a389a5c7d6b6c7fc28f67ff","summary":"versionName=0.1.0-alpha.5\nversionCode=6\napplicationId=host.msknet.sunsetripple","signature":"MEQCIEcqKQp/tQX2SWFMYJ7WAVaYAKQHhOak8YqOGnviTGuXAiAXarbxfQ/nKe5Sah+JZiwDkHCMRfqjD1FU1jTALBPNUg=="}''';

/// [_escapeFixture] 对应的「APK」内容：签名时按这些字节算的 SHA-256。
const String _fixtureApkBody = 'sunset-ripple-update-fixture-apk';

/// 另一把**真实存在但与本应用内置公钥不同**的 P-256 公钥（SPKI base64）。
const String _otherPublicKeyBase64 =
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAERjr4Ht87Ewr3k+2nGlL8BoRo'
    'DyyZsnd9reNwqH9n2g1ZfHV1BzhMRNYa3Rf3q8iz+dDu8FLj+rvko+SJXcKYtw==';

const String _expectedSummary = '第 15 版更新\n'
    '- 反斜杠 \\ 与引号 " 都必须转义\n'
    '- 制表符\t与不可见控制字符 \u0001 混排\n'
    '- 结语';

/// 把清单里的 `apkUrl` 换成别的地址（保留其余字段，结构仍合法）。
String _withApkUrl(String json, String url) {
  final start = json.indexOf('"apkUrl":"') + '"apkUrl":"'.length;
  final end = json.indexOf('","apkSha256"');
  expect(start, greaterThan(0));
  expect(end, greaterThan(start));
  return '${json.substring(0, start)}$url${json.substring(end)}';
}

/// 把清单里的 `signature` 换成别的值。
String _withSignature(String json, String signature) {
  final start = json.indexOf('"signature":"') + '"signature":"'.length;
  final end = json.lastIndexOf('"}');
  return '${json.substring(0, start)}$signature${json.substring(end)}';
}

/// 把清单的 summary 段整体替换成给定的**已转义** JSON 片段。
String _withSummary(String json, String summaryJsonFragment) {
  final start = json.indexOf('"summary":"') + '"summary":"'.length;
  final end = json.indexOf('","signature"');
  expect(end, greaterThan(start));
  return '${json.substring(0, start)}$summaryJsonFragment${json.substring(end)}';
}

String _signatureOf(String json) =>
    RegExp(r'"signature":"([^"]+)"').firstMatch(json)!.group(1)!;

void main() {
  group('真实签名清单：Java 生成端 ↔ Dart 校验端', () {
    test('验签通过并解出全部字段', () {
      final manifest = UpdateManifest.verify(_escapeFixture);

      expect(manifest.versionCode, 16);
      expect(manifest.versionName, '0.1.0-alpha.15');
      expect(manifest.channel, 'prerelease');
      expect(manifest.minimumVersionCode, 15);
      expect(manifest.packageName, kUpdatePackageName);
      expect(
        manifest.apkUrl,
        'https://github.com/Starlordzz/sunsetripple/releases/download/'
        'v0.1.0-alpha.15/SunsetRipple-v0.1.0-alpha.15.apk',
      );
      expect(manifest.apkSha256,
          '82c6f31133b9c797d027643860f7be3b8954a2f3d5adc787f1ebb966e4eec4a7');
      expect(manifest.certificateSha256,
          '32b678ce045c645cea8ea6090a96f2360c3190217a389a5c7d6b6c7fc28f67ff');
      expect(manifest.summary, _expectedSummary);
      expect(manifest.signature, isNotEmpty);
      expect(manifest.hasTrustedUpdateUrl, isTrue);
    });

    test('规范化 JSON 与 Java 的输出逐字节一致（含控制字符转义）', () {
      final manifest = UpdateManifest.verify(_escapeFixture);

      // 后半段是独立副本：只要转义规则（\\ \" \t \u00xx、非 ASCII 原样）与字段
      // 顺序和 Java 有任何出入，这条断言就会失败。
      expect(manifest.canonicalJson(), _escapeFixtureCanonical);
      // 落盘的 update.json 也能被逐字节复原，证明 signature 追加位置一致。
      expect(manifest.signedJson(), _escapeFixture);
    });

    test('summary 的反斜杠/引号/制表符/控制字符原样还原', () {
      final manifest = UpdateManifest.verify(_escapeFixture);

      expect(manifest.summary.contains(r'\'), isTrue);
      expect(manifest.summary.contains('"'), isTrue);
      expect(manifest.summary.contains('\t'), isTrue);
      expect(manifest.summary.contains('\u0001'), isTrue);
      expect(
          manifest.summary.codeUnits.length, _expectedSummary.codeUnits.length);
    });

    test('apkSha256 与 Dart 侧 sha256 对同一份字节的结果一致', () {
      final digest = sha256.convert(utf8.encode(_fixtureApkBody)).toString();

      // Java 的 MessageDigest("SHA-256") 与 package:crypto 必须给出同一个十六进制串，
      // 否则下载校验会永远失败。
      expect(digest, UpdateManifest.verify(_escapeFixture).apkSha256);
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('第二份真实清单（alpha.5 预演产物）同样通过验签', () {
      final manifest = UpdateManifest.verify(_rehearsalFixture);

      expect(manifest.versionCode, 6);
      expect(manifest.versionName, '0.1.0-alpha.5');
      expect(manifest.minimumVersionCode, 1);
      expect(
          manifest.summary, contains('applicationId=host.msknet.sunsetripple'));
      expect(manifest.canonicalJson(),
          '${_rehearsalFixture.substring(0, _rehearsalFixture.lastIndexOf(',"signature"'))}}');
    });
  });

  group('篡改与结构异常一律拒绝', () {
    test('篡改 signature 里一个字符即被拒绝', () {
      final signature = _signatureOf(_escapeFixture);
      final flipped = signature.replaceFirst('MEUC', 'MEUD');

      expect(flipped, isNot(signature));
      expect(
        () => UpdateManifest.verify(_withSignature(_escapeFixture, flipped)),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
      expect(
        UpdateManifest.parse(_withSignature(_escapeFixture, flipped))
            .verifySignature(),
        isFalse,
      );
    });

    test('把另一份清单的 signature 搬过来也被拒绝', () {
      final foreign = _signatureOf(_rehearsalFixture);

      expect(
        () => UpdateManifest.verify(_withSignature(_escapeFixture, foreign)),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });

    test('篡改 apkSha256（仍是合法 64 位 hex）被拒绝', () {
      final tampered = _escapeFixture.replaceFirst(
        '82c6f31133b9c797d027643860f7be3b8954a2f3d5adc787f1ebb966e4eec4a7',
        'ab' * 32,
      );

      // 格式仍然合法 —— 拒绝必须来自验签，而不是字段校验。
      expect(UpdateManifest.parse(tampered).apkSha256, 'ab' * 32);
      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });

    test('篡改 versionName 被拒绝', () {
      final tampered = _escapeFixture.replaceFirst(
          '"versionName":"0.1.0-alpha.15"', '"versionName":"9.9.9"');

      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });

    test('篡改 summary 正文被拒绝', () {
      final tampered = _escapeFixture.replaceFirst('都必须转义', '都不必转义');

      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });

    test('apkSha256 字段格式非法 → 格式错误（不会走到验签）', () {
      for (final bad in <String>['abc', 'zz' * 32, 'a' * 63, 'a' * 65]) {
        final tampered = _escapeFixture.replaceFirst(
          '82c6f31133b9c797d027643860f7be3b8954a2f3d5adc787f1ebb966e4eec4a7',
          bad,
        );
        expect(
          () => UpdateManifest.verify(tampered),
          throwsA(isA<UpdateManifestFormatException>()),
          reason: 'apkSha256=$bad 应当被拒绝',
        );
      }
    });

    test('certificateSha256 字段格式非法 → 格式错误', () {
      final tampered = _escapeFixture.replaceFirst(
        '32b678ce045c645cea8ea6090a96f2360c3190217a389a5c7d6b6c7fc28f67ff',
        'not-a-hash',
      );

      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('多出未签名字段 → 拒绝', () {
      final tampered = _escapeFixture.replaceFirst('{', '{"extra":"smuggled",');

      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('缺少必填字段 → 拒绝', () {
      final tampered =
          _escapeFixture.replaceFirst('"minimumVersionCode":15,', '');

      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('缺少 signature → 拒绝', () {
      final tampered = _withSignature(_escapeFixture, '');

      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('versionCode 不是整数 → 拒绝', () {
      final tampered =
          _escapeFixture.replaceFirst('"versionCode":16', '"versionCode":16.0');

      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('summary 为空 → 拒绝', () {
      expect(
        () => UpdateManifest.verify(_withSummary(_escapeFixture, '')),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('顶层不是 JSON 对象 → 拒绝', () {
      expect(() => UpdateManifest.verify('[]'),
          throwsA(isA<UpdateManifestFormatException>()));
      expect(() => UpdateManifest.verify('not json at all'),
          throwsA(isA<UpdateManifestFormatException>()));
      expect(() => UpdateManifest.verify(''),
          throwsA(isA<UpdateManifestFormatException>()));
    });

    test('apkUrl 不是 HTTPS → 拒绝', () {
      final tampered = _escapeFixture.replaceFirst(
          '"apkUrl":"https://github.com', '"apkUrl":"http://github.com');

      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('清单包名与本应用不一致 → 拒绝', () {
      expect(
        () => UpdateManifest.verify(_escapeFixture,
            expectedPackageName: 'com.evil.clone'),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });

    test('channel 不在 stable/prerelease 之内 → 拒绝', () {
      final tampered = _escapeFixture.replaceFirst(
          '"channel":"prerelease"', '"channel":"nightly"');

      expect(
        () => UpdateManifest.verify(tampered),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });
  });

  group('公钥异常：拒绝而不是崩溃或放行', () {
    test('内置公钥能验过真实清单（基准）', () {
      expect(UpdateManifest.verify(_escapeFixture).verifySignature(), isTrue);
      expect(kUpdateManifestPublicKeyBase64, isNotEmpty);
    });

    test('非法 base64 公钥 → 抛异常', () {
      expect(
        () => UpdateManifest.verify(_escapeFixture,
            publicKeyBase64: '这不是 base64!!!'),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });

    test('长度/曲线不对的公钥 → 抛异常', () {
      // 长度不对：随便一段合法 base64。
      expect(
        () => UpdateManifest.verify(_escapeFixture,
            publicKeyBase64: base64.encode(List<int>.filled(32, 7))),
        throwsA(isA<UpdateManifestSignatureException>()),
      );

      // 长度对但曲线 OID 不是 prime256v1（把 OID 末字节改掉）。
      final der = base64.decode(kUpdateManifestPublicKeyBase64);
      final otherCurve = List<int>.from(der)..[22] = 0x08;
      expect(
        () => UpdateManifest.verify(_escapeFixture,
            publicKeyBase64: base64.encode(otherCurve)),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });

    test('坐标不在 P-256 曲线上的公钥 → 抛异常', () {
      final der = base64.decode(kUpdateManifestPublicKeyBase64);
      final offCurve = List<int>.from(der)..[90] = der[90] ^ 0x01;

      expect(
        () => UpdateManifest.verify(_escapeFixture,
            publicKeyBase64: base64.encode(offCurve)),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });

    test('格式合法但属于别的密钥的公钥 → 验签失败', () {
      final manifest = UpdateManifest.parse(_escapeFixture);

      expect(manifest.verifySignature(_otherPublicKeyBase64), isFalse);
      expect(
        () => UpdateManifest.verify(_escapeFixture,
            publicKeyBase64: _otherPublicKeyBase64),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });

    test('signature 不是合法 base64 / 不是合法 DER → 抛异常', () {
      expect(
        () => UpdateManifest.verify(
            _withSignature(_escapeFixture, '!!!not-base64')),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
      // 合法 base64，但内容不是 SEQUENCE{INTEGER,INTEGER}。
      expect(
        () => UpdateManifest.verify(_withSignature(
            _escapeFixture, base64.encode(utf8.encode('MEUC-not-a-der')))),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
    });
  });

  group('APK 下载地址白名单', () {
    test('白名单域名 + 默认端口 + https 通过', () {
      for (final url in <String>[
        'https://github.com/Starlordzz/sunsetripple/releases/download/v1/a.apk',
        'https://objects.githubusercontent.com/github-production-release-asset/a.apk',
        'https://github-releases.githubusercontent.com/123/456?a=b',
      ]) {
        expect(UpdateManifest.isTrustedUpdateUrl(Uri.parse(url)), isTrue,
            reason: url);
      }
    });

    test('http:// 被拒绝', () {
      expect(
        UpdateManifest.isTrustedUpdateUrl(
            Uri.parse('http://github.com/x/releases/download/v1/a.apk')),
        isFalse,
      );
    });

    test('白名单外的域名被拒绝', () {
      for (final url in <String>[
        'https://evil.com/a.apk',
        'https://github.com.evil.com/a.apk', // 后缀欺骗
        'https://github.com@evil.com/a.apk', // userInfo 欺骗
        'https://raw.githubusercontent.com/a.apk',
        'https://github.com.cn/a.apk',
      ]) {
        expect(UpdateManifest.isTrustedUpdateUrl(Uri.parse(url)), isFalse,
            reason: url);
      }
    });

    test('非默认端口被拒绝', () {
      expect(
        UpdateManifest.isTrustedUpdateUrl(
            Uri.parse('https://github.com:8443/a.apk')),
        isFalse,
      );
      expect(
        UpdateManifest.isTrustedUpdateUrl(
            Uri.parse('https://github.com:443/a.apk')),
        isTrue,
      );
    });

    test('非 http(s) 协议被拒绝', () {
      expect(
        UpdateManifest.isTrustedUpdateUrl(Uri.parse('ftp://github.com/a.apk')),
        isFalse,
      );
      expect(
        UpdateManifest.isTrustedUpdateUrl(Uri.parse('file:///etc/passwd')),
        isFalse,
      );
    });

    test('assertTrustedUpdateUrl 对非白名单地址抛出明确错误', () {
      final untrusted = UpdateManifest.parse(
          _withApkUrl(_escapeFixture, 'https://evil.com/a.apk'));
      expect(untrusted.hasTrustedUpdateUrl, isFalse);
      expect(untrusted.assertTrustedUpdateUrl,
          throwsA(isA<UntrustedUpdateUrlException>()));

      final trusted = UpdateManifest.parse(
          _withApkUrl(_escapeFixture, 'https://github.com/x/a.apk'));
      expect(trusted.hasTrustedUpdateUrl, isTrue);
      trusted.assertTrustedUpdateUrl();
    });

    test('白名单与体积上限都是内置常量', () {
      expect(kTrustedApkHosts, contains('github.com'));
      expect(kTrustedApkPort, 443);
      expect(kUpdateDownloadMaxBytes, 150 * 1024 * 1024);
      expect(kUpdateDownloadTimeout.inMinutes, greaterThan(0));
    });
  });

  group('UpdateService 发现清单资产', () {
    test('找到名为 update.json 的资产', () {
      expect(
        UpdateService.findManifestAssetUrl(<Object?>[
          <String, Object?>{
            'name': 'SunsetRipple-v0.1.0-alpha.15.apk',
            'browser_download_url': 'https://github.com/x/a.apk',
          },
          <String, Object?>{
            'name': 'update.json',
            'browser_download_url':
                'https://github.com/x/releases/download/v0.1.0-alpha.15/update.json',
          },
        ]),
        'https://github.com/x/releases/download/v0.1.0-alpha.15/update.json',
      );
    });

    test('没有清单资产 / 结构异常 / 非 https 都返回 null', () {
      expect(UpdateService.findManifestAssetUrl(null), isNull);
      expect(UpdateService.findManifestAssetUrl('not-a-list'), isNull);
      expect(UpdateService.findManifestAssetUrl(<Object?>[]), isNull);
      expect(
        UpdateService.findManifestAssetUrl(<Object?>[
          <String, Object?>{'name': 'update.json'},
          <String, Object?>{'name': 'update.json', 'browser_download_url': 42},
          <String, Object?>{
            'name': 'update.json',
            'browser_download_url': 'http://github.com/update.json',
          },
        ]),
        isNull,
        reason: '非 https 的清单地址必须当作没有清单，退化到打开 Release 页面',
      );
    });

    test('UpdateAvailable 在没有清单资产时仍保留 Release 页面地址', () {
      const state = UpdateAvailable(
        versionName: '0.1.0-alpha.15',
        releaseNotes: 'notes',
        downloadUrl: 'https://github.com/x/releases/tag/v0.1.0-alpha.15',
      );
      expect(state.manifestUrl, isNull);
      expect(state.downloadUrl, contains('releases/tag'));
    });
  });

  group('平台接线一致性（Dart ↔ Kotlin ↔ Swift ↔ Manifest ↔ CI）', () {
    String read(String path) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path 必须存在');
      return file.readAsStringSync();
    }

    test('Android：权限、FileProvider 与下载目录三者对齐', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
      expect(manifest, contains('androidx.core.content.FileProvider'));
      expect(
          manifest,
          contains(
              r'android:authorities="${applicationId}.update.fileprovider"'));
      expect(manifest, contains('@xml/file_paths'));

      final filePaths = read('android/app/src/main/res/xml/file_paths.xml');
      expect(
        filePaths,
        contains('path="$kUpdateDownloadDirectoryName/"'),
        reason: 'FileProvider 暴露的目录必须与 Dart 侧 kUpdateDownloadDirectoryName 一致，'
            '否则 FileProvider.getUriForFile 会抛 IllegalArgumentException',
      );
    });

    test('Kotlin 插件：通道名 / authority 后缀 / 安装入口与 Dart 侧一致', () {
      final plugin = read(
          'android/app/src/main/kotlin/host/msknet/sunsetripple/UpdateInstallerPlugin.kt');
      expect(plugin, contains("host.msknet.sunsetripple/update_installer"),
          reason: '通道名必须与 update_installer.dart 的 MethodChannel 完全一致');
      expect(plugin, contains('.update.fileprovider'));
      expect(plugin, contains('FileProvider.getUriForFile'));
      // 优先 ACTION_VIEW + APK MIME；ACTION_INSTALL_PACKAGE 只做兜底。
      expect(plugin, contains('Intent.ACTION_VIEW'));
      expect(plugin, contains('application/vnd.android.package-archive'));
      expect(plugin, contains('ACTION_INSTALL_PACKAGE'));
      expect(plugin, contains('canRequestPackageInstalls'));
      // 原生侧也要自己核对包名/versionCode/证书，而不是只信 Dart。
      expect(plugin, contains('certificateSha256'));

      final mainActivity = read(
          'android/app/src/main/kotlin/host/msknet/sunsetripple/MainActivity.kt');
      expect(
        mainActivity,
        contains('UpdateInstallerPlugin('),
        reason: '插件必须在 MainActivity 里注册，否则 Dart 侧只会拿到 MissingPluginException',
      );
    });

    test('iOS：只在 AppDelegate 里实现 openUrl，并明确不支持自装', () {
      final appDelegate = read('ios/Runner/AppDelegate.swift');
      expect(
          appDelegate, contains('host.msknet.sunsetripple/update_installer'));
      expect(appDelegate, contains('"openUrl"'));
      expect(appDelegate, contains('UIApplication.shared.open'));
      expect(appDelegate, contains('"installApk"'));
      expect(appDelegate, contains('unsupported'));
    });

    test('release.yml：用脚本签清单并把 update.json 作为 Release 资产上传', () {
      final workflow = read('.github/workflows/release.yml');
      expect(workflow, contains('SignUpdateManifest.java'));
      expect(workflow, contains('release-artifacts/update.json'));
      expect(workflow, contains('UPDATE_PRIVATE_KEY_PKCS8_BASE64'));
      expect(workflow, contains('UPDATE_PUBLIC_KEY_BASE64'));
      expect(
        workflow,
        contains('kUpdateManifestPublicKeyBase64'),
        reason: '发布前必须比对 CI secret 与 App 内置公钥',
      );
      expect(
        workflow,
        contains('final-artifacts/*.json'),
        reason: 'update.json 必须出现在 gh release 的上传列表里，否则 App 永远找不到清单',
      );
    });
  });
}
