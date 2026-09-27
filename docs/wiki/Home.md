> 🌐 [English](en/Home.md) | 简体中文

# 落日后残波 · Wiki

> 落日之后，波纹仍在替我们说着那天没说完的话。
>
> *The sun has gone; the ripple hasn't.*

这里是 **落日后残波（SunsetRipple）** 的完整技术文档。项目本体见 [README](../../README.md)。

## 这是什么

一个去中心化近场语音对讲应用（Android / iOS / HarmonyOS NEXT）：语音不过服务器，在最多 6 台设备之间拉起临时语音房，支持局域网 / 热点 / Wi-Fi Direct 免路由直连与蓝牙 BLE 对讲两种房型；版本检查按用户操作访问 GitHub。

<p align="center">
  <img src="../screenshots/showcase-zh.png" width="720" alt="落日后残波 · 界面预览">
  <br>
  <sub>首页 · Wi-Fi 畅聊房 · 蓝牙对讲（月夜）· 房内消息</sub>
</p>

## 按需求找页面

| 你想做的事 | 去这里 |
| --- | --- |
| 跨平台架构与 Core-Shell 设计 | [Core-Shell 统一多端架构](Core-Shell统一多端架构.md) |
| 哪些平台真的能用（权威声明） | [平台支持范围](../../platform-support.md) |
| 适配 iOS 苹果端 (AudioUnit / CoreBluetooth L2CAP) | [iOS 平台适配指南](iOS平台适配指南.md) |
| 适配 HarmonyOS NEXT 纯血鸿蒙 | [HarmonyOS 平台适配指南](HarmonyOS平台适配指南.md) |
| 快速理解整个项目怎么搭的 | [架构总览](架构总览.md) |
| 实现一个兼容客户端 / 抓包分析 | [协议规范](协议规范.md) |
| 搞清楚该用 WiFi 房还是蓝牙房 | [房间模式对比](房间模式对比.md) |
| 调音质、改码率、理解延迟来源 | [音频管线](音频管线.md) |
| 理解房主退出后房间为什么没散 | [房主转移机制](房主转移机制.md) |
| 把源码编译成可安装的包 | [构建与发布](构建与发布.md) |
| 连不上、没声音、老掉线 | [故障排查](故障排查.md) |
| 一般性疑问 | [常见问题](常见问题.md) |

> 全部页面均有英文版（双语同步维护），入口：**[English Wiki](en/Home.md)**。

## 建议阅读顺序

新接手这个代码库，按这个顺序读最省力：

1. **[Core-Shell 统一多端架构](Core-Shell统一多端架构.md)** —— 理解跨平台核心与多端 Shell 之间的分层契约。
2. **[架构总览](架构总览.md)** —— 先建立分层心智模型：`ui → session → transport → protocol`，以及 `audio` 如何横切。
3. **[协议规范](协议规范.md)** —— 帧格式是整个系统的中枢，看懂 14 种帧类型就看懂了大半交互。
4. **[房间模式对比](房间模式对比.md)** —— 理解为什么同一套会话层要长出两种截然不同的房间。
5. **[音频管线](音频管线.md)** —— 采集、编码、抖动缓冲、混音、播放的完整链路。
6. **[房主转移机制](房主转移机制.md)** —— 全项目最复杂的部分，建议放在最后读。

## 关键事实速查

| 项 | 值 |
| --- | --- |
| 包名 / BundleID | `host.msknet.sunsetripple` |
| 当前版本 | `0.1.0-alpha.13`（versionCode 14） |
| 支持系统 | Android 8.0+ / iOS 15.0+ / HarmonyOS NEXT (API 12+) |
| 目标 / 编译 SDK | Android 35 / HarmonyOS 5.0(12) / iOS 15.0 |
| 语言与 UI | Flutter (Dart) + C++ DSP 核心，设备侧经 Kotlin / Swift / ArkTS 平台通道接入 |
| 测试规模 | `flutter test` 共 144 个自动化测试用例 |
| 音频编码 | Opus（Android 用 Concentus 纯 JVM 实现；iOS 仍为原始 PCM、Opus 未接入，已知缺口）16 kHz 单声道 20 ms；原生硬件 AEC/NS/AGC；C++ FFI 提供无锁环形缓冲、RMS 与 PCM 混音，并含纯 Dart 回退 |
| 房间容量 | 6 台设备（含房主） |
| 许可证 | Apache-2.0 |

## 项目约定

- **界面文案双语**：通过 `lib/l10n/app_strings.dart` 自动跟随系统切换中文或英文，资源测试校验两套 key 与格式占位符一致。
- **更新默认拒绝未签名内容**：清单、APK 哈希、包名和证书依次校验，安装交给 Android 确认。
- **诊断必须由用户主动导出**，且不包含音频、昵称原文、设备地址和密钥材料。
- **没有依赖注入框架、没有数据库、没有网络库**——传输层在 Dart 侧：`LanTransport` 走 `dart:io` socket，`BleL2capTransport` 走 Flutter MethodChannel，Android 插件在通道后用 Android BLE / Wi-Fi API 干活。
- **测试全部是 Dart（`flutter test`）**，不使用 Robolectric / MockK / Mockito（那些是 JVM 工具），而是 `MockAudioIo` 等手写 fake。
- **纯决策逻辑一律抽成不依赖平台的 Dart 对象**（如 `HostElection`，见 `lib/core/session/host_transfer.dart`），这是测试覆盖率能做厚的根本原因。
- **建房转场直接揭示真实房间界面**，首页与房间共用落日页头的运动相位和同源配色；不存在动画结束后再切页的第二阶段。
- **房内控制保持轻量**：成员轨道、频道核心、静音、扬声器和离开操作按使用频率分层，危险操作不再占据主要视觉位置。
- **昼夜两套配色共用同一批槽位语义**：浅色是落日，夜间是月与海面，两者复用同一份绘制代码，因此页头那轮天体不改几何就从落日变成月亮。档位分跟随系统 / 浅色 / 深色三档，入口在首页页头右上角。

## 相关链接

- [Releases](https://github.com/Starlordzz/sunsetripple/releases) —— 三端安装包与工程源码下载（注：iOS 提供纯原生 ARM64 极小体积极速安装包；HarmonyOS `.hap` 暂为占位，请下载完整源码工程使用 DevEco Studio 本地编译）
- [CHANGELOG](../../CHANGELOG.md) —— 版本变更记录
- [LICENSE](../../LICENSE) —— Apache-2.0
