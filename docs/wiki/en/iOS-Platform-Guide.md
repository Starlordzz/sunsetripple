> 🌐 English | [简体中文](../iOS平台适配指南.md)

# SunsetRipple iOS Platform Guide

This document describes the **current implementation** and the **remaining work** for SunsetRipple on iOS. The iOS side currently contains only two native plugins, both registered by `ios/Runner/AppDelegate.swift`:

- `ios/Runner/PlatformAudioPlugin.swift` — audio capture/playback plugin built on `AudioUnit` `kAudioUnitSubType_VoiceProcessingIO`.
- `ios/Runner/BleL2capPlugin.swift` — near-field data plugin built on BLE L2CAP CoC.

> ⚠️ `VoiceProcessingAudioEngine.swift` does **not** exist in the repo, and `MultipeerConnectivity` / `MultipeerTransport` are **not** used. Any sample based on them is not part of the current implementation.

iOS data-plane status: LAN TCP text/control messages work; the UDP audio data plane and the BLE data plane are not fully wired.

---

## 1. Audio Plugin `PlatformAudioPlugin.swift`

### 1.1 Channels

| Type | Name | Direction |
| --- | --- | --- |
| MethodChannel | `host.msknet.sunsetripple/audio` | Dart → iOS |
| EventChannel | `host.msknet.sunsetripple/audio_events` | iOS → Dart |

The event payload is `{ "data": Uint8List(PCM), "level": double }`, where `level` is the per-frame RMS normalized against a full scale of 32768, in the range `0.0 ~ 1.0`.

### 1.2 Audio parameters

- Sample rate 16000 Hz, mono, 16-bit linear PCM.
- Frame size 320 samples = 20 ms = 640 bytes (`PlatformAudioPlugin.frameSamples` / `bytesPerFrame`).
- Uses `kAudioUnitSubType_VoiceProcessingIO`, which enables system-level echo cancellation (AEC) and noise suppression (NS).
- Audio session category `.playAndRecord`, mode `.voiceChat`, with `setPreferredIOBufferDuration(0.02)`.

### 1.3 Methods

| Method | Arguments | Behavior |
| --- | --- | --- |
| `startCapture` | `{ bitrate?: Int }` | Checks microphone permission, then starts the AudioUnit; defaults to `bitrate = 24000` |
| `stopCapture` | — | Stops and disposes the AudioUnit, clears remote queues |
| `setMuted` | `{ muted: Bool }` | Sets the local mute flag |
| `setSpeakerphone` | `{ enabled: Bool }` | Switches speaker/receiver output routing |
| `setUseBuiltinMic` | `{ useBuiltinMic: Bool }` | Prefers the built-in mic or a headset/Bluetooth input |
| `setBitrate` | `{ bitrate: Int }` | Only records `currentBitrate` |
| `submitRemoteFrame` | `{ data: Uint8List }` | Feeds a remote frame |
| `removeRemoteMember` | `{ memberId: Int }` | Drops that member's playback queue |
| `clearRemoteMembers` | — | Clears all remote queues |
| `stopPlayback` | — | Same as `stopCapture` |
| `dispose` | — | Detaches channels and stops the engine |

### 1.4 Uplink audio

`audioInputCallback` pulls PCM via `AudioUnitRender` → `processCapturedPcm` computes RMS/level and, only when `isCapturing && !isMuted`, emits `{ data, level }` on the EventChannel.

### 1.5 Downlink playback and mixing

`submitRemoteFrame` hands the whole frame to `handleRemoteFrameData`:

1. Parses the 6-byte big-endian header `[type 1B][senderId 1B][seq 2B][payloadLen 2B]`.
2. Copies the payload as **raw PCM** into `Int16` samples per `senderId` (at most 640 bytes), appending to that member's queue.
3. Each member queue holds at most 10 frames.
4. `providePlaybackPcm` sums all member queues sample-by-sample and applies saturation clipping on output.

### 1.6 Known gaps

- **No Opus codec**: the entire path is raw PCM. The comment at `PlatformAudioPlugin.swift:290` states that if Opus were integrated the payload should be sent to an Opus decoder; today it is copied as raw PCM.
- **Per-frame payload ceiling of 640 bytes**: any `payload` longer than `bytesPerFrame` is truncated.
- `currentBitrate` (default 24000) is merely recorded by the methods and does not drive any actual encoding.

---

## 2. Near-Field BLE Plugin `BleL2capPlugin.swift`

### 2.1 Channels

| Type | Name | Payload |
| --- | --- | --- |
| MethodChannel | `host.msknet.sunsetripple/ble_l2cap` | — |
| EventChannel | `host.msknet.sunsetripple/ble_l2cap_data` | `{ data, peerAddress }` |
| EventChannel | `host.msknet.sunsetripple/ble_l2cap_scan` | `{ name, address, rssi, psm, memberCount }` |

Service UUID is `7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004`, company ID `0xFFFF`.

### 2.2 Host (Peripheral)

- Publishes a **dynamically allocated PSM** via `publishL2CAPChannel(withEncryption: false)`.
- Advertises a local name of the form `SR_<psm>_<memberCount>_<roomName>`; it also parses the Android manufacturer-data layout `[PSM hi][PSM lo][count][roomName utf8]`.
- Accepts incoming member `CBL2CAPChannel`s and, in `handleReceivedData`, forwards received data to the other host channels.
- `sendFrame` writes data to every host channel.

### 2.3 Member (Central)

- Scans by service UUID and parses the advertisement for PSM, member count, and room name.
- Connects with `peripheral.identifier` + PSM and calls `openL2CAPChannel(psm)`.

### 2.4 Frames and streams

- Inbound `consumeInput` **reassembles** frames by the 6-byte length prefix and discards the input buffer (with a log) when `payloadLen > 512`.
- Outbound `sendFrame` → `writeToStream` buffers unwritten data and continues in `drainWrites` on `.hasSpaceAvailable`.
- Methods: `isSupported`, `startHost`/`startAdvertising`, `stopHost`, `startScan`, `stopScan`, `connect`/`connectL2cap`, `disconnect`, `stop`, `sendFrame`/`sendL2capData`, `updateMemberCount`, `dispose`.

### 2.5 Known gaps

- **Stream fragmentation/reassembly and host broadcast relay are not fully wired**. `consumeInput` already performs length-prefixed reassembly and `handleReceivedData` contains host forwarding logic, but:
  - outbound data is not explicitly fragmented to the L2CAP CoC MTU;
  - relayed frames have their sender identity rewritten to `host-<key>` (see `streamPeerAddresses`), so the original `senderId` semantics are incomplete across devices.
- Consequently the iOS BLE data plane must **not** be treated as a working cross-device transport until these two items are completed and verified end-to-end.

---

## 3. Cross-platform protocol and audio baseline

- 6-byte big-endian header: `type(1) / senderId(1) / seq(2) / payloadLen(2)`, with `payload ≤ 512` bytes.
- FrameType: audio `0x01`, joinReq `0x02`, roster `0x03`, pttState `0x04`, heartbeat `0x05`, leave `0x06`, hostHandover `0x07`, hostAnnounce `0x08`, handshakeHello `0x09`, handshakeConfirm `0x0a`, sealed `0x0b`, chat `0x0c`, chatSync `0x0d`, chatDelete `0x0e`.
- Audio: 16 kHz mono 16-bit PCM, 20 ms = 320 samples = 640 bytes; target bitrate 24 kbps over Wi-Fi, 16 kbps over Bluetooth.
- Wi-Fi: TCP 8988 + UDP 8989 + discovery UDP 8990, with audio relayed through the host.
- Bluetooth: BLE L2CAP CoC with a dynamically allocated PSM advertised via BLE manufacturer data; no host transfer.
