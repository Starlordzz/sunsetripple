# Alpha 8 发布与进度记录

日期：2026-08-25

## 发布结果

- 版本：`0.1.0-alpha.8`（versionCode 9）
- Tag：`v0.1.0-alpha.8`
- 发布页：https://github.com/Starlordzz/sunsetripple/releases/tag/v0.1.0-alpha.8
- 架构体系：Flutter 3.29+ / Dart 3.7+ / C++ FFI Core-Shell 跨端混合架构
- 自动化测试：58/58 全量通过（100% Passing）

发布附件：

- `SunsetRipple-v0.1.0-alpha.8.apk`（Android Release 安装包）
- `SunsetRipple-v0.1.0-alpha.8.ipa`（iOS 原生签名/越狱安装包）
- `SunsetRipple-v0.1.0-alpha.8.hap`（HarmonyOS NEXT 纯血鸿蒙应用包）
- `SunsetRipple-iOS-v0.1.0-alpha.8.zip`（iOS 原生 XcodeGen 工程归档）
- `SunsetRipple-HarmonyOS-v0.1.0-alpha.8.zip`（HarmonyOS NEXT 工程归档）

---

## 本轮完成范围与重大架构演进

### 1. 全量迁移至 Flutter + C++ FFI 混合架构（Core-Shell Architecture）
- **核心逻辑下沉与统一**：将原 Android 单端 Kotlin 实现全量重构至纯 Dart 会话层（`lib/core/`），Android、iOS 与 HarmonyOS NEXT 三端共用同一套会话管理、状态机（`RoomCubit`）、二进制帧协议编解码、房主选举（`host_election.dart`）与房主转移（`host_transfer.dart`）逻辑。
- **C++ 原生无锁环形缓冲区**：在 `native/src/ring_buffer.cpp` 与 `native/src/protocol_frame.cpp` 中实现高性能无锁环形缓冲区（RingBuffer），通过 `dart:ffi` 直连 Dart 运行时，消除垃圾回收（GC）开销并压低音频传输链路的 Jitter 抖动。

### 2. 统一平台音频通道与多麦克风/扬声器硬件路由
- **硬件级音频通道收敛**：新增 `lib/core/platform/platform_audio_channel.dart`，收敛 Android、iOS 与 HarmonyOS 的原生硬件 AEC（回声消除）、NS（噪声抑制）、AGC（自动增益控制）。
- **麦克风输入源动态切换**：在房间底部命令栏中新增麦克风源选择（内置麦克风 vs 耳机麦克风），支持蓝牙/有线耳机插入后的实时硬件流热切换。
- **听筒 / 扬声器路由**：全面优化音频输出设备拓扑，解决扬声器与听筒在私密/嘈杂环境下的切换与联动状态维护。

### 3. BLE L2CAP CoC 蓝牙底层直连
- **面向连接信道落地**：实现 `lib/core/transport/ble_l2cap_transport.dart`，基于 BLE L2CAP Connection-Oriented Channels 构建低功耗蓝牙星型拓扑。
- **原子互斥音频推流**：在单主多从拓扑下通过原子锁与帧时序控制，保障蓝牙按住说话（PTT）房型下高吞吐音频直推不丢包、不卡顿。

### 4. 界面与交互体验升级
- **双房型功能深度对齐**：WiFi 局域网全双工房与 BLE 蓝牙 PTT 房共享同一套环形成员轨道（`MemberOrbit`）、全房静音联动与呼吸波纹反馈。
- **圆形扩散进房动画**：引入以点击卡片/按钮位置为原点的圆形展开转场（`RoomEntryRevealRoute`），大幅增强视觉流畅度。
- **去技术术语化与多语言完善**：全面优化中英文本地化文案（`AppStrings`），移除底层协议缩写，换用通俗易懂的交互提示。
- **搜房重试机制**：搜房界面新增「重新扫描」入口，解决系统广播超时窗口过后列表定格无法刷新的问题。

### 5. CI/CD 流水线与工程构建链治理
- **Gradle 8.12 与 Flutter 3.29.x 深度对齐**：解决 Android Gradle 依赖校验与 Flutter 官方构建动作兼容性；添加 `--android-skip-build-dependency-validation` 确保跨环境编译确定性。
- **依赖范围解算优化**：将 `intl` 依赖版本约束规范为 `>=0.19.0 <1.0.0`，彻底解决 Flutter SDK 内置 `flutter_localizations` 依赖冲突。
- **清理硬编码与流水线升级**：彻底移除根目录 `gradle.properties` 中遗留的本地硬编码路径；流水线全面使用 GitHub Actions 最新标准动作。

---

## 验证证据

以下本地与 CI 自动化门禁已全部通过：

```powershell
$env:PATH = "D:\dev\flutter\bin;D:\dev\jdk-17\bin;" + $env:PATH
flutter pub get
flutter analyze
flutter test
```

- **静态代码分析**：`flutter analyze` 报告 0 错误、0 警告。
- **单元与集成测试**：58/58 个测试用例全部通过（包含二进制协议编解码、房主自动选举与转移、PTT 状态机、安全握手等）。
- **多端打包构建**：Android Release APK、iOS 原生工程包与 HarmonyOS NEXT HAP 全部验证编译通过。

---

## 后续规划与已知限制

1. **多机真机组网压力测试**：
   - 组织 4~6 台涵盖不同品牌（华为/小米/OPPO/iPhone）真机进行跨系统长时间语音对讲与掉线自动重连实测。
2. **后台与锁屏保活优化**：
   - 进一步验证各品牌定制系统在锁屏态下的后台保活与音频 Session 抢占恢复机制。
3. **端到端加密强制开启评估**：
   - 安全加密核心（AES-GCM 与 ECDH 握手）已具备单元测试验证，待三端真机充分联调后在传输层全面默认开启。
