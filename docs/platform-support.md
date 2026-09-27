# 平台支持范围（Platform Support Scope）

本文件是**唯一权威的平台能力声明**。README、pubspec 描述与 Issue 模板如与
本文件冲突，以本文件为准。

## 支持的平台

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| **Android 8.0+ (API 26)** | ✅ 完整支持 | WiFi 房（局域网/热点/Wi-Fi Direct）、蓝牙 PTT 房、房内文字、房主转移、自动更新 |
| **iOS 15.0+** | 🚧 部分支持 | 音频与 BLE 插件已就绪；**搜房未接入 Bonjour，实际不可用**（见下） |
| **HarmonyOS NEXT** | 🚧 实验性 | `harmonyos/` 是独立 ArkTS 工程，仅有 UDP 房间发现；**数据面未接通**，无 `.hap` 产物 |
| **Windows / macOS / Linux** | ❌ 不支持 | 无桌面音频后端，见下 |

## 桌面端（Windows / macOS / Linux）为什么标记为不支持

`windows/`、`linux/`、`macos/` 三个目录目前是 **Flutter 脚手架模板**：

- 没有任何 `MethodChannel` 实现（`grep -r MethodChannel windows linux macos` 无命中），
  因此 `PlatformAudioChannel` 的全部调用都会抛 `MissingPluginException`；
- `native/CMakeLists.txt` 只被 Android 的 Gradle 引用，**没有任何脚本产出**
  `sunset_ripple_native.dll`（`NativeCoreFfi` 在 Windows 上会去找它）；
- 结果：可以编译出窗口，但**没有声音、无法对讲**。

保留这三个目录只是「未来的占位」。`pubspec.yaml` 的 `description` 不再宣称
支持桌面端，以免用户下载后得到「界面正常但没有声音」的体验——这正是历史上
`PlatformAudioChannel` 吞掉 `MissingPluginException` 时最难排查的一类问题。

**要让它真正可用，需要补齐**：桌面音频采集/播放后端（WASAPI / CoreAudio /
PulseAudio）、`native/` 的桌面构建脚本、以及桌面端的传输层适配（BLE L2CAP
与 Wi-Fi Direct 在桌面不可用，需要退化为纯 UDP）。

## iOS 搜房为何仍不可用

iOS 14+ 起，向 `255.255.255.255` 发 UDP 广播需要
`com.apple.developer.networking.multicast` 授权（付费开发者账号 + Apple 逐案审批）。
本项目没有付费账号，因此 iOS 侧必须改走 **Bonjour**（系统代为完成组播）。

`ios/Runner/Info.plist` 已声明 `NSBonjourServices`，但 **Dart 侧的
`LanRoomDiscovery` 仍是裸广播，尚未接入 Bonjour**。所以：

- 同 WiFi/热点下**作为客户端手动输入地址**的路径可用；
- 「看看附近」的房间列表在 iOS 上**收不到任何结果**。

## 鸿蒙的现状

`harmonyos/` 只有 **UDP 房间发现**（`LanRoomDiscovery.ets`）、音频引擎骨架与
一个 63 行的会话管理器；`HarmonyRoomSession.onLocalAudioCaptured` 是空实现
（注释写着「可在此打包 Frame 并通过 UDP 发送」）。发布产物是**源码工程 zip**，
需自行用 DevEco Studio 构建，CI 不产出 `.hap`（原因见
[构建与发布](构建与发布.md)）。

## 维护约定

- 新增平台能力时，**先改本文件**，再改 README 与代码；
- 不要把「能编译」当成「支持」——判据是**该平台核心场景端到端可用**；
- 桌面目录在补齐后端之前不接受与平台能力无关的重构（避免给人「正在支持桌面」的错觉）。
