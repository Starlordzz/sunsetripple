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
| `versionCode` / `versionName` | 12 / `0.1.0-alpha.11` |
| Java / JVM target | 17 |

> The legacy test package name `com.wt.intercom` differs from the current one and **cannot be upgraded over**; the old version must be uninstalled first.

## Common Commands

```powershell
# 1. 获取依赖包
flutter pub get

# 2. 运行自动化单元测试 (58 个用例)
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

`app/build.gradle.kts` registers a `verifyReleaseSigning` task that is attached before `packageRelease` / `bundleRelease`. If the configuration file is missing, a field is missing, or the key file does not exist, the build **fails early** with a reason (in Chinese), preventing unsigned or wrongly signed artifacts.

### Packaging

```powershell
$env:JAVA_HOME='C:\Path\To\jdk-17' # 替换为本机 JDK 17 安装目录
.\gradlew.bat :app:testDebugUnitTest :app:lintRelease :app:assembleRelease :app:bundleRelease
```

Artifacts:

- Sideloadable APK: `app/build/outputs/apk/release/app-release.apk`
- App-store AAB: `app/build/outputs/bundle/release/app-release.aab`

CI or a temporary signing configuration can point Gradle properties elsewhere (absolute paths accepted):

```bash
./gradlew :app:assembleRelease -PsunsetRipple.signingProperties=/secure/path/keystore.properties
```

### Publishing to GitHub Releases

Published versions are listed under [Releases](https://github.com/Starlordzz/sunsetripple/releases). `.github/workflows/release.yml` automatically runs tests, Release lint, signs the APK/AAB, signs the `update.json` manifest, and uploads the GitHub Release after a `v*` tag is pushed.

Before enabling this for the first time, configure `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, and `UPDATE_PRIVATE_KEY_PKCS8_BASE64` in GitHub Actions Secrets, plus the non-sensitive variable `UPDATE_PUBLIC_KEY_BASE64`. The update private key and the Android keystore must be backed up offline.

Release steps:

1. Update `versionCode` / `versionName` (in both `pubspec.yaml` and `harmonyos/AppScope/app.json5`) and `CHANGELOG.md`.
2. Commit the changes and create a tag with the same name, for example `v0.1.0-alpha.11`.
3. Push the tag: `git push origin v0.1.0-alpha.11`.
4. Actions automatically creates the version Release and updates the rolling `updates-prerelease` or `updates-stable` manifest.

alpha / beta tags are automatically marked as prerelease; when running the workflow manually, the input tag must already exist and match `versionName` exactly.

## Release Build Notes

The current release build is `0.1.0-alpha.11`. The update protocol verifies the manifest signature, APK SHA-256, package name, and Android signing certificate before handing over to the system for installation confirmation. The voice pipeline does not depend on the internet; GitHub is only accessed when the user manually checks for updates.

## Related Pages

- [FAQ](FAQ.md) — quick diagnosis of build errors and installation failures
- [Troubleshooting](Troubleshooting.md) — runtime issues
- [Architecture Overview](Architecture-Overview.md)
