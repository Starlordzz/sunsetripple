# Core-Shell（核心-外壳）统一多端架构规范

SunsetRipple（落日后残波）采用业界成熟的 **Core-Shell（核心-外壳）** 与 **Ports & Adapters（端口与适配器）** 架构。

---

## 1. 架构核心思想

像 **FlClash / Clash Verge / Spotify** 等优秀的跨平台应用一样：
> **“核心引擎与界面业务沉淀在 Core，各操作系统仅作为一层极薄的 Shell（启动与硬件外壳）。”**

```mermaid
flowchart TD
    subgraph CORE ["💎 Core（统一业务核心）"]
        direction TB
        PROTO["📦 1. 协议核心：6 字节二进制 Frame 编解码、Roster 名单"]
        AUDIO_ALGO["🔊 2. 音频算法：Mixer 混音器、JitterBuffer 抖动缓冲、Opus 编解码"]
        SESSION_SM["🧠 3. 房间状态机：RoomSession Mesh 全双工 / PTT 仲裁、房主选举"]
        DISCOVERY["🌐 4. 网络发现：UDP 8990 广播信标与局域网热点 Mesh 自动组网"]
        THEME["🎨 5. 美学与主题：落日暖色 / 月海冷色调色板、圆盘手势交互"]
    end

    subgraph PORTS ["🔌 Ports（抽象硬件接缝）"]
        P_AUDIO["AudioIo (音频采集/播放接缝)"]
        P_TRANS["Transport (近场链路与 Socket 接缝)"]
        P_NOTIF["PlatformService (后台保活与通知接缝)"]
    end

    subgraph SHELLS ["🐚 Shells（各平台超薄打包外壳）"]
        S_AND["📱 Android Shell (`app/`)<br/>• Activity / 前台服务<br/>• WifiDirectManager & BluetoothAdapter<br/>• 产出 `.apk`"]
        S_IOS["🍏 iOS Shell (`ios/`)<br/>• Flutter Runner<br/>• AudioUnit (VoiceProcessingIO) & CoreBluetooth L2CAP<br/>• 产出 `.ipa`"]
        S_HARMONY["🔴 HarmonyOS NEXT Shell (`harmonyos/`)<br/>• ArkUI Launcher<br/>• @ohos.multimedia.audio & @ohos.net.wifi<br/>• 产出 `.hap`"]
        S_DESKTOP["💻 Desktop Shell (`desktop/`)<br/>• JavaSound & Windows/Mac 窗口启动器<br/>• 产出 `.exe` / `.msi`"]
    end

    CORE --> PORTS
    PORTS --> SHELLS
```

---

## 2. 目录规范与职责划分

| 层次 / 模块 | 目录路径 | 职责与技术栈 |
| :--- | :--- | :--- |
| **Core 统一核心** | [`app/src/main/kotlin/host/msknet/sunsetripple/`](file:///d:/LEARNING/vibeproject/SunsetRipple/app/src/main/kotlin/host/msknet/sunsetripple/) | • `protocol/`：统一二进制帧<br/>• `audio/`：混音、抖动缓冲、`AudioIo` 接口<br/>• `transport/lan/`：UDP 8990 跨端房间发现<br/>• `session/`：房间会话生命周期<br/>• `ui/`：落日调色板与工具栏决策模型 |
| **Android Shell** | [`app/`](file:///d:/LEARNING/vibeproject/SunsetRipple/app/) | 承载 AndroidManifest、前台保活服务、`WifiP2pManager` 与 `BluetoothServerSocket` |
| **HarmonyOS Shell** | [`harmonyos/`](file:///d:/LEARNING/vibeproject/SunsetRipple/harmonyos/) | 承载 DevEco Studio 工程、ArkTS 入口、`AudioCapturer`/`AudioRenderer`、ArkUI 界面 |
| **iOS Shell** | [`ios/`](file:///d:/LEARNING/vibeproject/SunsetRipple/ios/) | 承载 Xcode 工程、Flutter Runner、`PlatformAudioPlugin` (VoiceProcessingIO)、`BleL2capPlugin` |

---

## 3. 跨端行为一致性保证

1. **协议字节一致**：
   所有平台生成的音频与控制帧严格遵循 `[Type 1B][SenderId 1B][Seq 2B][Length 2B][Payload ≤512B]` 规范，大小端保持网络字节序（Big-Endian）。
2. **音频参数一致**：
   全平台统一采样率 **16,000 Hz**，单声道 16-bit PCM，每帧采样点 **320 Samples (20ms)**。
3. **视觉调色板一致**：
   - **日间落日**：主强调 `#9B4A52`（暖珊瑚），离开按钮 `#FF9E90`，背景 `#F4F1EC`。
   - **夜间月海**：主强调 `#3F76AC`（海蓝），离开按钮 `#FF7B92`（冷调玫瑰粉），背景 `#0E1626`。

