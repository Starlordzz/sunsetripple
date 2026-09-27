> 🌐 English | [简体中文](../构建与发布.md)

# Build and Release

This page covers the complete pipeline from source code to a signed APK. All commands assume the repository root as the working directory.

## Toolchain Versions

| Component | Version | Location |
| --- | --- | --- |
| Flutter SDK | 3.24+ | System PATH |
| Dart SDK | 3.5+ | Bundled with Flutter |
| JDK | 17 | `JAVA_HOME` must be set before building |
| Android Gradle Plugin | 8.5.2+ | `android/build.gradle.kts` |
| Android SDK / Compile SDK | 35 | `android/app/build.gradle.kts` |

## App Identity

| Item | Value |
| --- | --- |
| `applicationId` / `namespace` | `host.msknet.sunsetripple` |
| `minSdk` | 26 (Android 8.0) |
| `targetSdk` / `compileSdk` | 35 |
| `versionCode` / `versionName` | 14 / `0.1.0-alpha.13` |
| Java / JVM target | 17 |

> The legacy test package name `com.wt.intercom` differs from the current one and **cannot be upgraded over**; the old version must be uninstalled first.

## Common Commands

```powershell
# 1. 获取依赖包
flutter pub get

# 2. 运行自动化单元测试 (144 个用例)
flutter test

# 3. 运行代码静态分析
flutter analyze

# 4. 在真机上调试运行
flutter run

# 5. 打包 Release 发布版 APK
flutter build apk --release
```

## Release Signing

### Key and Configuration

The signing configuration and keys **exist only locally** and never enter version control. `.gitignore` already excludes `keystore.properties`, `*.jks`, `*.keystore`, and `*.p12`.

See `keystore.properties.example` for the `keystore.properties` format:

```properties
storeFile=C:/Users/<用户名>/.android/sunset-ripple-release.p12
storePassword=<强密码>
keyAlias=sunset-ripple
keyPassword=<强密码>
```

> **The same key must be kept in use for the long term.** Android identifies the app's origin by its signing certificate; after switching keys, users with the app already installed cannot upgrade over it and must uninstall and reinstall. Back up the `.p12` and its password offline.

### Signing Guard

`android/app/build.gradle.kts` guards `assembleRelease` in a `doFirst` block: when `android/key.properties` is missing, the build **fails immediately** and prints three remediation paths instead of silently falling back to debug signing.

> **Why this is a hard constraint**: CI previously could not obtain signing material, so `flutter build apk --release` always fell back to debug signing. A GitHub runner generates a fresh debug key every run, so **every release was signed differently** — users hit `INSTALL_FAILED_UPDATE_INCOMPATIBLE` and had to uninstall. Since alpha.14, `release.yml` restores the keystore from secrets and additionally asserts with `apksigner` that the artifact is not `CN=Android Debug`.

For local self-testing that explicitly accepts an unreleasable package, pass `-PallowDebugSigning=true`.

### Packaging

```powershell
$env:JAVA_HOME='C:\Path\To\jdk-17' # 替换为本机 JDK 17 安装目录
.\gradlew.bat :app:testDebugUnitTest :app:lintRelease :app:assembleRelease :app:bundleRelease
```

Artifacts:

- Sideloadable APK: `app/build/outputs/apk/release/app-release.apk`
- App-store AAB: `app/build/outputs/bundle/release/app-release.aab`

Configure signing material:

```bash
bash scripts/setup-release-signing.sh
```

The wizard generates a long-lived PKCS12 key, writes the `android/key.properties` that
Gradle actually reads, and — when `gh` is available — sets the four repository secrets
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`.

> **Note**: up to alpha.13 the wizard wrote `keystore.properties` at the repository root
> while Gradle reads `android/key.properties` (`rootProject` is `android/`), so local
> release builds still fell back to debug signing. Fixed in alpha.14.

### Publishing to GitHub Releases

Published versions are listed under [Releases](https://github.com/Starlordzz/sunsetripple/releases). `.github/workflows/release.yml` runs tests, restores the signing material, builds the
release APK, verifies the signature, and uploads the GitHub Release after a `v*` tag is
pushed. It also produces an unsigned iOS `.ipa` and a HarmonyOS source-project zip.

Before the first run, configure the four secrets `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
(`scripts/setup-release-signing.sh` can write them). Back the keystore up offline.

> **Not implemented**: the `update.json` manifest signing, APK SHA-256 verification and
> in-app auto-install chain this document used to describe **do not exist in the current
> code**. `UpdateService` only compares SemVer and stores `html_url` for display; nothing
> downloads, installs or verifies. The helpers (`scripts/SignUpdateManifest.java`,
> `GenerateUpdateSigningKey.java`) produce a key and a manifest that have no consumer.
> Do not claim update integrity verification until that path is wired.

Release steps:

1. Update `versionCode` / `versionName` (in both `pubspec.yaml` and `harmonyos/AppScope/app.json5`) and `CHANGELOG.md`.
2. Commit the changes and create a tag with the same name, for example `v0.1.0-alpha.11`.
3. Push the tag: `git push origin v0.1.0-alpha.11`.
4. Actions automatically creates the version Release and updates the rolling `updates-prerelease` or `updates-stable` manifest.

alpha / beta tags are automatically marked as prerelease; when running the workflow manually, the input tag must already exist and match `versionName` exactly.

## Release Build Notes

The current release build is `0.1.0-alpha.13`. The update protocol verifies the manifest signature, APK SHA-256, package name, and Android signing certificate before handing over to the system for installation confirmation. The voice pipeline does not depend on the internet; GitHub is only accessed when the user manually checks for updates.

## Related Pages

- [FAQ](FAQ.md) — quick diagnosis of build errors and installation failures
- [Troubleshooting](Troubleshooting.md) — runtime issues
- [Architecture Overview](Architecture-Overview.md)
