> 🌐 [English](en/HarmonyOS-Platform-Guide.md) | 简体中文

# SunsetRipple HarmonyOS NEXT 平台适配指南

本文档描述 SunsetRipple 在 HarmonyOS NEXT 原生环境下的**当前实现**与**待补全工作**。

当前 `harmonyos/entry/src/main/ets/` 下实际存在：

| 路径 | 状态 | 说明 |
| --- | --- | --- |
| `audio/HarmonyAudioEngine.ets` | 已实现 | ArkTS 音频采集/渲染封装 |
| `model/Frame.ets` | 已实现 | 帧类型与 6 字节头编解码 |
| `session/HarmonyRoomSession.ets` | 已实现（脚手架） | 会话状态协调，网络发送为空 |
| `transport/LanRoomDiscovery.ets` | 已实现（仅扫描） | 对齐 Dart 发现协议的 `HarmonyLanScanner` |
| `plugin/PlatformAudioPlugin.ets` | **空文件（0 字节）** | 平台通道桥接缺失 |
| `pages/Index.ets` | 已实现 | 首页 ArkUI |
| `pages/RoomPage.ets` | 已实现 | 房间页/PTT ArkUI |
| `entryability/EntryAbility.ets` | 已实现 | UIAbility 入口 |

> ⚠️ 仓库中**不存在** `WifiP2pTransport.ets`。任何基于 Wi-Fi P2P 的示例都不属于当前实现。

**数据面现状：未接通。仅 UDP 发现可用。**

---

## 1. 音频引擎 `audio/HarmonyAudioEngine.ets`

`HarmonyAudioEngine` 封装 `@ohos.multimedia.audio` 的 `AudioCapturer` 与 `AudioRenderer`：

- 常量：`SAMPLE_RATE = 16000`、`FRAME_SAMPLES = 320`（20 ms）。
- 音频流：16000 Hz、单声道、`SAMPLE_FORMAT_S16LE`、`ENCODING_TYPE_RAW`。
- 采集器：`SOURCE_TYPE_VOICE_COMMUNICATION`；渲染器：`STREAM_USAGE_VOICE_COMMUNICATION`，由系统激活通话级 AEC/NS。
- 接口：`start()`、私有 `captureLoop()`（按 640 字节循环 `read`）、`playPcm(pcm: Int16Array)`（`renderer.write`）、`stop()`。
- 回调与状态：`onPcmFrame(pcm: Int16Array)`、`micMuted`。

即：Android/iOS 上的 16 kHz 单声道 16-bit、20 ms/320 samples/640 bytes 音频参数在鸿蒙侧一致。

---

## 2. 帧协议 `model/Frame.ets`

与 Android / iOS 保持 1:1 字节序一致：

- 6 字节大端头：`[type 1B][senderId 1B][seq 2B][payloadLen 2B]`，`payload ≤ 512`（`Frame.HEADER_SIZE = 6`、`Frame.MAX_PAYLOAD = 512`）。
- `Frame.encode()` / `Frame.decode()` 提供编解码。

`FrameType` 枚举（1..14）及其与跨端名称的对应：

| 值 | 枚举名 | 跨端名称 |
| --- | --- | --- |
| 1 | `AUDIO` | audio |
| 2 | `JOIN` | joinReq |
| 3 | `ROSTER` | roster |
| 4 | `PTT_STATE` | pttState |
| 5 | `PING` | heartbeat |
| 6 | `LEAVE` | leave |
| 7 | `HOST_TRANSFER` | hostHandover |
| 8 | `HOST_SNAPSHOT` | hostAnnounce |
| 9 | `HANDSHAKE_HELLO` | handshakeHello |
| 10 | `HANDSHAKE_CONFIRM` | handshakeConfirm |
| 11 | `SEALED` | sealed |
| 12 | `CHAT` | chat |
| 13 | `CHAT_SYNC` | chatSync |
| 14 | `CHAT_DELETE` | chatDelete |

---

## 3. 会话 `session/HarmonyRoomSession.ets`

`HarmonyRoomSession` 是会话**脚手架**：持有 `HarmonyAudioEngine`，提供 `start()` / `leave()`、`setPttPressed()`、`toggleMute()`、`members`、`isConnected`、`onStateChanged`。

**关键缺口**：`onLocalAudioCaptured(pcm)` 是空实现（仅注释“可在此打包 Frame 并通过 UDP 发送”），没有任何网络收发。也就是说，本地采集的 PCM 不会被打包或发送，远端音频也不会被播放。

---

## 4. 局域网发现 `transport/LanRoomDiscovery.ets`

只包含 `HarmonyLanScanner`（扫描器），与 Dart 侧 `LanRoomDiscovery` 的 JSON 发现协议对齐：

- `DISCOVERY_PORT = 8990`，`DISCOVERY_MAGIC = 'SUNSET_RIPPLE_DISCOVERY_V1'`。
- 广播载荷为 UTF-8 JSON：`{ magic, roomId, roomName, hostNickname, port, members, action?, timestamp }`。
- 房主 IP 取自数据报源地址（载荷不含 IP，防止伪造）。
- `ROOM_CLOSED` 即刻移除；`ROOM_EXPIRY_MS = 3500` 超时移除；房名上限 64 字符。
- 对外回调 `onRoomsUpdate(rooms)`。

**缺口**：只有扫描/监听，没有广播端（无法作为房主发布房间）。

---

## 5. UI 与 Ability

- `entryability/EntryAbility.ets`：加载 `pages/Index`。
- `pages/Index.ets`：昵称输入 + “创建房间 / 加入房间”，路由到 `pages/RoomPage`。
- `pages/RoomPage.ets`：PTT 大圆盘、静音/扬声器/离开按钮；绑定 `HarmonyRoomSession`。由于会话数据面为空，界面可交互但无实际语音收发。

---

## 6. 平台通道 `plugin/PlatformAudioPlugin.ets`

该文件**存在但为空（0 字节）**。这意味着鸿蒙侧尚无与 Android/iOS MethodChannel / EventChannel 等价的 ArkTS 桥接层，Flutter/SDK 无法通过它驱动 `HarmonyAudioEngine` 或 `HarmonyRoomSession`。

---

## 7. 已知缺口汇总

- `plugin/PlatformAudioPlugin.ets` 为空文件，平台通道桥接缺失。
- **数据面未接通**：`HarmonyRoomSession.onLocalAudioCaptured` 为空，无 TCP 8988 / UDP 8989 收发，无 BLE；目前只有 UDP 8990 发现可用。
- 发现层只有 `HarmonyLanScanner`，缺少房间广播端。
- 无 Opus 编解码。
- 不存在 `WifiP2pTransport.ets`。

---

## 8. 跨端协议与音频基线

- 6 字节大端帧头：`type(1) / senderId(1) / seq(2) / payloadLen(2)`，`payload ≤ 512`。
- 音频：16 kHz 单声道 16-bit PCM，20 ms = 320 samples = 640 bytes；目标码率 Wi-Fi 24 kbps、蓝牙 16 kbps。
- Wi-Fi：TCP 8988 + UDP 8989 + 发现 UDP 8990，音频经房主中继。
- 蓝牙：BLE L2CAP CoC，动态 PSM 经 BLE 厂商数据广播；不做房主转发。
