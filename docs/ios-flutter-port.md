# iOS Flutter 端架构与适配进展

从 v0.1.0-alpha.9 起，iOS 平台已彻底废除并移除早期的独立 SwiftUI 子工程（`ios/SunsetRipple/`），全面收敛至 Flutter 统一宿主（`ios/Runner/`）。

三端（Android / iOS / HarmonyOS）基于同一套二进制帧协议与会话模型演进，iOS 与 Android 100% 共享 Dart 会话核心（`lib/core/`）与 UI 界面。

## 落地清单

### 1. 平台音频通道（已实现）

`ios/Runner/PlatformAudioPlugin.swift` 已完整实现统一平台音频通道：
- 对齐方法通道：`host.msknet.sunsetripple/audio`
- 对齐事件通道：`host.msknet.sunsetripple/audio_events`
- 基于 Apple 硬件声学前端 `VoiceProcessingIO` AudioUnit，提供硬件级回声消除（AEC）、噪声抑制（NS）与自动增益（AGC）。
- 具备 16kHz / 单声道 / 20ms（320 采样点）PCM 实时采集、RMS 能量电平计算、多路远端音频饱和防爆音混音与听筒/扬声器/外接麦克风动态路由。

### 2. BLE L2CAP 蓝牙面向连接信道（已实现）

`ios/Runner/BleL2capPlugin.swift` 基于 `CoreBluetooth` 完整实现：
- 方法通道：`host.msknet.sunsetripple/ble_l2cap`
- 数据事件通道：`host.msknet.sunsetripple/ble_l2cap_data`
- 扫描事件通道：`host.msknet.sunsetripple/ble_l2cap_scan`
- 房主（Host）发布动态 PSM 广播；成员扫描并连接 `CBL2CAPChannel` 进行全双工点对点数据流通讯。无需 MFi 硬件认证。

---

## 推进中事项

### 1. WiFi 搜房方案切换为 Bonjour

`lib/core/transport/lan_discovery.dart:152` 把发现包发往 `InternetAddress("255.255.255.255")`。iOS 14+ 起，发送广播或组播需要 `com.apple.developer.networking.multicast` 授权，该授权要求付费 Apple Developer Program 账号并经 Apple 逐案审批。
- 音频单播通路不受影响（`lan_transport.dart` 为单播，只需 `NSLocalNetworkUsageDescription`）。
- 搜房方案：iOS 侧通过 `NWBrowser` / `NWListener` 注册与浏览 `_sunsetripple._udp`，由系统代做组播发现并交回 Dart。`Info.plist` 的 `NSBonjourServices` 已预先声明好这两个服务类型。

### 2. 原生 C++ 接入 Runner target

`ios/Runner.xcodeproj/project.pbxproj` 没有引用 `native/src/*.cpp`，
`NativeCoreFfi` 在 iOS 上会走 `DynamicLibrary.process()` 查不到符号，
静默退回纯 Dart 实现（见 `native_core_ffi.dart:72-75`，不会崩）。

接入方式：把 `native/src/{ring_buffer,audio_dsp,protocol_frame}.cpp`
加入 Runner target 的 Sources 构建阶段即可静态链接，Dart 侧无需改动。

`FFI_EXPORT` 已补上 `__attribute__((used))`——否则 release 构建的
`-dead_strip` 会把这些符号剥掉，因为链接期没有任何引用，
只有 Dart 在运行时查。

## 已完成的前置工作

- `ios/Runner/Info.plist`：补齐麦克风、本地网络、蓝牙权限说明与
  `NSBonjourServices`、`UIBackgroundModes`。此前**一条权限声明都没有**，
  一录音就会崩。
- `native/src/*`：`FFI_EXPORT` 增加 `__attribute__((used))`。
- CI：新增 `build-ios-flutter` job，产出未签名 Flutter IPA。

## 关于签名

仓库当前没有 Apple Developer Program 账号，所有 iOS 产物均为**未签名**，
需用户以自己的 Apple ID 通过 AltStore / Sideloadly 在本地重签后安装。

若日后取得付费账号，在 `release.yml` 中接入证书 `.p12` 与描述文件
secrets 即可产出 ad-hoc 签名 IPA，配合 `itms-services` 清单实现
「点链接直装」——但仍需预先登记设备 UDID。
