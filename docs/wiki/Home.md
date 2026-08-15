# 落日后残波 · Wiki

> 落日之后，波纹仍在替我们说着那天没说完的话。
>
> *The sun has gone; the ripple hasn't.*

这里是 **落日后残波（SunsetRipple）** 的完整技术文档。项目本体见 [README](../../README.md)。

## 这是什么

一个 Android 近场语音对讲应用：不联网、不过服务器，用手机自带的 WiFi Direct 与经典蓝牙，在最多 6 台设备之间拉起临时语音房。

## 按需求找页面

| 你想做的事 | 去这里 |
| --- | --- |
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

1. **[架构总览](架构总览.md)** —— 先建立分层心智模型：`ui → session → transport → protocol`，以及 `audio` 如何横切。
2. **[协议规范](协议规范.md)** —— 帧格式是整个系统的中枢，看懂 8 种帧类型就看懂了大半交互。
3. **[房间模式对比](房间模式对比.md)** —— 理解为什么同一套会话层要长出两种截然不同的房间。
4. **[音频管线](音频管线.md)** —— 采集、编码、抖动缓冲、混音、播放的完整链路。
5. **[房主转移机制](房主转移机制.md)** —— 全项目最复杂的部分，建议放在最后读。

## 关键事实速查

| 项 | 值 |
| --- | --- |
| 包名 | `host.msknet.sunsetripple` |
| 当前版本 | `0.1.0-alpha.2`（versionCode 3） |
| 最低系统 | Android 8.0 / API 26 |
| 目标 / 编译 SDK | 35 |
| 语言与 UI | Kotlin 2.0.20 + Jetpack Compose |
| 源码规模 | 58 个 Kotlin 源文件 |
| 测试规模 | 36 个测试文件，243 个测试方法，纯 JVM |
| 音频编码 | Opus（Concentus 纯 JVM）16 kHz 单声道 20 ms |
| 房间容量 | 6 台设备（含房主） |
| 许可证 | Apache-2.0 |

## 项目约定

- **界面文案全部为简体中文**，且硬编码在 Kotlin 中——项目没有 `strings.xml`，也没有做多语言。
- **没有依赖注入框架、没有数据库、没有网络库**——传输层直接用 `java.net` 与 `android.bluetooth`。
- **测试不使用 Robolectric / MockK / Mockito**，全部是手写 fake，因此可在纯 JVM 上秒跑。
- **纯决策逻辑一律抽成不依赖 Android 的对象**（如 `HostElection`、`RoomFlow`、`RoomPermissions`、`BluetoothMixPlanner`），这是测试覆盖率能做厚的根本原因。

## 相关链接

- [Releases](https://github.com/Starlordzz/sunsetripple/releases) —— 已签名 APK 下载
- [CHANGELOG](../../CHANGELOG.md) —— 版本变更记录
- [LICENSE](../../LICENSE) —— Apache-2.0
