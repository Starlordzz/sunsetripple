> 🌐 English | [简体中文](../故障排查.md)

# Troubleshooting

Organized by symptom. Each entry gives the most likely cause first, then how to verify it.

## Cannot Create a Room / Cannot Discover Devices

### Permissions Not Fully Granted

This is the most common cause. The permissions the app needs vary considerably by Android version:

| Android Version | Wi-Fi Room requires | Bluetooth Room (PTT) requires |
| --- | --- | --- |
| 8.0 – 11 (API 26–30) | Microphone + Fine location | Microphone + Fine location |
| 12 (API 31–32) | Microphone + Fine location | Microphone + `BLUETOOTH_SCAN` (to join) or `BLUETOOTH_ADVERTISE` (to create) |
| 13+ (API 33+) | Microphone + `NEARBY_WIFI_DEVICES` + notification permission | Microphone + Bluetooth permissions + notification permission |

Key points:

- **Fine location cannot be "approximate location" only** — granting coarse location alone will still be blocked.
- **On Android 13+, the notification permission is a hard prerequisite** — the foreground call service needs it; denying it directly blocks joining a room.
- **On Android 9–12 (API 28–32), the system-level "Location Services" switch must also be turned on** — granting the permission alone is not enough. This is an OS-level restriction on Wi-Fi / Bluetooth scanning, unrelated to this app.

The in-app denial prompt tells you which item is missing; just enable it accordingly.

### Wi-Fi Direct Group Creation Failures

- Confirm the device supports Wi-Fi P2P (a few customized systems strip this capability).
- Turn off features that may seize the P2P channel: hotspot, screen casting, Wi-Fi Direct file transfer (such as the vendors' "quick share" apps).
- On some models, power-saving mode restricts P2P; disable power saving first and retry.
- During group creation the system may pop up a connection confirmation dialog that **must be confirmed manually**; failing to confirm before the timeout causes failure.
- If it reports "group owner address not ready" and returns to the home page after 10 seconds, the P2P channel is usually occupied or the system has not delivered the address in time — toggle Wi-Fi off and back on, then retry once.

### Bluetooth Cannot Find the Host

- The Host must be in a **discoverable** state, valid for 300 seconds; after it expires, recreate the room.
- Pair once in the system Bluetooth settings first; it is usually more reliable.
- Classic Bluetooth discovery is inherently slow; waiting 10–20 seconds is normal.

## Connected but No Audio

### Step One: Run the Loopback Self-Test

Enter loopback mode from the home page. It runs the full audio pipeline **on a single device** (microphone → encoding → jitter buffer → decoding → speaker).

- **Loopback has audio** → the audio stack is fine; the problem is in the network link. Read on.
- **Loopback is silent** → the problem is local audio; check microphone permission, whether the microphone is occupied by another app, and the volume.

### Audio Focus Stolen

Incoming calls, navigation announcements, and other media apps can take the audio focus. This app's strategy is to **degrade to listen-only rather than drop the connection** — so the UI still shows an ongoing call, but what you say is not sent out.

Hang up the incoming call or close the app that took focus to recover. Note: **focus recovery does not automatically undo a mute you set manually** — this is intentional; check the state of the mute button.

### Listen-Only Mode

Make sure listen-only mode was not toggled by accident. The mute state in the UI and the control button in the notification shade are the same piece of state.

### Bluetooth Room: Forgot to Push to Talk

The Bluetooth Room (PTT) is **Push-to-talk (PTT)**, not full-duplex. Hold the center disc to transmit; release to listen.

Also, while PTT is held, local playback is muted — not hearing others is **expected behavior**, meant to avoid echo. You will hear again once you release.

## Frequent Disconnects

### Distance and Obstruction

- Wi-Fi Direct: tens of meters in open space; walls attenuate significantly.
- Bluetooth: about 10 meters, and body obstruction noticeably affects it.

Take the device out of your pocket and avoid standing between the two devices.

### What Does Reconnection Look Like

After a disconnect, it retries three times at **1 s → 2 s → 4 s** intervals. During this the UI shows "Reconnecting", and member slots are reserved for 7 seconds.

- **Reconnection succeeds** → the original member ID and join order are restored via the token; no need to rejoin.
- **All three attempts exhausted** → if a Host snapshot is cached locally, the host takeover flow is triggered automatically instead of disbanding immediately; otherwise the room is exited.

### System Kills the Background Process

Foreground service + WakeLock + WifiLock already do their best to keep the app alive, but Chinese OEM systems each have their own aggressive policies. If calls are frequently interrupted for no apparent reason:

1. Add the app to the **battery optimization whitelist** / "allow background activity" in system settings.
2. Turn off "auto-manage" or "smart power saving" for this app.
3. **Lock** the app in the recent tasks list.

### The Host Changed

When the Host leaves or crashes, the room automatically elects a successor and rebuilds. During this process:

- **Bluetooth Room**: rebuilds quickly; voice is interrupted briefly.
- **Wi-Fi Room**: the Wi-Fi Direct group must be rebuilt, so voice is interrupted longer, and **the system may pop up the connection confirmation dialog again** — it must be confirmed manually, otherwise reconnection fails.

See [Host Transfer](Host-Transfer.md) for details.

## Audio Quality Issues

### Choppy / Stuttering Audio

The jitter buffer's policy is **better to drop than to wait**: late packets are dropped outright, and the gaps left by drops are covered by Opus PLC. So a poor link manifests as slight choppiness rather than accumulating latency.

How to improve: shorten the distance, reduce obstruction, and avoid congested 2.4 GHz environments (microwaves, large numbers of Wi-Fi devices).

### Bluetooth Room Audio Is Noticeably Worse Than the Wi-Fi Room

This is by design. The Bluetooth Room runs at 16 kbps versus 24 kbps for the Wi-Fi Room; moreover, Bluetooth Room audio has to be mixed and forwarded by the Host, adding one extra codec pass.

### Echo

- Confirm the device supports and has enabled hardware echo cancellation (the app automatically enables `AcousticEchoCanceler`, but some models do not have it).
- Lower the speaker volume, or switch to a headset.
- When the two devices are too close (within one meter), speaker output bleeds directly into the other side's microphone; software cannot solve this.

## Installation Issues

### "App not installed" or "package conflict"

This happens when an old test build with the package name `com.wt.intercom` was installed. The package name has changed to `host.msknet.sunsetripple`; **it cannot upgrade over the old build — the old version must be uninstalled first**.

### System Blocks Installation

APKs from unknown sources require allowing the corresponding installation source (browser / file manager) in system settings.

## Build Issues

See [Build and Release](Build-and-Release.md) and [FAQ](FAQ.md#build-related).

## Related Pages

- [FAQ](FAQ.md) · [Audio Pipeline](Audio-Pipeline.md) · [Room Modes](Room-Modes.md) · [Host Transfer](Host-Transfer.md)
