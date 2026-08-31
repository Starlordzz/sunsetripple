# iOS Flutter 端接通与架构收敛记录

从 v0.1.0-alpha.9 起，iOS 平台已彻底废弃并移除独立的 SwiftUI 子工程（`ios/SunsetRipple/`），全面收敛至 Flutter 统一宿主（`ios/Runner/`）。

三端（Android / iOS / HarmonyOS）实现 100% 共享 Dart 会话核心（`lib/core/`）、二进制帧协议与 C++ FFI。

---

## 落地清单

### 1. 平台音频通道（已完成）

`ios/Runner/PlatformAudioPlugin.swift` 已完整实现统一平台音频通道：
- 对齐方法通道：`host.msknet.sunsetripple/audio`
- 对齐事件通道：`host.msknet.sunsetripple/audio_events`
- 基于 Apple 硬件声学前端 `VoiceProcessingIO` AudioUnit，提供硬件级回声消除（AEC）、噪声抑制（NS）与自动增益（AGC）。
- 具备 16kHz / 单声道 / 20ms（320 采样点）PCM 实时采集、RMS 能量电平计算、多路远端音频饱和混音与听筒/扬声器/麦克风动态路由。

### 2. BLE L2CAP 蓝牙面向连接信道（已完成）

`ios/Runner/BleL2capPlugin.swift` 基于 `CoreBluetooth` 完整实现：
- 方法通道：`host.msknet.sunsetripple/ble_l2cap`
- 数据事件通道：`host.msknet.sunsetripple/ble_l2cap_data`
- 扫描事件通道：`host.msknet.sunsetripple/ble_l2cap_scan`
- 房主（Peripheral / Host）发布 L2CAP 信道（`publishL2CAPChannel`）并广播动态 PSM；成员（Central / Client）扫描并连接 `CBL2CAPChannel` 进行双向二进制帧流式收发。

### 3. Flutter 引擎生命周期与插件注册（已完成）

`ios/Runner/AppDelegate.swift` 在 `application(_:didFinishLaunchingWithOptions:)` 中自动挂载并注册 `PlatformAudioPlugin` 与 `BleL2capPlugin`。

### 4. 权限声明与后台模式（已完成）

`ios/Runner/Info.plist` 已配置好：
- 麦克风权限（`NSMicrophoneUsageDescription`）
- 本地网络权限（`NSLocalNetworkUsageDescription`）
- 蓝牙权限（`NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription`）
- Bonjour 服务类型（`_sunsetripple._udp` / `_sunsetripple._tcp`）
- 后台音频与蓝牙保活（`UIBackgroundModes`: `audio`, `bluetooth-central`, `bluetooth-peripheral`）

---

## 关于构建与签名

- CI/CD 在 GitHub Actions（`release.yml`）通过 `flutter build ios --release --no-codesign` 产出统一未签名 IPA（`SunsetRipple-*-ios-unsigned.ipa`）。
- 仓库当前未配置付费 Apple 开发者证书，安装包需用户使用 AltStore 或 Sideloadly 配合个人 Apple ID 在电脑端重签名后安装。

