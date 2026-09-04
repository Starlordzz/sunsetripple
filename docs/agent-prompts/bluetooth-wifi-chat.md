# SunsetRipple 蓝牙 / WiFi 房文字聊天室实施提示词

> 用法：把本文件全文交给负责实现的 agent。它是一份实施合同，不是泛泛的功能建议。agent 必须先读当前源码，再按阶段实现、测试、记录平台缺口；源码优先于旧 Wiki 或旧计划。

## 角色与目标

你正在 `D:\LEARNING\vibeproject\SunsetRipple` 的 `bluetooth-wifi-chat` 分支上工作。当前基线是 `master` 的 `c26ae93`。目标是在现有 Flutter/Dart 房间核心中增加一个**仅限当前房间、仅内存、文本消息**功能，并让 WiFi 房与蓝牙 PTT 房共享同一套聊天会话与界面。

完成后的用户流程：

1. 用户在 WiFi 房或蓝牙房内点击聊天入口；
2. 打开聊天面板，看到本次房间生命周期内的消息；
3. 输入 UTF-8 文本并发送；
4. 本机立即看到自己的消息，其他在线成员收到一次；
5. 退出、断线结束或重新进房后，历史消息不恢复；
6. WiFi 聊天走可靠 TCP 控制面，蓝牙聊天走现有 L2CAP 帧面；聊天不能进入 WiFi UDP 音频端口。

这次实现不改变语音拓扑、不增加服务器、不增加账号、不把聊天持久化到磁盘、不做图片/文件/回复/编辑/撤回/已读回执/搜索/跨房间消息。

## 开始前的硬性动作

1. 确认当前分支是 `bluetooth-wifi-chat`，确认工作树状态；不要执行 `reset --hard`、`checkout --`、删除用户已有改动等破坏性操作。
2. 亲自阅读并以源码为准：
   - `lib/core/protocol/frame_type.dart`
   - `lib/core/protocol/frame.dart`
   - `lib/core/protocol/payloads/*.dart`
   - `lib/core/transport/room_transport.dart`
   - `lib/core/transport/lan_transport.dart`
   - `lib/core/transport/ble_l2cap_transport.dart`
   - `lib/core/session/room_session.dart`
   - `lib/core/session/member.dart`
   - `lib/ui/pages/room_page.dart`
   - `lib/ui/pages/session_stage.dart`
   - `lib/l10n/app_strings.dart`
   - `test/protocol_test.dart`
   - `test/room_session_test.dart`
   - `test/room_layout_test.dart`
3. 再读 `docs/wiki/架构总览.md`、`docs/wiki/协议规范.md`、`docs/wiki/房间模式对比.md`、`CHANGELOG.md`，但若文档和源码冲突，以源码为准，并在交接报告中指出冲突。
4. 先运行窄验证：`flutter test test/protocol_test.dart test/room_session_test.dart test/room_layout_test.dart`。若基线失败，记录失败而不是把它伪装成聊天回归。

## 已确认的源码事实

- `Frame` 使用 6 字节头：类型 1 字节、senderId 1 字节、seq 2 字节大端、payload 长度 2 字节大端；Dart `Frame.maxPayloadSize` 是 512 字节，超长构造会截断，所以业务层必须在构造 `Frame` 前拒绝超长文本（见 `lib/core/protocol/frame.dart:5-44`）。
- 当前 `FrameType` 只有 `audio` 到 `sealed` 的 0x01..0x0b，没有聊天类型（`lib/core/protocol/frame_type.dart:1-23`）。新增类型只能使用未占用的 `0x0c`，不得改动既有数值。
- `RoomTransport.send(Frame)` 对上层透明；`RoomSession` 通过 `onSendFrame` 接线（`lib/core/transport/room_transport.dart:10-47`、`lib/core/session/room_session.dart:684-700`）。
- `LanTransport.send` 只把 `FrameType.audio` 送到 UDP，其余帧走 TCP；房主 TCP 控制帧会转发给其他客户端（`lib/core/transport/lan_transport.dart:355-402`）。聊天必须是非 audio 类型，因而自动走 TCP。
- Dart BLE 传输把所有 `Frame` 编码后送到 `sendL2capData`（`lib/core/transport/ble_l2cap_transport.dart:224-241`）；Android 原生 BLE 主机收到完整帧后会转发给除来源外的成员。不要为了聊天另造一条信道。
- `RoomSession.handleIncomingFrame` 目前是穷举 switch（`lib/core/session/room_session.dart:172-217`），新增枚举后必须新增明确的 `chat` 分支；不要把聊天帧当作音频交给 `audioIo`。
- 房主创建后当前成员号是 1，客户端在收到 roster 前是 0；成员表以 `memberId` 为身份，昵称不能作为聊天主键（`room_session.dart:108-158,300-317`）。
- 当前 UI 只有 `stateStream`、`membersStream`、`waveStream`，没有 `RoomUiState` 和聊天状态。`RoomContent` 是未滚动 Column，直接塞一个常驻聊天列表会破坏 360x640 布局（`lib/ui/pages/room_page.dart:48-119`）。聊天应优先做成按入口打开的 `showModalBottomSheet`/独立面板，而不是永久挤占中央对讲盘。
- 字符串是手写 typed 双语 `AppStrings`，不是 ARB（`lib/l10n/app_strings.dart`）。所有聊天 UI、错误、空状态、无障碍标签都必须加中英文 getter，并补 `test/i18n_test.dart`。
- `RoomSession.secureCodec` 当前默认为 null，生产代码没有完成握手协商；只有显式注入 codec 时 `sendFrame` 才会密封控制帧（`room_session.dart:34-42,687-700`）。本任务不能假装已经启用端到端加密，也不能绕过 `sendFrame` 自创另一套加密。
- Android BLE 原生读取器的上限是 1024，而共享 Dart 帧上限是 512；iOS BLE 当前存在流分片重组和主机转发缺口；HarmonyOS 当前只有发现代码，没有可用房间数据传输。没有相应真机证据时不得在 README/CHANGELOG 中宣称“全平台聊天室已完成”。

## 统一协议合同

### 帧类型

新增：`FrameType.chat(0x0c)`。既有帧数值保持不变；同步更新注释、协议文档和所有穷举 switch。未知类型仍由 `Frame.decode` 丢弃。

### Chat payload

新建 `lib/core/protocol/payloads/chat_message.dart`，不要把 JSON 放进协议。推荐且应保持稳定的二进制格式：

```text
[version 1B = 0x01][textLength 2B BE][text UTF-8 bytes]
```

合同如下：

- `textLength` 必须等于剩余字节数；拒绝多余尾字节、长度不足、版本不为 1、非法 UTF-8。
- 文本不能是空字符串；业务上限为 **480 UTF-8 字节**，不是 Dart 字符数。这样 payload 最大 483 字节，仍低于 Frame 的 512 字节硬上限，并为以后扩展保留空间。
- `encode` 在超长、空文本或无法编码时抛 `ArgumentError`；不得依赖 `Frame` 的静默截断。
- `decode` 返回 nullable 或明确的失败结果，风格要和现有 payload codec 一致；接收失败只丢弃该聊天帧并记录脱敏日志，不得让整个房间崩溃。
- 不在 payload 中传时间戳。消息身份使用外层 `(senderId, seq)`；时间戳只在本机收到/本地发送时生成。

### 会话消息模型

新建 `lib/core/session/chat_message.dart`（或在 session 中放置等价不可变模型），至少包含：

```text
senderId       int
senderNickname String  // 收到时从当前 roster 快照复制，成员离开后历史仍可显示
seq            int
text           String
timestamp      DateTime // 本地时间，不上 wire
isLocal        bool
```

模型应不可变，`==`/`hashCode` 便于测试。不要以昵称查找或合并消息。

### RoomSession API 与状态

在 `RoomSession` 增加：

- `Stream<ChatMessage> get chatStream`：每条新消息只发一次；
- `List<ChatMessage> get chatMessages`：返回不可变快照或防御性拷贝；
- `Stream<int> get unreadChatStream` 与 `int get unreadChatCount`；
- `void markChatRead()`：把当前未读数归零；
- `Future<void> sendChat(String text)`：先按 payload 合同校验，再用当前 `_selfMemberId` 和 `_nextSeq()` 生成 `FrameType.chat`，唯一发送路径是 `sendFrame(frame)`。

建议历史上限为 100 条。超过上限时从最旧端删除；未读数不能因为历史裁剪变成负数。`leave()` 和 `dispose()` 必须取消/清空聊天流、历史、未读和去重集合；不能向已关闭 controller 写入。

发送语义：

1. `sendChat` 只能在本机会话有效时发送；无效输入抛 `ArgumentError`，UI 捕获后显示双语错误；
2. 先构造完整 payload，再构造 Frame，避免任何截断；
3. 通过 `sendFrame` 发送，不能直接调用 `onSendFrame` 或 transport；
4. 本机在成功提交发送路径后立即追加一条 `isLocal=true` 的消息，保证 WiFi/BLE 都能看到自己的消息；不要等待对端回显，也不要因为接收到自己的回送再追加一次；
5. `sendFrame` 是异步且当前 callback 不等待传输结果。不要在聊天层声称“服务器已送达”；必要时只显示本地发送状态，不设计伪造的送达回执。

接收语义：

1. 在 `handleIncomingFrame` 的 `chat` 分支解码 payload；
2. `frame.senderId` 必须存在于当前 `_members`，未知 sender 直接丢弃；
3. `frame.senderId == _selfMemberId` 直接丢弃，避免房主/客户端转发造成重复本地消息；
4. 以 `(senderId, seq)` 做有界去重。至少保留最近 512 个 key，重复帧不再次发 stream、不增加未读；
5. 不凭 seq 推断墙上时间，不做跨 16 位回绕的错误排序假设。WiFi TCP 与 Android BLE 当前保持传输顺序，UI 按到达顺序显示；
6. 复制当前成员昵称到 `senderNickname`，之后成员离开不影响历史；
7. 只有非本地入站消息增加未读数；在 stream controller 已关闭或 session 已 leave 时安全忽略。

## 分工与并行交付

如果使用多个 agent，按以下 ownership 分开，避免同时编辑同一文件：

### Agent A：协议与纯模型（P0）

负责：

- `lib/core/protocol/frame_type.dart`
- `lib/core/protocol/payloads/chat_message.dart`
- `lib/core/session/chat_message.dart`
- `test/protocol_test.dart` 及新增纯模型测试文件

要求：先写红灯测试，再实现；覆盖中文、emoji、ASCII、空文本、480 字节边界、481 字节拒绝、非法 UTF-8、错误版本、错误长度、Frame chat round-trip。完成标准是该 agent 的窄测试全绿，并提供每个协议字段的测试名称。

### Agent B：RoomSession 会话（P0）

负责：

- `lib/core/session/room_session.dart`
- `test/room_session_test.dart` 中聊天相关测试

要求：复用现有 `MockAudioIo` 和 `onSendFrame = sent.add` 习惯；不要重构无关的音频、房主转移或重连代码。测试 host/client 两种模式、发送 sender/seq/type、合法成员接收、未知 sender/self/非法 payload/重复 key 丢弃、history 上限、unread/read、leave/dispose 清理。若需要 fake transport，单独放在测试辅助文件，不修改生产 `RoomTransport` 契约。

### Agent C：WiFi/BLE 传输核验（P0/P1）

负责：

- 优先新增 Dart 层传输回归测试或测试辅助；只有发现必要缺陷才修改 `lib/core/transport/lan_transport.dart`、`lib/core/transport/ble_l2cap_transport.dart`；
- 如承担 iOS/Android 原生修复，明确 ownership 到具体文件。

必须证明：

- WiFi `chat` 被视为非 audio，走 TCP 控制连接；不进入 UDP 8989；房主转发给其他客户端且本地交付一次；
- BLE Dart 发送的是完整 `Frame.encode()`；Android 现有主机广播路径能转发 chat；
- iOS 若仍无分片重组/主机转发，必须写成阻塞项和复现步骤，不能通过修改 README 掩盖；
- 不把聊天帧改成 UDP，不新增另一套 framing。

### Agent D：Flutter 聊天 UI（P0）

负责：

- `lib/ui/pages/room_page.dart` 只做必要接线；
- 新建 `lib/ui/widgets/room_chat_sheet.dart`（或等价独立组件）；
- `lib/ui/pages/session_stage.dart` 只增加聊天入口/未读 badge；
- `lib/l10n/app_strings.dart` 与 `test/i18n_test.dart`。

建议交互：

- 房间头部右侧增加聊天 icon + 未读数量 badge，使用现有 `tooltip` 习惯；
- 点击打开 `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)`，面板内是 `ListView`、文本输入框、发送 icon button；
- 打开面板立即 `markChatRead()`；发送成功后清空输入并保持键盘/滚动体验；新消息到来时仅当用户接近列表底部才自动滚动；
- 不在 `RoomContent` 原有 Column 中永久放聊天列表，不能牺牲中央 WiFi 音浪盘或 BLE PTT 盘；
- 每个输入框有语义 label，不只依赖 placeholder；发送、打开聊天、关闭面板等 icon 有 tooltip/contentDescription；
- 消息行同时显示稳定昵称/短码语义和文本；长文本软换行，禁止 `maxLines: 1` 截断正文；未知历史 sender 显示“已离开成员/Former member”一类双语回退；
- 360x640、411x892、430x932，浅色/深色，WiFi/BLE 两种模式均不能 overflow。键盘打开后面板仍可滚动，发送按钮不能被遮挡。

### Agent E：安全与文档边界（P1）

负责：

- 检查聊天是否始终经过 `RoomSession.sendFrame`；
- 在已有 `secureCodec` 注入时补一个 focused test，证明 chat 会被封装为 `sealed`；
- 不在本任务内重写 SessionHandshake，也不把 `secureCodec == null` 改成未经兼容验证的强制默认；
- 更新 `docs/wiki/协议规范.md`、`docs/wiki/架构总览.md`，必要时在 `CHANGELOG.md` 记录“内存聊天已实现”和已知平台限制。

文档必须明确：当前生产握手尚未接线时，聊天与其他控制帧一样沿现有明文兼容路径；只有显式配置安全 codec 才会密封。不要写“聊天端到端加密已完成”这种不符合源码的结论。

## UI 具体验收合同

- 房间头部聊天入口不影响离开和诊断按钮的点击区域；转场 `stage < 1.0` 时入口仍遵守现有 `IgnorePointer` 行为。
- 未读 badge 只显示正数；打开面板后归零；离开房间后归零。
- 空历史有中英文空状态；没有消息时发送按钮可见但不能发送空白字符串。
- 文本输入按 UTF-8 字节校验，不能只按 `String.length`。错误信息指出“消息过长/Message is too long”，不打印用户全文到日志。
- 自己发送的消息和远端消息有稳定的视觉区分，但不使用大卡片套小卡片；布局需符合现有落日/月夜主题。
- 文本、按钮和输入在系统字体 1.3x、1.5x 下不重叠、不溢出；英文长文案也不截断关键命令。

## 测试矩阵

### 协议

- FrameType.chat 数值为 0x0c，既有值不变；
- Chat payload round-trip：ASCII、中文、emoji；
- 空文本、空白文本策略明确并测试；
- 480 UTF-8 字节通过，481 拒绝；多字节字符不能被半截编码；
- 非法版本、长度不一致、尾字节、非法 UTF-8 拒绝；
- 完整 Frame encode/decode round-trip，payload 长度不超过 512。

### 会话

- host 与 bluetoothPtt client 的 `sendChat` 都发送 `FrameType.chat`；senderId 是当前 self id，seq 使用现有 16 位 `_nextSeq()`；
- 本地消息只出现一次；合法 roster 成员的入站消息只出现一次；
- self、未知 sender、非法 payload、重复 `(senderId, seq)` 都不进入 stream/history；
- 100 条 history 上限、unread 增加/`markChatRead`、leave/dispose 清理；
- `secureCodec` 非空时 sendChat 经 `sealed`，为空时保留现有兼容行为并在文档中说明。

### 传输

- WiFi chat 走 TCP 控制路径，不走 UDP；host 本地收到一次并转发给其他成员；
- BLE chat 经过现有 L2CAP `sendL2capData`；Android host 转发时排除来源；
- 如果无法在当前测试环境模拟原生链路，至少用 fake/MethodChannel 证明 Dart 发出的 bytes 是合法完整 chat frame，并把真机待办写入报告；
- iOS 分片重组、iOS 多成员 host relay、Harmony 数据传输不得被“测试未覆盖”误标成通过。

### Widget / i18n

- 聊天入口和 sheet 在 360x640、411x892、430x932 不溢出；WiFi/BLE、日/夜均测；
- 打开、输入、发送、清空、关闭、未读 badge 行为有 widget test；
- 中英文 getter 集合和现有 `i18n_test.dart` 断言同步；
- TalkBack/语义树至少检查聊天入口、输入框、发送按钮的 label。

## 日志、隐私与错误处理

- 聊天正文是用户数据；默认不写 `AppLog`，错误日志只记录类型、字节长度、senderId 是否在册等脱敏信息；
- 诊断报告不得包含聊天正文、昵称原文、完整设备地址、密钥或 payload 原文。若诊断模块收集帧统计，只收计数/长度/错误码；
- 单个坏聊天帧只丢弃该帧，不断开整个 WiFi/BLE 房间，不影响音频和其他控制帧；
- 发送失败必须有可测试的本地错误路径，但不要伪造远端送达；
- 离房和 `dispose` 幂等，不能出现 `StateError: Cannot add new events after calling close`。

## 验证命令

先运行快速命令：

```bash
flutter pub get
flutter test test/protocol_test.dart test/room_session_test.dart test/room_layout_test.dart test/i18n_test.dart
flutter analyze
flutter test
```

若改了 Android 原生或需要 APK 构建，在 Windows 上使用项目已验证的环境：

```bash
export JAVA_HOME='D:/LEARNING/tools/jdk-17'
export GRADLE_USER_HOME="$PWD/.gradle-local"
flutter build apk --debug
```

失败分类要清楚：依赖下载、Gradle 权限/锁、原生 SDK 缺失属于环境问题；Dart 编译、测试断言、帧解析、UI overflow 属于目标失败。不要用环境失败替代功能通过。

## 提交与交接

每个 agent 只提交自己 ownership 内的可审查变更，推荐顺序：

1. `test: lock chat payload contract`
2. `feat: add chat frame and session history`
3. `test: cover wifi and bluetooth chat routing`
4. `feat: add room chat sheet and unread badge`
5. `docs: document bluetooth wifi chat limits`

提交前检查：

- `git diff --check`；
- `git status --short` 中没有 keystore、APK、缓存、截图、hprof 或 `.gradle-local`；
- 没有无关重排、批量改名、旧功能行为变化；
- 所有新文件在 `git status` 可见；
- 测试输出和未解决平台缺口已记录。

交接报告必须包含：

```text
分支与基线：
完成的文件与符号：
协议字段与上限：
WiFi 路由证据：
BLE 路由证据：
安全 codec 行为（已配置 / 默认未配置）：
测试命令与结果：
真机未验收项：
已知阻塞（尤其 iOS BLE / Harmony）：
下一 agent 的唯一下一步：
```

最终完成定义不是“页面出现输入框”，而是：协议可严格编解码、RoomSession 对两种房型都能发送/接收/去重/清理、WiFi 不进 UDP、BLE 沿现有 L2CAP、UI 在最小屏幕和双语下不溢出、日志不泄露正文、测试和平台限制均有证据。
