> 🌐 English | [简体中文](../Home.md)

# SunsetRipple · Wiki

> After the sunset, the ripples are still speaking for us — the words we never finished saying that day.
>
> *The sun has gone; the ripple hasn't.*

This is the complete technical documentation for **SunsetRipple (落日后残波)**. For the project itself, see the [README](../../../README.md).

## What This Is

An Android near-field voice intercom app: voice never passes through a server. Using the phone's built-in Wi-Fi Direct and Classic Bluetooth, it spins up ad-hoc voice rooms across up to 6 devices; version checks reach GitHub only on user action.

## Find a Page by Need

| What you want to do | Go here |
| --- | --- |
| Cross-platform architecture and the Core-Shell design | [Core-Shell Unified Multi-Platform Architecture](Core-Shell-Architecture.md) |
| Adapting the iOS side (AudioUnit / Multipeer) | [iOS Platform Guide](iOS-Platform-Guide.md) |
| Adapting HarmonyOS NEXT | [HarmonyOS Platform Guide](HarmonyOS-Platform-Guide.md) |
| Quickly understanding how the whole project fits together | [Architecture Overview](Architecture-Overview.md) |
| Implementing a compatible client / analyzing packet captures | [Protocol Specification](Protocol-Specification.md) |
| Deciding between a Wi-Fi Room and a Bluetooth Room (PTT) | [Room Modes](Room-Modes.md) |
| Tuning audio quality, changing bitrate, understanding latency sources | [Audio Pipeline](Audio-Pipeline.md) |
| Understanding why the room does not dissolve when the Host leaves | [Host Transfer](Host-Transfer.md) |
| Building the source into installable packages | [Build and Release](Build-and-Release.md) |
| Cannot connect, no sound, constant disconnects | [Troubleshooting](Troubleshooting.md) |
| General questions | [FAQ](FAQ.md) |

## Suggested Reading Order

New to this codebase? Reading in this order takes the least effort:

1. **[Core-Shell Unified Multi-Platform Architecture](Core-Shell-Architecture.md)** — understand the layering contract between the cross-platform core and the per-platform shells.
2. **[Architecture Overview](Architecture-Overview.md)** — build the layered mental model first: `ui → session → transport → protocol`, and how `audio` cuts across.
3. **[Protocol Specification](Protocol-Specification.md)** — the frame format is the hub of the whole system; once you understand the 8 frame types, you understand most of the interactions.
4. **[Room Modes](Room-Modes.md)** — understand why one and the same session layer grows two radically different kinds of rooms.
5. **[Audio Pipeline](Audio-Pipeline.md)** — the complete chain of capture, encoding, jitter buffering, mixing, and playback.
6. **[Host Transfer](Host-Transfer.md)** — the most complex part of the project; best saved for last.

## Key Facts at a Glance

| Item | Value |
| --- | --- |
| Package name / Bundle ID | `host.msknet.sunsetripple` |
| Current version | `0.1.0-alpha.12` (versionCode 13) |
| Supported systems | Android 8.0+ / iOS 15.0+ / HarmonyOS NEXT (API 12+) |
| Target / compile SDK | Android 35 / HarmonyOS 5.0(12) / iOS 15.0 |
| Languages & UI | Flutter (Dart) + C++ FFI + Kotlin / Swift / ArkTS native channels |
| Test scale | 18 test suites, 131 automated test cases |
| Audio codec | Opus (C++ FFI lock-free ring buffer / native hardware AEC), 16 kHz mono 20 ms |
| Room capacity | 6 devices (Host included) |
| License | Apache-2.0 |

## Project Conventions

- **The UI automatically follows the system language (Chinese or English)**; resource tests verify that both key sets and format placeholders match.
- **Updates refuse unsigned content by default**: manifest, APK hashes, package name, and certificate are verified in sequence; installation is handed to Android for confirmation.
- **Diagnostics must be exported explicitly by the user**, and contain no audio, no raw nicknames, no device addresses, and no key material.
- **No dependency-injection framework, no database, no networking library** — the transport layer uses `java.net` and `android.bluetooth` directly.
- **Tests use no Robolectric / MockK / Mockito**; everything is hand-written fakes, so the suite runs on a plain JVM in seconds.
- **Pure decision logic is always extracted into Android-free objects** (such as `HostElection`, `RoomFlow`, `RoomPermissions`, `BluetoothMixPlanner`) — this is the fundamental reason test coverage can be made thick.
- **The room-creation transition reveals the real room screen directly**; the home page and the room share the sunset header's motion phase and the same color source; there is no second stage that switches screens after an animation ends.
- **In-room controls stay lightweight**: member orbits, the channel core, mute, speaker, and leave are layered by frequency of use; dangerous actions no longer occupy the primary visual position.
- **The day and night palettes share the same set of slot semantics**: light mode is sunset, night mode is moon and sea; both reuse the same drawing code, so the celestial body in the header turns from sun to moon without any change in geometry. There are three modes — follow system / light / dark — with the entry at the top-right of the home page header.

## Related Links

- [Releases](https://github.com/Starlordzz/sunsetripple/releases) — installer packages for all three platforms and the full source download (note: iOS ships a pure-native ARM64 package with an extremely small footprint for fast installation; the HarmonyOS `.hap` is a placeholder for now — download the full source project and build it locally with DevEco Studio)
- [CHANGELOG](../../../CHANGELOG.md) — version history
- [LICENSE](../../../LICENSE) — Apache-2.0
