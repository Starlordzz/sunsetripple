import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/update/update_manifest.dart';

// These tests exercise the actual release tools with disposable keys, without
// reading .update-signing/ or uploading repository secrets. Requires JDK 17 and
// Bash (the same tools installed by Flutter CI).
void main() {
  late Directory sandbox;
  final repository = Directory.current.path;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('sunset-release-');
  });
  tearDown(() => sandbox.deleteSync(recursive: true));

  Future<ProcessResult> java(List<String> arguments) =>
      Process.run('java', arguments, workingDirectory: sandbox.path);

  Future<ProcessResult> setup(String input) async {
    final process = await Process.start(
        'bash',
        [
          '$repository/scripts/setup-release-signing.sh',
          '--local-only',
        ],
        workingDirectory: sandbox.path);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(input);
    await process.stdin.close();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw StateError('Signing setup did not stop after stdin closed');
      },
    );
    return ProcessResult(process.pid, exitCode, await stdout, await stderr);
  }

  void expectSuccess(ProcessResult result) {
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  void createProject() {
    // A fresh project layout, with no signing files, Flutter/Gradle caches, or
    // dependency resolution. This catches the old root settings.gradle check.
    File('${sandbox.path}/pubspec.yaml').writeAsStringSync('name: rehearsal\n');
    Directory('${sandbox.path}/android').createSync();
    File('${sandbox.path}/android/settings.gradle.kts').writeAsStringSync('');
  }

  test(
    'clean setup creates usable Gradle properties and reuses the same key',
    () async {
      createProject();
      const password = 'rehearsal-only:=#42';
      // Relative paths must be made absolute for Gradle's android/app/ base.
      const storePath = 'keys with spaces/rehearsal.p12';
      const input = '\n\n$storePath\n\n\n$password\n$password\ny\n';
      final first = await setup(input);
      expectSuccess(first);
      expect(first.stdout, contains('Local-only mode'));
      expect(first.stdout, isNot(contains(password)));
      final store = File('${sandbox.path}/$storePath');
      final originalKey = store.readAsBytesSync();
      final properties = File('${sandbox.path}/android/key.properties');
      expect(
        properties.readAsStringSync(),
        contains('storeFile=${store.absolute.path}'),
      );

      // Load properties exactly as Gradle does and actually use the recovered
      // password/alias to sign and verify, rather than checking file text alone.
      final probe = File('${sandbox.path}/CheckSigning.java');
      probe.writeAsStringSync('''
import java.nio.file.*;
import java.util.Properties;
import java.security.*;
class CheckSigning {
  public static void main(String[] args) throws Exception {
    Properties p = new Properties();
    try (var input = Files.newInputStream(Path.of("android/key.properties"))) {
      p.load(input);
    }
    KeyStore store = KeyStore.getInstance("PKCS12");
    try (var input = Files.newInputStream(Path.of(p.getProperty("storeFile")))) {
      store.load(input, p.getProperty("storePassword").toCharArray());
    }
    String alias = p.getProperty("keyAlias");
    Signature signature = Signature.getInstance("SHA256withRSA");
    signature.initSign((PrivateKey) store.getKey(alias,
        p.getProperty("keyPassword").toCharArray()));
    byte[] message = new byte[]{1, 2, 3};
    signature.update(message);
    byte[] signed = signature.sign();
    signature.initVerify(store.getCertificate(alias));
    signature.update(message);
    if (!signature.verify(signed)) throw new IllegalStateException("Invalid key");
  }
}
''');
      expectSuccess(await java([probe.path]));

      // Enter retains persisted identity/password. Confirmation is never saved.
      final second = await setup('\n\n\n\n\n\n$password\n');
      expectSuccess(second);
      expect(second.stdout, contains('existing keystore'));
      expect(store.readAsBytesSync(), originalKey);
      expectSuccess(await java([probe.path]));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'closed input fails promptly without creating signing material',
    () async {
      createProject();
      // Reach the password prompt, then EOF: previously this loop never ended.
      final result = await setup('\n\nunused.p12\n\n\n');
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('Input ended'));
      expect(
        File('${sandbox.path}/android/key.properties').existsSync(),
        isFalse,
      );
      expect(File('${sandbox.path}/unused.p12').existsSync(), isFalse);
    },
  );

  test(
    'fresh Java keys and signed manifest verify in Dart and reject tampering',
    () async {
      final keyDirectory = '${sandbox.path}/.update-signing';
      final generator = '$repository/scripts/GenerateUpdateSigningKey.java';
      expectSuccess(await java([generator, keyDirectory]));
      final publicKey = base64.encode(
        File('$keyDirectory/update-public-key.der').readAsBytesSync(),
      );
      final privateKey = File('$keyDirectory/update-private-key.pk8');
      final originalPrivateKey = privateKey.readAsBytesSync();

      final duplicate = await java([generator, keyDirectory]);
      expect(duplicate.exitCode, isNot(0));
      expect(duplicate.stderr, contains('Refusing to overwrite'));
      expect(privateKey.readAsBytesSync(), originalPrivateKey);

      final apk = File('${sandbox.path}/fixture.apk')
        ..writeAsBytesSync(List.generate(256, (index) => index));
      const summary = '更新 🌅\n引号 " / 反斜杠 \\ / 制表符\t / 控制字符 \u0001 / 结束';
      final summaryFile = File('${sandbox.path}/summary.txt')
        ..writeAsStringSync(summary);
      final output = File('${sandbox.path}/artifacts/update.json');
      List<String> signArguments(String verificationKey) => [
            '$repository/scripts/SignUpdateManifest.java',
            '--version-code',
            '17',
            '--version-name',
            '0.1.0-alpha.16',
            '--channel',
            'prerelease',
            '--minimum-version-code',
            '16',
            '--package-name',
            kUpdatePackageName,
            '--apk-url',
            'https://github.com/Starlordzz/sunsetripple/releases/download/v0.1.0-alpha.16/test.apk',
            '--certificate-sha256',
            'AB' * 32,
            '--summary-file',
            summaryFile.path,
            '--apk',
            apk.path,
            '--private-key',
            privateKey.path,
            '--public-key-base64',
            verificationKey,
            '--output',
            output.path,
          ];
      expectSuccess(await java(signArguments(publicKey)));
      final signedJson = output.readAsStringSync();
      final manifest = UpdateManifest.verify(
        signedJson,
        publicKeyBase64: publicKey,
      );
      expect(manifest.summary, summary);
      expect(
        manifest.apkSha256,
        sha256.convert(apk.readAsBytesSync()).toString(),
      );
      expect(manifest.certificateSha256, 'ab' * 32);
      expect(manifest.versionCode, 17);
      expect(manifest.minimumVersionCode, 16);
      expect(manifest.signedJson(), signedJson.trim());

      final tampered = jsonDecode(signedJson) as Map<String, dynamic>;
      tampered['summary'] = '篡改后的说明';
      expect(
        () => UpdateManifest.verify(
          jsonEncode(tampered),
          publicKeyBase64: publicKey,
        ),
        throwsA(isA<UpdateManifestSignatureException>()),
      );
      final otherKeys = '${sandbox.path}/other-keys';
      expectSuccess(await java([generator, otherKeys]));
      final otherPublicKey = base64.encode(
        File('$otherKeys/update-public-key.der').readAsBytesSync(),
      );
      expect(
        () =>
            UpdateManifest.verify(signedJson, publicKeyBase64: otherPublicKey),
        throwsA(isA<UpdateManifestSignatureException>()),
      );

      output.deleteSync();
      final mismatch = await java(signArguments(otherPublicKey));
      expect(mismatch.exitCode, isNot(0));
      expect(mismatch.stderr, contains('does not match'));
      expect(output.existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
