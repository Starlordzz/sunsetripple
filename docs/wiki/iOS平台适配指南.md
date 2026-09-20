> 🌐 [English](en/iOS-Platform-Guide.md) | 简体中文

# SunsetRipple iOS 平台适配指南

本文档描述 SunsetRipple 在 iOS 端的**当前实现**与**待补全工作**。iOS 侧目前只有两个原生插件，均由 `ios/Runner/AppDelegate.swift` 注册：

- `ios/Runner/PlatformAudioPlugin.swift` —— 基于 `AudioUnit` 的 `kAudioUnitSubType_VoiceProcessingIO` 音频采集/播放插件。
- `ios/Runner/BleL2capPlugin.swift` —— 基于 BLE L2CAP CoC 的近场数据插件。

> ⚠️ 仓库中**不存在** `VoiceProcessingAudioEngine.swift`，也**未使用** `MultipeerConnectivity` / `MultipeerTransport`。任何基于这两者的示例都不属于当前实现。

iOS 数据面现状：局域网 TCP 文本/控制消息可用；UDP 音频数据面与 BLE 数据面尚未完全打通。

---

## 1. 音频插件 `PlatformAudioPlugin.swift`

### 1.1 通道

| 类型 | 名称 | 方向 |
| --- | --- | --- |
| MethodChannel | `host.msknet.sunsetripple/audio` | Dart → iOS |
| EventChannel | `host.msknet.sunsetripple/audio_events` | iOS → Dart |

事件负载为 `{ "data": Uint8List(PCM), "level": double }`，`level` 是该帧 RMS 按满量程 32768 归一化后的 `0.0 ~ 1.0` 音量。

### 1.2 音频参数

- 采样率 16000 Hz，单声道，16-bit 线性 PCM。
- 帧长 320 samples = 20 ms = 640 bytes（`PlatformAudioPlugin.frameSamples` / `bytesPerFrame`）。
- 使用 `kAudioUnitSubType_VoiceProcessingIO`，自动启用系统级回声消除（AEC）与环境降噪（NS）。
- 音频会话类别为 `.playAndRecord`、模式 `.voiceChat`，并设置 `setPreferredIOBufferDuration(0.02)`。

### 1.3 Method 方法

| 方法 | 参数 | 行为 |
| --- | --- | --- |
| `startCapture` | `{ bitrate?: Int }` | 检查麦克风权限后启动 AudioUnit；默认 `bitrate = 24000` |
| `stopCapture` | — | 停止并销毁 AudioUnit，清空远端队列 |
| `setMuted` | `{ muted: Bool }` | 设置本地静音标志 |
| `setSpeakerphone` | `{ enabled: Bool }` | 切换扬声器/听筒输出路由 |
| `setUseBuiltinMic` | `{ useBuiltinMic: Bool }` | 优先使用内置麦克风或耳机/蓝牙输入 |
| `setBitrate` | `{ bitrate: Int }` | 仅记录 `currentBitrate` |
| `submitRemoteFrame` | `{ data: Uint8List }` | 送入远端帧数据 |
| `removeRemoteMember` | `{ memberId: Int }` | 移除该成员的播放队列 |
| `clearRemoteMembers` | — | 清空全部远端队列 |
| `stopPlayback` | — | 同 `stopCapture` |
| `dispose` | — | 解除通道并停止引擎 |

### 1.4 上行音频流

`audioInputCallback` 通过 `AudioUnitRender` 拉取 PCM → `processCapturedPcm` 计算 RMS/level，并仅在 `isCapturing && !isMuted` 时经 EventChannel 上送 `{ data, level }`。

### 1.5 下行播放与混音

`submitRemoteFrame` 将整帧交给 `handleRemoteFrameData`：

1. 解析 6 字节大端头 `[type 1B][senderId 1B][seq 2B][payloadLen 2B]`。
2. 按 `senderId` 将负载作为**原始 PCM** 拷贝为 `Int16` 样本（最多 640 字节），写入该成员队列。
3. 每个成员队列最多保留 10 帧。
4. `providePlaybackPcm` 将所有成员队列逐样本相加并做饱和截断（clipping）后输出。

### 1.6 已知缺口

- **无 Opus 编解码**：全链路为原始 PCM。`PlatformAudioPlugin.swift:290` 的注释已注明“若集成 Opus，此处应送入 Opus 解码器”，当前实现直接按原始 PCM 拷贝。
- **单帧负载上限 640 字节**：`payload` 超过 `bytesPerFrame` 的部分被截断。
- `currentBitrate`（默认 24000）只在方法中记录，未参与任何实际编码。

---

## 2. 近场 BLE 插件 `BleL2capPlugin.swift`

### 2.1 通道

| 类型 | 名称 | 负载 |
| --- | --- | --- |
| MethodChannel | `host.msknet.sunsetripple/ble_l2cap` | — |
| EventChannel | `host.msknet.sunsetripple/ble_l2cap_data` | `{ data, peerAddress }` |
| EventChannel | `host.msknet.sunsetripple/ble_l2cap_scan` | `{ name, address, rssi, psm, memberCount }` |

服务 UUID 为 `7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004`，厂商 ID `0xFFFF`。

### 2.2 房主（Peripheral）

- 通过 `publishL2CAPChannel(withEncryption: false)` 发布**动态 PSM**。
- 广播本地名格式为 `SR_<psm>_<memberCount>_<roomName>`；同时兼容 Android 侧厂商数据格式 `[PSM hi][PSM lo][count][roomName utf8]`。
- 接受成员接入的 `CBL2CAPChannel`，并在 `handleReceivedData` 中把收到数据转发给其余房主通道。
- `sendFrame` 数据写入所有房主通道。

### 2.3 成员（Central）

- 按服务 UUID 扫描，解析广播得到 PSM、人数与房名。
- 以 `peripheral.identifier` + PSM 连接并 `openL2CAPChannel(psm)`。

### 2.4 帧与流

- 入站 `consumeInput` 按 6 字节长度前缀做**重组**，`payloadLen > 512` 时丢弃输入缓冲并记日志。
- 出站 `sendFrame` → `writeToStream` 缓冲未写完的数据，并在 `.hasSpaceAvailable` 时 `drainWrites` 继续写。
- Method 方法：`isSupported`、`startHost`/`startAdvertising`、`stopHost`、`startScan`、`stopScan`、`connect`/`connectL2cap`、`disconnect`、`stop`、`sendFrame`/`sendL2capData`、`updateMemberCount`、`dispose`。

### 2.5 已知缺口

- **流分片/重组与房主广播中继尚未完全打通**。当前 `consumeInput` 已实现长度前缀重组、`handleReceivedData` 已包含房主转发逻辑，但：
  - 出站没有按 L2CAP CoC MTU 做显式分片；
  - 中继帧的发送者身份会被改写为 `host-<key>`（见 `streamPeerAddresses`），原始 `senderId` 语义在跨设备路径上不完整。
- 因此 iOS BLE 数据面目前**不能**视为可用的跨设备传输，需先补齐上述两项并做端到端验证。

---

## 3. 跨端协议与音频基线

- 6 字节大端帧头：`type(1) / senderId(1) / seq(2) / payloadLen(2)`，`payload ≤ 512` 字节。
- FrameType：audio `0x01`、joinReq `0x02`、roster `0x03`、pttState `0x04`、heartbeat `0x05`、leave `0x06`、hostHandover `0x07`、hostAnnounce `0x08`、handshakeHello `0x09`、handshakeConfirm `0x0a`、sealed `0x0b`、chat `0x0c`、chatSync `0x0d`、chatDelete `0x0e`。
- 音频：16 kHz 单声道 16-bit PCM，20 ms = 320 samples = 640 bytes；目标码率 Wi-Fi 24 kbps、蓝牙 16 kbps。
- Wi-Fi：TCP 8988 + UDP 8989 + 发现 UDP 8990，音频经房主中继。
- 蓝牙：BLE L2CAP CoC，动态 PSM 经 BLE 厂商数据广播；不做房主转发。
