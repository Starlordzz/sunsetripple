# 落日后残波 · Wiki

> 落日之后，波纹仍在替我们说着那天没说完的话。
>
> *The sun has gone; the ripple hasn't.*

这里是 **落日后残波（SunsetRipple）** 的完整技术文档。项目本体见 [README](../../README.md)。

## 这是什么

一个 Android 近场语音对讲应用：语音不过服务器，用手机自带的 WiFi Direct 与经典蓝牙，在最多 6 台设备之间拉起临时语音房；版本检查按用户操作访问 GitHub。

## 按需求找页面

| 你想做的事 | 去这里 |
| --- | --- |
| 跨平台架构与 Core-Shell 设计 | [Core-Shell 统一多端架构](Core-Shell统一多端架构.md) |
| 适配 iOS 苹果端 (AudioUnit / Multipeer) | [iOS 平台适配指南](iOS平台适配指南.md) |
| 适配 HarmonyOS NEXT 纯血鸿蒙 | [HarmonyOS 平台适配指南](HarmonyOS平台适配指南.md) |
| 快速理解整个项目怎么搭的 | [架构总览](架构总览.md) |
| 实现一个兼容客户端 / 抓包分析 | [协议规范](协议规范.md) |
| 搞清楚该用 WiFi 房还是蓝牙房 | [房间模式对比](房间模式对比.md) |
| 调音质、改码率、理解延迟来源 | [音频管线](音频管线.md) |
| 理解房主退出后房间为什么没散 | [房主转移机制](房主转移机制.md) |
| 把源码编译成可安装的包 | [构建与发布](构建与发布.md) |
| 连不上、没声音、老掉线 | [故障排查](故障排查.md) |
| 一般性疑问 | [常见问题](常见问题.md) |

## 建议阅读顺序

新接手这个代码库，按这个顺序读最省力：

1. **[Core-Shell 统一多端架构](Core-Shell统一多端架构.md)** —— 理解跨平台核心与多端 Shell 之间的分层契约。
2. **[架构总览](架构总览.md)** —— 先建立分层心智模型：`ui → session → transport → protocol`，以及 `audio` 如何横切。
3. **[协议规范](协议规范.md)** —— 帧格式是整个系统的中枢，看懂 8 种帧类型就看懂了大半交互。
4. **[房间模式对比](房间模式对比.md)** —— 理解为什么同一套会话层要长出两种截然不同的房间。
5. **[音频管线](音频管线.md)** —— 采集、编码、抖动缓冲、混音、播放的完整链路。
6. **[房主转移机制](房主转移机制.md)** —— 全项目最复杂的部分，建议放在最后读。

## 关键事实速查

| 项 | 值 |
| --- | --- |
| 包名 / BundleID | `host.msknet.sunsetripple` |
| 当前版本 | `0.1.0-alpha.7`（versionCode 8） |
| 支持系统 | Android 8.0+ / iOS 15.0+ / HarmonyOS NEXT (API 12+) |
| 目标 / 编译 SDK | Android 35 / HarmonyOS 5.0(12) / iOS 15.0 |
| 语言与 UI | Kotlin (Compose) + ArkTS (ArkUI) + Swift (SwiftUI) |
| 测试规模 | 40 个测试文件，255 个测试方法，纯 JVM |
| 音频编码 | Opus（Concentus 纯 JVM / 原生 AEC）16 kHz 单声道 20 ms |
| 房间容量 | 6 台设备（含房主） |
| 许可证 | Apache-2.0 |

## 项目约定

- **界面自动跟随系统中文或英文**，资源测试校验两套 key 与格式占位符一致。
- **更新默认拒绝未签名内容**：清单、APK 哈希、包名和证书依次校验，安装交给 Android 确认。
- **诊断必须由用户主动导出**，且不包含音频、昵称原文、设备地址和密钥材料。
- **没有依赖注入框架、没有数据库、没有网络库**——传输层直接用 `java.net` 与 `android.bluetooth`。
- **测试不使用 Robolectric / MockK / Mockito**，全部是手写 fake，因此可在纯 JVM 上秒跑。
- **纯决策逻辑一律抽成不依赖 Android 的对象**（如 `HostElection`、`RoomFlow`、`RoomPermissions`、`BluetoothMixPlanner`），这是测试覆盖率能做厚的根本原因。
- **建房转场直接揭示真实房间界面**，首页与房间共用落日页头的运动相位和同源配色；不存在动画结束后再切页的第二阶段。
- **房内控制保持轻量**：成员轨道、频道核心、静音、扬声器和离开操作按使用频率分层，危险操作不再占据主要视觉位置。
- **昼夜两套配色共用同一批槽位语义**：浅色是落日，夜间是月与海面，两者复用同一份绘制代码，因此页头那轮天体不改几何就从落日变成月亮。档位分跟随系统 / 浅色 / 深色三档，入口在首页页头右上角。

## 相关链接

- [Releases](https://github.com/Starlordzz/sunsetripple/releases) —— 已签名 APK 下载
- [CHANGELOG](../../CHANGELOG.md) —— 版本变更记录
- [LICENSE](../../LICENSE) —— Apache-2.0
