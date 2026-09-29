# Changelog

## 0.1.0-alpha.15 - 2026-09-27

### 修复：房主转移在名单广播后静默失效

- `RoomSession._handleRoster` 每次重建成员对象时只继承了 `sessionToken`，
  把 **`endpoint` 与 `joinOrder` 抹成空值/0**。后果是一条静默的失效链：
  `_buildTransferPlan` 因端点为空跳过所有候选 → 候选表为空 → 返回 null →
  **手动转让房主与房主故障自愈同时失效**。症状是「房主刚广播过名单，之后就
  再也转让不了房主了」，且全程无任何报错。现已从上一份名单继承这两个字段
- **`attachTransport` 会静默切断发送链路**：它把 `onSendFrame` 覆写成
  `transport.send`，任何在其之前赋值的观测钩子会被悄悄丢掉，表现为
  「帧一条都发不出去且没有报错」。新增 `addSendObserver` / `setSendInterceptor`，
  注册的钩子会在传输层更换时被重新串进链路，不再依赖赋值顺序

### 架构：拆解上帝对象

- **`RoomSession` 1565 → 1511 行**，外提三个纯逻辑协作对象
  （`SessionChatHub` 193 行 + `SessionTelemetry` 87 行 + `HostFailoverTracker` 154 行）：
  - `SessionChatHub`：聊天历史表、`(senderId,seq)` 去重窗口、撤回、历史同步、
    跨进退房同人识别。会话层只保留**鉴权**（发送者是否在册、是否房主）与**发帧**
  - `SessionTelemetry`：帧计数、丢包估算（uint16 序号的正确回绕处理）、
    入房往返时延。纯计算，可直接单测
  - `HostFailoverTracker`：房主失联判定、交接计划防重放（joinOrder 水位）、
    迁移互斥。`evaluate()` 要求调用方注入 `now`——原先直接读 `DateTime.now()`，
    导致「失联 6 秒后接管」这条规则只能靠**真的等 6 秒**验证，实测覆盖率长期为 0
  - 聚合魔法数：房主失联阈值 6000ms → 具名常量 `hostTimeout`，并写明它为何
    比成员超时（10 秒）短——房主是星型单点，等 10 秒会让用户先经历一段
    「还在房里但谁也听不见」的空白期
  - 判定结果从「四种情况共用 `return`」改为 sealed class，新增
    `FailoverIdleReason` 以区分「房主还活着」与「名单里还没房主」——
    原先两者无法区分，排障只能靠猜
- **`home_page.dart` 1017 → 916 行**，建房/入房编排外提到
  `lib/ui/services/room_launcher.dart`。四条启动路径（WiFi 建房、蓝牙建房、
  局域网入房、Wi-Fi Direct 直连）原本各自夹在 1000 行 Widget 里按顺序装配
  2~3 个对象、失败时逆序拆解，极易漏掉一次 `dispose()` 而泄漏 socket 与端口；
  现在失败回滚收敛到一处，且不碰 `BuildContext`
- 新增 `docs/platform-support.md` 作为**平台能力权威声明**：明确
  Windows/macOS/Linux 因缺少桌面音频后端而**不支持**（可编译出窗口但无声音）、
  iOS 搜房未接入 Bonjour 因而不可用、鸿蒙仅有 UDP 发现。README 平台表与之对齐

### 安全：安全层从死代码变成可达路径

- **新增 `SecureSessionNegotiator`**：在既有 `SessionHandshake` 之上补齐
  「谁在什么时候驱动握手、成功后把 codec 装到哪」这段缺失的编排。
  此前 `lib/core/security/` 实现齐全却**零生产调用**——`RoomSession` 对
  `handshakeHello` 直接 `break`，`secureCodec` 永远为 null
- `RoomSession` 现在处理握手帧并在入房后自动发起；握手成功即装上 `secureCodec`，
  业务帧自动密封。**握手失败保持明文并在诊断面板留痕，不静默假装加密**
- 新增**带外安全短码**（6 位十进制，取自双方公钥的排序拼接哈希），
  供用户口头比对以抵御主动中间人。安全边界已在代码注释与文档中如实标注：
  签名校验只证明「对端持有其自称公钥的私钥」，不比对短码前不声称防 MITM
- 明文默认仍为明文（产品取舍未变），但现在**有了一条真正可用的加密路径**，
  而不是一层对外宣称存在、实际不可达的代码

### 更新链路：从"只比较版本号"到真正可安装

- 新增 `update_manifest.dart`：拉取 `update.json`，**ECDSA-P256 验签**
  （签对象为规范化 JSON），校验包名、`minimumVersionCode`、SHA-256
- 新增 `update_installer.dart`：HTTPS + 域名白名单（github.com 系）、
  流式下载、**边下边算 SHA-256**、响应体大小上限、整体超时；
  摘要不符即删除临时文件并报错
- 新增 Android `UpdateInstallerPlugin`：`REQUEST_INSTALL_PACKAGES` 权限检查、
  跳系统「安装未知应用」设置页、FileProvider + `ACTION_VIEW` 拉起安装器，
  安装前**原生侧二次核对**包名 / versionCode / 签名证书 SHA-256
- iOS 明确回 `unsupported`（沙箱不允许自装），只提供「打开下载页」
- `release.yml` 构建后生成并签名 `update.json` 作为 release 资产；
  并比对 Dart 内置公钥常量与 `UPDATE_PUBLIC_KEY_BASE64` secret 是否一致，
  不一致直接让发布失败

### 可观测性

- 新增 `TraceId`：会话级 8 字节随机 hex，入房生成、退房释放；
  `AppLog` 输出格式变为 `[HH:mm:ss][LEVEL][traceId][tag] message`，
  用户导出的诊断报告可据此挑出一次完整会话的日志
- 新增 `SessionMetrics` + `NetworkQuality` 分级（loss/RTT 双阈值，边界可测），
  `DiagnosticsSheet` 从「只有一个延迟值」扩展为完整指标区
- 传输层补齐 9 处关键路径日志（白名单拦截、来源不符、成员移除、重连结果、
  链路关闭），这些此前是**裸 return**，事故现场完全没有痕迹

### 测试

- 新增 **JUnit 原生单测 21 条**（`android/app/src/test`）：`JitterBuffer` 14 条
  （预缓冲、乱序、丢包报 `Lost` 而非 `NotReady`、16 位序号回绕、积压上限、
  迟到帧、断流重对齐）、`OpusCodec` 7 条（编解码往返、PLC、码率边界、实例隔离）。
  **原生音频层此前零覆盖**，而它决定断音/回声等全部音质问题
- 新增 `ReconnectController` 测试 8 条：退避序列、耗尽后放弃回调只触发一次、
  `cancel()` 后定时器彻底静默、在途尝试结果被丢弃、重复 `start()` 不叠加链路。
  断线重连此前**完全没有测试**
- 新增 `SecureSessionNegotiator` 测试 10 条：双方派生出**同一个短码**、
  派生的 codec 能双向加解密且密文不含明文、幂等、畸形/空字段 Hello 不崩溃、
  `roomId` 不一致必然验签失败
- 新增 `update_manifest_test.dart` 41 条 + 下载校验路径 8 条冒烟
- 新增 `i18n_parity_test.dart` 5 条：**机械阻止**「裸中文字面量绕过 AppStrings」
  这类回归，并校验全部 getter 在中英文下都非空
- 新增 `host_failover_test.dart` 14 条：房主活跃时不迁移、无快照时体面解散、
  按快照迁移、继任者是自己时接管、`becomeHost`/`reconnectToHost` 失败进入
  disconnected、不支持转移的传输层保持原位、陈旧计划防重放、非房主发的交接帧
  被忽略、手动转让的端点已知/未知两条路径、发送链路的观察者存活与改写层拦截
- 新增 `host_succession_test.dart` 7 条：接任者占 #1 且用本地身份覆盖计划自述、
  继任者不重复出现、其余成员保留端点与 token、计划含冲突成员号 1 时被忽略、
  `nextJoinOrder` 接在最大值之后
- 新增 `host_failover_tracker_test.dart` 14 条：失联阈值两侧边界（差 1ms 算存活、
  恰好等于算失联）、房主未知/存活两条 idle 原因、无快照必解散、防重放水位、
  joinOrder 相同视为幂等重播、迁移互斥、`reset` 清跨会话水位
- CI 增加 `:app:testDebugUnitTest` 步骤与报告上传

### 修整

- UI 层 6 处硬编码中英文提示（建房/入房失败、断线）归位 `AppStrings`；
  删除 `about_page` 的私有 `_bilingual` 与 `diagnostics_sheet` 的临时扩展
- 删除 `gradle-wrapper.properties` 里重复的 `distributionUrl`（8.9 / 8.12 两行，
  后者生效）
- 新增 `docs/platform-support.md` 作为**平台能力权威声明**：明确
  Windows/macOS/Linux 因缺少桌面音频后端而**不支持**（可编译出窗口但无声音），
  iOS 搜房未接入 Bonjour 因而不可用，鸿蒙仅有 UDP 发现。
  README 平台表与此对齐

### 架构：RoomSession 再拆解，启动回滚收敛到一处（YOU-7）

- **`RoomSession` 1511 → 1183 行**，再外提四个协作对象，全部时钟可注入、可单独单测：
  - `SessionChatService`：聊天族帧（chat / chatSync / chatDelete）的解码、**鉴权**与发帧。
    `SessionChatHub` 只管本地状态与去重，「谁有资格发」这层原先在会话里占掉近 250 行
  - `PresenceTracker`：说话指示灯 400ms 超时熄灭、心跳 10 秒超时清理、音频时间戳簿记。
    这两条**时间规则**此前只能靠真等 400ms / 10 秒验证，现在是假时钟下的边界断言
    （恰好 400ms 不熄、401ms 熄）
  - `SendPipeline`：发送出口 / 观察者 / 改写层的串联与 16 位序号计数器。
    「`attachTransport` 覆写 `onSendFrame` 就把观测钩子丢掉」这个坑从此只有一处实现，
    观察者在换传输层后必定被重新串上
  - `buildTransferPlanFromRoster`：交接计划的纯组装（端点未知的人不能当继任者、
    缺有效令牌则整份计划作废），从 `_buildTransferPlan` 外提到 `host_transfer.dart`
  - `session_token.dart` 收编令牌生成与逐字节比较（原先散在会话里的两个静态私有方法）
- 新增 `lib/core/clock.dart`（`Clock` / `SystemClock` / `FakeClock`），并为
  `RoomSession`、`SessionTelemetry`、`LanRoomDiscovery`、`BleL2capTransport` 接上注入时钟
- **建房/入房的失败回滚**（`lib/ui/services/room_launcher.dart`）：四条启动路径原先只在
  「start/connect 返回 false」时回滚，**装配中途抛异常**（`attachTransport` /
  `createRoom` / `joinRoom` / `startAdvertising`）会把已经开好的监听端口、广播定时器
  留在原地，只能等下一个人建房时冲突。现在资源一拿到就进回滚栈，失败时逆序释放，
  并且传输层出口与发现器都改成可注入的工厂，测试里不再需要真 socket
- 新增 `test/room_launcher_rollback_test.dart`：逐路径枚举「第 N 步装配失败 →
  已占用的 socket/端口全部释放」，并有一条全流程成功的正例

### 工程门禁：时间相关规则必须注入时钟（YOU-8）

- 新增 `scripts/check-clock-injection.sh`：`lib/core/` 下出现未豁免的
  `DateTime.now()` 即失败（只认代码，注释里提到不算），已接入
  `.github/workflows/flutter-ci.yml` 的 test 作业（`flutter analyze` 之后）
- 豁免必须写在调用点**同一行**（`// clock-exempt: <理由>`），当前只有三处，且都是
  默认值而非规则：日志缺省时间戳（`app_log.dart`）、线协议缺省时间戳
  （`chat_message.dart`）、成员模型缺省值（`member.dart`）
- 存量 17 处直接读系统时间全部改为注入时钟（会话 10、遥测 2、蓝牙扫描 2、局域网发现 3）；
  系统时钟本身只允许出现在 `lib/core/clock.dart`

### CI：修掉长期红的 flutter 作业（卡在「装依赖」）

- 症状：9/17 起 `flutter-ci` 的 test 作业每次都在 **Install dependencies** 失败
  （exit 65），`analyze` / `format` / 测试 / 覆盖率 / 时钟门禁一步都跑不到
- 根因一：`pubspec.lock` 里 62 个包的来源都记着生成时的镜像
  `https://pub.flutter-io.cn`（本机 `PUB_HOSTED_URL`），CI 没有这个变量，按
  `https://pub.dev` 解析 → **62 个包全部对不上** → `--enforce-lockfile` 拒绝
- 根因二：锁里 `glob` / `io` / `mime` / `pool` / `pub_semver` / `yaml` 六个包比当前
  可解析上限旧，CI 的**全新解析**（空 pub 缓存 + 干净检出）会升级它们，同样对不上锁
- 改法：两个 workflow 都显式声明 `PUB_HOSTED_URL` 与生成锁的环境一致；锁升到这六个包的
  上限；Flutter 钉到 `3.29.0`（补丁号变化会让 SDK 自带依赖的钉版漂移）；并在装依赖前加
  一步「包源 host 必须与锁一致」的门禁，把原来那句看不懂的「Would change 62
  dependencies」变成指名道姓的报错

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
