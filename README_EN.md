<p align="center">
  <a href="README.md">简体中文</a> | <a href="README_EN.md">English</a>
</p>

<br>

<p align="center">
  <img src="docs/assets/mark.svg" width="96" alt="SunsetRipple">
</p>

<h1 align="center">SunsetRipple</h1>

<p align="center"><sub>S U N S E T &nbsp;&nbsp; R I P P L E</sub></p>

<br>

<p align="center">
  <a href="https://github.com/Starlordzz/sunsetripple/releases"><img alt="Release" src="https://img.shields.io/github/v/release/Starlordzz/sunsetripple?include_prereleases&amp;color=FF7138&amp;labelColor=3A1030"></a>
  <img alt="Flutter 3.29.0" src="https://img.shields.io/badge/Flutter-3.29.0-02569B?labelColor=3A1030">
  <img alt="Android 8.0+" src="https://img.shields.io/badge/Android-8.0%2B-FF8A3D?labelColor=3A1030">
  <a href="https://github.com/Starlordzz/sunsetripple/actions/workflows/flutter-ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Starlordzz/sunsetripple/flutter-ci.yml?branch=master&amp;label=CI&amp;color=F4B85C&amp;labelColor=3A1030"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-7D6B67?labelColor=3A1030"></a>
</p>

<br>

---

<br>

**A local voice intercom app for up to 6 devices over a LAN, Wi-Fi Direct, or Bluetooth. No account or server setup is required. Android is currently the only actively maintained platform.**

<br>

<p align="center">
  <img src="docs/screenshots/showcase-en.png" width="880" alt="SunsetRipple · UI preview">
  <br>
  <sub>Home · Wi-Fi room · Bluetooth talk · In-room messages</sub>
</p>

<br>

## Features

- **Wi-Fi rooms**: full-duplex conversations over a shared LAN, personal hotspot, or Wi-Fi Direct.
- **Bluetooth rooms**: push-to-talk over BLE L2CAP CoC. Hold to speak, release to listen.
- **In-room messages**: text chat with message recall. Messages stay in memory and are cleared when you leave.
- **Audio controls**: mute, switch between speaker and earpiece, and select the phone or headset microphone.
- **Connection recovery**: automatic reconnection, plus manual host transfer and automatic host election in Wi-Fi rooms.

<br>

## Platform Support

| Platform | Current status | Distribution |
| --- | --- | --- |
| Android 8.0+ | Available; Bluetooth rooms require Android 10+ | APK, install directly |
| iOS 15+ | Paused (`ios/` frozen placeholder); CI and releases disabled | None (IPA output stopped) |
| HarmonyOS NEXT | Paused (`harmonyos/` frozen placeholder); UDP discovery only, checks and packaging disabled | None (source-zip output stopped) |
| Windows / macOS / Linux | Unsupported; native audio backends are missing | None |

See [Platform Support](docs/platform-support.md) (Chinese) for detailed capabilities and limitations.

<br>

## Install and Use

Download and install the Android APK from [Releases](https://github.com/Starlordzz/sunsetripple/releases).

1. For Wi-Fi rooms, use a shared LAN, personal hotspot, or Wi-Fi Direct. For Bluetooth rooms, enable Bluetooth.
2. Create a room on one device, select the room type, and grant the requested microphone and nearby-device permissions.
3. On the other devices, search for nearby rooms and join.
4. Speak freely in Wi-Fi rooms. In Bluetooth rooms, hold the central disc to speak and release it to listen.

<br>

## Privacy and Security

Voice and in-room messages are not relayed through a cloud server. Manual update checks access GitHub Releases. **Session encryption is disabled by default; default sessions are not end-to-end encrypted.**

<br>

## Build from Source

The main app uses Flutter / Dart and is currently built and maintained for Android only (via Kotlin native plugins and the C++ core); `ios/` and `harmonyos/` are frozen as placeholders.

Development requirements: Flutter **3.29.0** (matching [CI](.github/workflows/flutter-ci.yml)), JDK 17, and the Android SDK.

```sh
# Bash / Git Bash: use the package host recorded in the lockfile
export PUB_HOSTED_URL=https://pub.flutter-io.cn
flutter pub get --enforce-lockfile
flutter run
```

Checks and packaging (release APK builds require signing credentials in `android/key.properties`):

```sh
flutter analyze
flutter test
bash scripts/check-clock-injection.sh
flutter build apk --release
```

The clock-injection check requires Bash. The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

For archived build notes on the frozen platforms, see [iOS notes (frozen)](docs/ios-flutter-port.md) and [HarmonyOS notes (frozen)](docs/harmonyos-build.md).

<br>

## Documentation

- [Documentation home](docs/wiki/en/Home.md)
- [Architecture overview](docs/wiki/en/Architecture-Overview.md)
- [Build and release](docs/wiki/en/Build-and-Release.md)
- [Troubleshooting](docs/wiki/en/Troubleshooting.md)
- [Changelog](CHANGELOG.md)

<br>

## License

[Apache License 2.0](LICENSE) · Copyright 2026 Starlordzz
