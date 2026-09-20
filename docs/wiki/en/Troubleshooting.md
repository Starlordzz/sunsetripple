> 🌐 English | [简体中文](../故障排查.md)

# Troubleshooting

Organized by symptom. Each entry gives the most likely cause first, then how to verify it.

## Cannot Create a Room / Cannot Discover Devices

### Permissions Not Fully Granted

This is the most common cause. The app requests all runtime permissions at once in `MainActivity.kt`; the required items vary by Android version:

| Permission | Applies to |
| --- | --- |
| Microphone `RECORD_AUDIO` | All versions |
| Bluetooth `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN` / `BLUETOOTH_ADVERTISE` | Android 12+ (API 31+) |
| `NEARBY_WIFI_DEVICES` + notification `POST_NOTIFICATIONS` | Android 13+ (API 33+) |
| Fine location `ACCESS_FINE_LOCATION` | Below Android 13 (API 32 and lower) |

Key points:

- **Fine location cannot be "approximate location" only** — granting coarse location alone will still be blocked.
- **On Android 13+, granting the notification permission is recommended** — without it, the foreground call service's persistent notification is hidden and the service is more likely to be reclaimed by the system.
- On some systems, even with the fine-location permission granted, the system-level "Location Services" switch must also be on before Wi-Fi / Bluetooth scanning finds devices. This is an OS restriction, unrelated to this app.

The in-app denial prompt tells you which item is missing; just enable it accordingly.

### Wi-Fi Room Not Found / Direct Connection Fails

- Confirm the device supports Wi-Fi Direct (P2P); a few customized systems strip this capability.
- Turn off features that may seize the P2P channel: hotspot, screen casting, Wi-Fi Direct file transfer (such as the vendors' "quick share" apps).
- On some models, power-saving mode restricts P2P; disable power saving first and retry.
- Wi-Fi Direct requires the system to establish the connection; the app waits about 15 seconds and reports failure on timeout — move closer and try again.
- If it keeps failing, toggle Wi-Fi off and back on, then retry once.

### Bluetooth Room's Host Not Found

- Bluetooth Rooms require **Android 10 (API 29) or newer** and a BLE-capable device; on older versions the app reports the reason when you try to start one.
- Make sure Bluetooth is on and the Bluetooth permissions are granted.
- The Host must keep the room open; a scan result disappears from the list after about 6 seconds without reappearing, so just "Look nearby" again.
- Bluetooth Rooms do not require pairing in the system Bluetooth settings first.

## Connected but No Audio

### Check Local Audio First

This version has no loopback self-test. Walk through these instead:

- Is the microphone permission granted (`RECORD_AUDIO`)?
- Is the microphone occupied by another app (recording, incoming calls, voice assistants)?
- Was mute toggled by accident? Is the speaker / earpiece volume up?
- Is the other device muted?

### Bluetooth Room: Forgot to Push to Talk

The Bluetooth Room (PTT) is **Push-to-talk (PTT)**, not full-duplex. Hold the center disc to transmit; release to listen.

Also, while PTT is held, local playback is muted — not hearing others is **expected behavior**, meant to avoid echo. You will hear again once you release.

## Frequent Disconnects / Reconnection

### Distance and Obstruction

- Wi-Fi Direct: tens of meters in open space; walls attenuate significantly.
- Bluetooth: about 10 meters, and body obstruction noticeably affects it.

Take the device out of your pocket and avoid standing between the two devices.

### What Does Reconnection Look Like

In a Wi-Fi Room, after a disconnect the app retries three times at **1 s → 2 s → 4 s** intervals (`ReconnectController`).

- **Reconnection succeeds** → the original member id and join order are restored via the 16-byte session token; no need to rejoin.
- **All three attempts exhausted** → if a host handover snapshot is cached locally, the app takes over automatically (Wi-Fi Room); otherwise the room is exited.

Bluetooth Rooms currently have no separate automatic reconnection interface; after the link drops, search again and rejoin.

### System Kills the Background Process

The foreground service and multicast lock already do their best to keep the app alive, but Chinese OEM systems each have their own aggressive policies. If calls are frequently interrupted for no apparent reason:

1. Add the app to the **battery optimization whitelist** / "allow background activity" in system settings.
2. Turn off "auto-manage" or "smart power saving" for this app.
3. **Lock** the app in the recent tasks list.

### The Host Changed

When the Host leaves or loses connection, a Wi-Fi Room elects a successor from the snapshot and rebuilds automatically; voice is interrupted briefly, then recovers. **Bluetooth Rooms do not support host transfer** — the room ends when the Host leaves. See [Host Transfer](Host-Transfer.md) for details.

## Audio Quality Issues

### Choppy / Stuttering Audio

The jitter buffer's policy is **better to drop than to wait**: late packets are dropped outright, and the gaps left by drops are covered by Opus PLC. So a poor link manifests as slight choppiness rather than accumulating latency.

How to improve: shorten the distance, reduce obstruction, and avoid congested 2.4 GHz environments (microwaves, large numbers of Wi-Fi devices).

### Bluetooth Room Audio Is Noticeably Worse Than the Wi-Fi Room

This is by design. The Bluetooth Room runs at 16 kbps versus 24 kbps for the Wi-Fi Room; moreover, Bluetooth Room audio is relayed by the Host, adding one extra codec pass.

### Echo

- Android captures with `VOICE_COMMUNICATION` and enables hardware echo cancellation (AEC) / noise suppression (NS) / automatic gain control (AGC); iOS uses VoiceProcessingIO. Some models have no hardware AEC.
- Lower the speaker volume, or switch to a headset.
- When the two devices are too close (within one meter), speaker output bleeds directly into the other side's microphone; software cannot solve this.

## Diagnostic Report

The About page can generate and copy a diagnostic report. The report is sanitized: MAC addresses, IPv4 addresses, and long tokens are replaced with placeholders. It reflects only the current state — nothing is written to disk, persisted, or uploaded automatically.

## Installation Issues

### "App not installed" or "package conflict"

The current package name is `host.msknet.sunsetripple`. An early test build used the historical package name `com.wt.intercom`; the code package names and signatures differ, so **it cannot upgrade over the old build — uninstall the old version first**.

### System Blocks Installation

APKs from unknown sources require allowing the corresponding installation source (browser / file manager) in system settings.

## Build Issues

See [Build and Release](Build-and-Release.md) and [FAQ](FAQ.md#build-related).

## Related Pages

- [FAQ](FAQ.md) · [Audio Pipeline](Audio-Pipeline.md) · [Room Modes](Room-Modes.md) · [Host Transfer](Host-Transfer.md)
