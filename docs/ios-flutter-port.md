# iOS Flutter 端接通计划

`ios/Runner/` 目前是一个**未经改动的 Flutter 脚手架**。CI 里的
`build-ios-flutter` job 能产出一个真实的 `.ipa`（与 Android 同源，含完整
Flutter 引擎与 Dart 会话核心），但**装上后除界面外没有任何功能可用**。

在这些缺口补齐之前，请继续使用 `build-ios-native` 产出的
`SunsetRipple-native-*-unsigned.ipa`——那是 `ios/SunsetRipple/` 下的独立
SwiftUI 实现，自带 AVAudioEngine 音频与 MultipeerConnectivity 发现。

## 缺口清单

### 1. 平台音频通道未实现（阻断级）

`ios/Runner/PlatformAudioPlugin.swift` 是**空文件**（0 字节），
`ios/Runner/AppDelegate.swift` 是原版模板，只调了
`GeneratedPluginRegistrant.register`。整个 `ios/` 目录搜不到一个
`MethodChannel`。

Dart 侧 `PlatformAudioChannel` 会收到 `MissingPluginException`。注意
`lib/core/platform/platform_audio_channel.dart:13-15` 的注释——作者在
Android 上踩过同一个坑，症状是「界面一切正常但没有声音」。

需要实现的契约（与 `android/.../PlatformAudioPlugin.kt` 完全对齐）：

| 通道 | 类型 | 名称 |
| --- | --- | --- |
| 方法 | `MethodChannel` | `host.msknet.sunsetripple/audio` |
| 事件 | `EventChannel` | `host.msknet.sunsetripple/audio_events` |

方法共 10 个：`startCapture` `stopCapture` `stopPlayback`
`submitRemoteFrame` `setBitrate` `setMuted` `setSpeakerphone`
`setUseBuiltinMic` `removeRemoteMember` `clearRemoteMembers`。

可直接移植 `ios/SunsetRipple/Audio/VoiceProcessingAudioEngine.swift`——
它已经用 `AVAudioEngine` + `.voiceChat` 模式拿到了硬件 AEC/NS/AGC。

### 2. WiFi 搜房被 Apple 挡死（需改架构）

`lib/core/transport/lan_discovery.dart:152` 把发现包发往
`InternetAddress("255.255.255.255")`。iOS 14+ 起，**发送广播或组播需要
`com.apple.developer.networking.multicast` 授权**，该授权要求付费
Apple Developer Program 账号并经 Apple 逐案审批。没有账号则此路不通。

好消息是**音频通路不受影响**：`lan_transport.dart:413` 与 `:441` 都是
单播（`socket.send(bytes, endpoint.address, endpoint.port)`），只需
`NSLocalNetworkUsageDescription` 即可，该权限已在 `Info.plist` 中补齐。

所以只有「发现」这一步需要换机制。两个免授权方案：

- **Bonjour**（推荐）：iOS 侧用 `NWBrowser` / `NWListener` 注册与浏览
  `_sunsetripple._udp`，由系统代做组播。`Info.plist` 的
  `NSBonjourServices` 已预先声明好这两个服务类型。发现到 peer 后解析出
  IP/端口交回 Dart，后续单播流程完全复用现有代码。
- **MultipeerConnectivity**：`ios/SunsetRipple/Transport/MultipeerTransport.swift`
  已有实现，但它自带一套传输语义，与 Dart 的帧协议耦合度更高。

无论选哪个，都需要把 `LanRoomDiscovery` 抽象成按平台可替换的发现策略：
Android 保留 UDP 广播，iOS 走平台通道。

### 3. BLE L2CAP 未实现

`ios/` 下没有任何 `CBL2CAPChannel` 代码。需对齐 Android
`BleL2capPlugin.kt` 的三个通道：

- `host.msknet.sunsetripple/ble_l2cap`（方法）
- `host.msknet.sunsetripple/ble_l2cap_data`（事件）
- `host.msknet.sunsetripple/ble_l2cap_scan`（事件）

`CBL2CAPChannel` 不需要 MFi 认证，也不需要特殊授权，
`NSBluetoothAlwaysUsageDescription` 已补齐。

### 4. 原生 C++ 未接入 Runner target

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
