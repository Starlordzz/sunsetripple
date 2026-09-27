# Changelog

## 0.1.0-alpha.14 - 2026-09-27

### 发布链路（最高优先级）

- 修复 release 签名链路：`release.yml` 现在从 `ANDROID_KEYSTORE_BASE64` 等 secrets
  还原 keystore 并写入 `android/key.properties`；此前 CI 拿不到签名材料，
  `flutter build apk --release` 必然回落 **debug 签名**，每个 release 的签名都不同，
  用户升级报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，只能卸载重装
- `android/app/build.gradle.kts` 缺少签名材料时**直接失败**并给出修复指令，
  不再静默产出不可发布的「正式包」；本地自测需显式加 `-PallowDebugSigning=true`
- 新增 APK 签名断言：产物若为 `CN=Android Debug` 则 CI 失败
- `scripts/setup-release-signing.sh` 修正为写入 Gradle 实际读取的
  `android/key.properties`（此前写根目录 `keystore.properties`，跑完仍回落 debug），
  新增 CI secrets 自动配置，并从 `.gitignore` 恢复纳管
- CI 新增门禁：`flutter analyze`、`dart format --set-exit-if-changed`、
  行覆盖率阈值（当前基线 65.5%，门槛 60）、`--enforce-lockfile`、覆盖率产物上传

### 安全

- **安全信封改为失败关闭**：配置 `secureCodec` 后，一切非 `sealed` / 非握手帧的
  明文业务帧一律丢弃。此前只加密出站、入站照收明文，攻击者继续发明文帧即可
  注入聊天与状态，会得出「已启用 E2E」的错误结论
- **蓝牙房房主转发重写 `senderId`**：L2CAP 是链路寻址，接收端没有 LAN 房那种
  「按连接身份重写」的机会。房主现在按 `bindMember(peerAddress, memberId)`
  绑定关系重写帧头，未绑定链路按 `senderId=0` 丢弃，堵住成员冒用他人身份
  发言、撤回、伪造 PTT 的路径（Kotlin / Swift / Dart 三侧同步）
- 诊断报告补齐 **IPv6 与平台信息脱敏**（此前只脱敏 MAC/IPv4，纯 IPv6 网络下
  导出报告带出完整对端地址）；新增 `environment` 字段
- release 构建丢弃 debug/info 日志（这些日志含对端 IP、端口与昵称）

### 协议

- **统一聊天文本预算**：`ChatMessagePayload.maxTextBytes` 由 480 收敛为 368，
  与 `chatSync` 共享。此前 chat 允许 480 字节而历史同步只有约 466 字节预算，
  一条 467~480 字节的合法消息会让新成员的**历史同步在循环中途整段中断**；
  启用安全信封时更会静默发送失败而本地仍显示已发送
- `chatSync` decode 补上 `messageId` / `nickname` 字段长度上界校验

### 工程

- 版本号收敛为**单一真相源** `lib/core/version.dart`，由
  `test/version_consistency_test.dart` 强制与 `pubspec.yaml`、`CHANGELOG.md`
  一致。此前版本号硬编码在 4 处（pubspec / UpdateService / AppStrings / 测试），
  必然漂移
- 测试改用**临时端口**（`startHost(port: 0)`）替代固定 8988/8989，
  消除并行测试文件互抢同一 socket 的 flaky；`ServerSocket.bind` 去掉 `shared: true`
- 新增 `test/ble_l2cap_binding_test.dart`：覆盖 join token → 链路绑定、
  成员移除解绑、客户端不发起绑定、stop 后绑定表复位
- 删除 0 字节占位文件 `harmonyos/.../plugin/PlatformAudioPlugin.ets`
- `pubspec.yaml` 描述修正为实际支持的平台（Android / iOS），不再宣称桌面端

## 0.1.0-alpha.13 - 2026-09-17

- 精简并彻底移除历史原生子工程，全面收拢至 Flutter 跨平台与 C++ FFI 架构
- 协议层全面规范化收拢：入房鉴权与房主交接强制校验 16 字节非零会话令牌
- 增强端到端协议边界防护与交接超限保护，杜绝异常帧与身份冲突
- 规范化 3 位数字设备标识码解析与同名冲突智能标注
- 优化 iOS 原生音频与蓝牙 L2CAP 插件挂载及路由容灾机制
- 同步更新中英文架构概览、协议规范与房主转移 Wiki 文档

## 0.1.0-alpha.12 - 2026-09-12

- 支持 Wi-Fi 直连与蓝牙建连失败即时提示及重试引导
- 支持连接异常中断保护与平滑退出首页
- 修复新成员重名加入导致本地在册成员 ID 被覆盖问题
- 优化原生 C++ 音频 RMS 能量计算精度
- 修复更新服务 SemVer 版本比对逻辑（忽略构建元数据）
- 规范化设备短码解析与 480 字节消息边界
- 支持全量英文 Wiki 与双语 README 界面预览图

## 0.1.0-alpha.11 - 2026-09-06

- 支持近场轻量文字对讲与即时消息面板（RoomChatSheet）
- 支持文字消息 100 条纯内存缓存与 LRU 消息去重
- 修复 Android 引擎注册 WifiDirectPlugin 导致的 P2P 静默失效
- 增强入房重连鉴权（改用 16 字节随机会话令牌）
- 增强文字历史同步帧与消息撤回权限校验
- 支持房主侧 UDP 语音面白名单过滤与未在册帧丢弃
- 支持房主侧 10 秒心跳超时自动清理离线成员
- 增强房间发现协议安全（同源校验与 64 条容量上限）
- 优化主动离房流程（推送底层 leave 帧后再断开）
- 对齐蓝牙 L2CAP 最大载荷为 512 字节并移除冗余 PTT 接口
- 优化进出房转场渲染性能与图层重绘
- 对音浪流与首页后台动画进行节流降耗
- 支持应用名称与副标题多语言本地化
- 优化首页房型选择卡等高自适应布局

## 0.1.0-alpha.10 - 2026-09-02

- 统一直连房与 WiFi 房体系及无网免路由直连拓扑
- 支持局域网组播与 Wi-Fi Direct 聚合展示及近场直连标签
- 适配 Android 14 系统广播安全策略（RECEIVER_EXPORTED）
- 优化 Wi-Fi Direct 离线近场定位权限申请流程
- 增强底层 P2P 繁忙状态退避重试与通道状态恢复
- 修复未连 Wi-Fi 离线状态下 UDP 广播未捕获异常
- 扩充 Wi-Fi Direct 与平台通道单元测试套件

## 0.1.0-alpha.9 - 2026-08-30

- 支持一镜到底舞台化进房转场（CelestialCanvas）
- 支持成员十六进制设备短码与同名区分
- 优化房间内各组件尺寸与屏幕自适应可读性
- 优化转场性能（延迟开麦与前景树按帧重建解耦）
- 修复离开房间响应卡顿（动画即时播放与网络后台收尾）
- 修复房间头部标题定位错误
- 修复 360dp 窄屏控制条及房型卡标题溢出
- 清理废弃的扩散式进房路由代码
- CI：为 Android Gradle 配置阿里云镜像仓库
- 新增转场端到端验收与多宽度溢出回归测试

## 0.1.0-alpha.8 - 2026-08-25

- 全量重构迁移至 Flutter/Dart 与 C++ FFI 混合架构
- 新增 C++ 原生无锁环形缓冲区与二进制帧编解码
- 支持 BLE L2CAP CoC 传输通道与蓝牙 PTT 房型
- 支持跨平台统一音频通道（硬件 AEC/NS/AGC）
- 引入 RoomCubit 状态管理与模块化会话解耦
- 对齐 WiFi 全双工与蓝牙 PTT 房功能交互体验
- 支持搜房界面手动「重新扫描」
- 修复部分机型平台音频通道名不匹配导致的采集异常
- 优化界面文案表述并去除生硬技术术语
- CI：升级 GitHub Actions CI/CD 工作流与依赖项

## 0.1.0-alpha.7 - 2026-08-22

- 支持跨端局域网及热点房间发现（LanRoomDiscovery）
- 新增 HarmonyOS NEXT 纯血鸿蒙原生工程与硬件 AEC
- 新增 iOS 原生工程与 MultipeerConnectivity 支持
- CI：扩展 Android、iOS、HarmonyOS NEXT 三端构建流水线
- 优化夜间模式「离开房间」按钮无障碍对比度
- 修复按住 PTT 讲话时主机下行混音被静音的问题

## 0.1.0-alpha.6 - 2026-08-20

- 修复安卓与鸿蒙 4 设备在 WiFi 房互搜兼容性问题
- 支持 WiFi 搜房超时后手动重新扫描
- 优化房内离开按钮浅色/深色主题对比度
- 丰富 P2P 底层错误码转译与发现日志
- 杂项：清理文档敏感路径与规划文件，补充 .hprof 忽略规则

## 0.1.0-alpha.5 - 2026-08-18

- 新增「关于与更新」页面与版本检查入口
- 支持签名更新清单校验、哈希比对与系统安装引导
- 支持安全握手核心与 AES-GCM 密封帧编解码
- 支持网络质量指标监控、脱敏诊断导出与系统级中英文切换
- 重构导航与会话生命周期协调器（RoomLifecycleCoordinator）
- 优化 Activity 重建与瞬态页面安全回退逻辑
- 限制在通话进行期间检查与下载更新
- 新增 Macrobenchmark 与 Baseline Profile 性能配置

## 0.1.0-alpha.4 - 2026-08-17

- 新增「月与海面」夜间深色主题配色
- 支持跟随系统/浅色/深色三档昼夜主题循环切换
- 支持通话过程中动态无缝切换昼夜主题
- 重构主题调色板对象并统一绘制逻辑
- 优化深色模式系统冷启动窗口过渡背景
- 修复深色模式下扫描提示条与房内工具栏对比度问题

## 0.1.0-alpha.3 - 2026-08-16

- 重构建房展开动画为点击原位圆形揭示转场
- 重新设计房内成员轨道、频道核心与轻量底部控制栏
- 统一应用横幅、启动图与房间落日波纹几何视觉
- 优化动画逐帧状态读取与绘制层重绘性能
- 优化非活跃状态动画资源消耗与转场曲线阻尼
- 修复转场结束时偶现闪黑与页面跳动问题
- 修复深色底部栏选中状态标签对比度不足

## 0.1.0-alpha.2 - 2026-08-15

- 支持前台通话期间屏幕常亮与切后台允许熄屏
- 更改 Android 应用包名为 host.msknet.sunsetripple
- 修复客户端主动离房误触发房主接管与异常结束提示

## 0.1.0-alpha.1 - 2026-08-14

- 支持免路由器 Wi-Fi Direct 多人全双工语音通话（最多 6 台设备）
- 支持蓝牙 RFCOMM 按住说话（PTT）与音频队列调度
- 支持成员短暂断线退避重试与身份恢复机制
- 支持房主主动离房自动转移与崩溃故障接管选举
- 支持音频焦点管理、前台通话保活服务与只听模式
- 提供「落日后残波」极简对讲交互与响应式动作盘
- 修复 Wi-Fi Direct 组主地址就绪超时处理与安全回退
- 修复音频采集播放异常中断后会话状态不同步问题
- 修复成员重连身份复用与离线席位超时释放机制
