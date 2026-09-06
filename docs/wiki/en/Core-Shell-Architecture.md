> 🌐 English | [简体中文](../Core-Shell统一多端架构.md)

# Core-Shell Unified Multi-Platform Architecture Specification

SunsetRipple (落日后残波) adopts the industry-proven **Core-Shell** and **Ports & Adapters** architectures.

---

## 1. Core Architectural Idea

Like excellent cross-platform apps such as **FlClash / Clash Verge / Spotify**:
> **"The core engine and UI business logic settle into the Core; each operating system serves only as an extremely thin Shell (startup and hardware casing)."**

```mermaid
flowchart TD
    subgraph CORE ["💎 Core (Unified Business Core)"]
        direction TB
        PROTO["📦 1. Protocol core: 6-byte binary Frame codec, Roster"]
        AUDIO_ALGO["🔊 2. Audio algorithms: Mixer, JitterBuffer, Opus codec"]
        SESSION_SM["🧠 3. Room state machine: RoomSession Mesh full-duplex / PTT arbitration, Host election"]
        DISCOVERY["🌐 4. Network discovery: UDP 8990 broadcast beacons and LAN/hotspot mesh auto-networking"]
        THEME["🎨 5. Aesthetics & theme: sunset warm / moon-sea cool palettes, disc gesture interaction"]
    end

    subgraph PORTS ["🔌 Ports (Abstract Hardware Seams)"]
        P_AUDIO["AudioIo (audio capture/playback seam)"]
        P_TRANS["Transport (near-field link and Socket seam)"]
        P_NOTIF["PlatformService (background keep-alive and notification seam)"]
    end

    subgraph SHELLS ["🐚 Shells (Ultra-thin per-platform packaging shells)"]
        S_AND["📱 Android Shell (`app/`)<br/>• Activity / foreground service<br/>• WifiDirectManager & BluetoothAdapter<br/>• Produces `.apk`"]
        S_IOS["🍏 iOS Shell (`ios/`)<br/>• Flutter Runner<br/>• AudioUnit (VoiceProcessingIO) & CoreBluetooth L2CAP<br/>• Produces `.ipa`"]
        S_HARMONY["🔴 HarmonyOS NEXT Shell (`harmonyos/`)<br/>• ArkUI Launcher<br/>• @ohos.multimedia.audio & @ohos.net.wifi<br/>• Produces `.hap`"]
        S_DESKTOP["💻 Desktop Shell (`desktop/`)<br/>• JavaSound & Windows/Mac window launcher<br/>• Produces `.exe` / `.msi`"]
    end

    CORE --> PORTS
    PORTS --> SHELLS
```

---

## 2. Directory Layout and Responsibility Split

| Layer / Module | Directory | Responsibilities & Tech Stack |
| :--- | :--- | :--- |
| **Core (unified core)** | [`app/src/main/kotlin/host/msknet/sunsetripple/`](../../../app/src/main/kotlin/host/msknet/sunsetripple/) | • `protocol/`: unified binary frames<br/>• `audio/`: mixing, jitter buffer, `AudioIo` interface<br/>• `transport/lan/`: UDP 8990 cross-platform room discovery<br/>• `session/`: room session lifecycle<br/>• `ui/`: sunset palette and toolbar decision models |
| **Android Shell** | [`app/`](../../../app/) | Hosts the AndroidManifest, the foreground keep-alive service, `WifiP2pManager` and `BluetoothServerSocket` |
| **HarmonyOS Shell** | [`harmonyos/`](../../../harmonyos/) | Hosts the DevEco Studio project, the ArkTS entry point, `AudioCapturer`/`AudioRenderer`, and the ArkUI interface |
| **iOS Shell** | [`ios/`](../../../ios/) | Hosts the Xcode project, the Flutter Runner, `PlatformAudioPlugin` (VoiceProcessingIO), and `BleL2capPlugin` |

---

## 3. Cross-Platform Behavioral Consistency Guarantees

1. **Byte-level protocol consistency**:
   Audio and control frames generated on all platforms strictly follow the `[Type 1B][SenderId 1B][Seq 2B][Length 2B][Payload ≤512B]` specification, with byte order kept as network byte order (Big-Endian).
2. **Audio parameter consistency**:
   All platforms use a unified sample rate of **16,000 Hz**, mono 16-bit PCM, with **320 samples (20ms) per frame**.
3. **Visual palette consistency**:
   - **Daytime Sunset**: primary accent `#9B4A52` (warm coral), leave button `#FF9E90`, background `#F4F1EC`.
   - **Night Moon-Sea**: primary accent `#3F76AC` (ocean blue), leave button `#FF7B92` (cool rose pink), background `#0E1626`.
