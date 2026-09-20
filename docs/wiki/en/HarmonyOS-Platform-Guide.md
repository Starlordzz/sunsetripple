> 🌐 English | [简体中文](../HarmonyOS平台适配指南.md)

# SunsetRipple HarmonyOS NEXT Platform Guide

This document describes the **current implementation** and the **remaining work** for SunsetRipple in the native HarmonyOS NEXT environment.

Under `harmonyos/entry/src/main/ets/` the following actually exist:

| Path | Status | Notes |
| --- | --- | --- |
| `audio/HarmonyAudioEngine.ets` | Implemented | ArkTS audio capture/render wrapper |
| `model/Frame.ets` | Implemented | Frame types and 6-byte header codec |
| `session/HarmonyRoomSession.ets` | Implemented (scaffolding) | Coordinates session state; network send is empty |
| `transport/LanRoomDiscovery.ets` | Implemented (scanner only) | `HarmonyLanScanner`, aligned with the Dart discovery protocol |
| `plugin/PlatformAudioPlugin.ets` | **Empty file (0 bytes)** | Platform-channel bridge missing |
| `pages/Index.ets` | Implemented | Home ArkUI page |
| `pages/RoomPage.ets` | Implemented | Room/PTT ArkUI page |
| `entryability/EntryAbility.ets` | Implemented | UIAbility entry point |

> ⚠️ `WifiP2pTransport.ets` does **not** exist in the repo. Any sample based on Wi-Fi P2P is not part of the current implementation.

**Data-plane status: not connected. Only UDP discovery works.**

---

## 1. Audio Engine `audio/HarmonyAudioEngine.ets`

`HarmonyAudioEngine` wraps the `AudioCapturer` and `AudioRenderer` from `@ohos.multimedia.audio`:

- Constants: `SAMPLE_RATE = 16000`, `FRAME_SAMPLES = 320` (20 ms).
- Audio stream: 16000 Hz, mono, `SAMPLE_FORMAT_S16LE`, `ENCODING_TYPE_RAW`.
- Capturer: `SOURCE_TYPE_VOICE_COMMUNICATION`; renderer: `STREAM_USAGE_VOICE_COMMUNICATION`, letting the system enable call-grade AEC/NS.
- API: `start()`, private `captureLoop()` (loops `read` in 640-byte chunks), `playPcm(pcm: Int16Array)` (`renderer.write`), `stop()`.
- Callback and state: `onPcmFrame(pcm: Int16Array)`, `micMuted`.

In other words, the Android/iOS audio parameters — 16 kHz mono 16-bit, 20 ms / 320 samples / 640 bytes — are identical on HarmonyOS.

---

## 2. Frame Protocol `model/Frame.ets`

Byte-order identical to Android / iOS (1:1):

- 6-byte big-endian header: `[type 1B][senderId 1B][seq 2B][payloadLen 2B]`, `payload ≤ 512` (`Frame.HEADER_SIZE = 6`, `Frame.MAX_PAYLOAD = 512`).
- `Frame.encode()` / `Frame.decode()` provide the codec.

The `FrameType` enum (1..14) and its cross-platform name mapping:

| Value | Enum name | Cross-platform name |
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

## 3. Session `session/HarmonyRoomSession.ets`

`HarmonyRoomSession` is **scaffolding**: it holds a `HarmonyAudioEngine` and exposes `start()` / `leave()`, `setPttPressed()`, `toggleMute()`, `members`, `isConnected`, and `onStateChanged`.

**Key gap**: `onLocalAudioCaptured(pcm)` is empty (only a comment saying a Frame could be packed and sent over UDP). There is no network send or receive at all. Locally captured PCM is never packed or sent, and remote audio is never played.

---

## 4. LAN Discovery `transport/LanRoomDiscovery.ets`

Contains only `HarmonyLanScanner`, aligned with the JSON discovery protocol of the Dart-side `LanRoomDiscovery`:

- `DISCOVERY_PORT = 8990`, `DISCOVERY_MAGIC = 'SUNSET_RIPPLE_DISCOVERY_V1'`.
- Broadcast payload is UTF-8 JSON: `{ magic, roomId, roomName, hostNickname, port, members, action?, timestamp }`.
- The host IP is taken from the datagram source address (the payload carries no IP, to prevent spoofing).
- `ROOM_CLOSED` removes a room immediately; `ROOM_EXPIRY_MS = 3500` removes it on timeout; room names are capped at 64 characters.
- Emits `onRoomsUpdate(rooms)`.

**Gap**: scanning/listening only; there is no advertiser (it cannot publish a room as host).

---

## 5. UI and Ability

- `entryability/EntryAbility.ets`: loads `pages/Index`.
- `pages/Index.ets`: nickname input plus "Create Room / Join Room", routing to `pages/RoomPage`.
- `pages/RoomPage.ets`: PTT disc, mute/speaker/leave buttons; bound to `HarmonyRoomSession`. Because the session data plane is empty, the UI is interactive but carries no actual audio.

---

## 6. Platform Channel `plugin/PlatformAudioPlugin.ets`

This file **exists but is empty (0 bytes)**. HarmonyOS therefore has no ArkTS bridge equivalent to the Android/iOS MethodChannel / EventChannel layers, so a Flutter/SDK layer cannot drive `HarmonyAudioEngine` or `HarmonyRoomSession` through it.

---

## 7. Known Gaps Summary

- `plugin/PlatformAudioPlugin.ets` is an empty file; the platform-channel bridge is missing.
- **Data plane not connected**: `HarmonyRoomSession.onLocalAudioCaptured` is empty; there is no TCP 8988 / UDP 8989 send/receive and no BLE. Only UDP 8990 discovery works.
- The discovery layer only has `HarmonyLanScanner`; the room advertiser is missing.
- No Opus codec.
- `WifiP2pTransport.ets` does not exist.

---

## 8. Cross-platform protocol and audio baseline

- 6-byte big-endian header: `type(1) / senderId(1) / seq(2) / payloadLen(2)`, with `payload ≤ 512`.
- Audio: 16 kHz mono 16-bit PCM, 20 ms = 320 samples = 640 bytes; target bitrate 24 kbps over Wi-Fi, 16 kbps over Bluetooth.
- Wi-Fi: TCP 8988 + UDP 8989 + discovery UDP 8990, with audio relayed through the host.
- Bluetooth: BLE L2CAP CoC with a dynamically allocated PSM advertised via BLE manufacturer data; no host transfer.
