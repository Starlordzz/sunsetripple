> 🌐 English | [简体中文](../常见问题.md)

# FAQ

## Usage

**Does it need the internet? Does it need an account?**

Neither. No servers, no accounts, no cloud. Voice is transmitted peer-to-peer between devices only; not a single byte passes through a third party. The app requests the `INTERNET` permission, but that is an OS requirement for socket communication, not for accessing the internet.

**How many people at most?**

6 devices, including the Host. This is a hard limit at the protocol level (`MAX_MEMBERS = 6`); join requests beyond it are rejected, without affecting members already in the room.

**How far does it reach?**

Wi-Fi Room (LAN / hotspot / Wi-Fi Direct): roughly tens of meters in open space; Bluetooth Room (PTT): about 10 meters. Walls and body obstruction shorten the range considerably.

**Does it drain the battery?**

The Wi-Fi Room is noticeably more power-hungry — a persistent TCP/UDP link plus WakeLock and WifiLock. The Bluetooth Room (PTT) consumes far less power. For long sessions, prefer the Bluetooth Room.

**Why can't everyone talk at the same time in a Bluetooth Room?**

RFCOMM bandwidth cannot sustain 6-way full-duplex mixing. Rather than a choppy, uneven full-duplex experience, it is built as reliable Push-to-talk (PTT). See [Room Modes](Room-Modes.md).

**Why can't I hear others while holding Push-to-talk?**

By design — while Push-to-talk (PTT) is held, local playback is muted to prevent your own voice from looping back through the link as echo. Release the button to hear others.

**Why does the room expand directly from the button when I tap Create Room?**

The expanding area draws the actual room UI, not a transitional overlay that vanishes after playing. The home page and the room share the same sunset header motion and color scheme, so no page switch is needed when the animation ends, and no black frames or a second pop-in of the room page occur.

**Is the room gone once the Host leaves?**

No. The room automatically elects **the earliest-joined member who is still online** to take over and rebuild. The Host leaving voluntarily, a process crash, being killed by the system, or a link interruption can all trigger it. See [Host Transfer](Host-Transfer.md).

**Does it support dark mode? What about multiple languages?**

Dark mode yes, multiple languages no. The color scheme has three settings — Follow system / Always light / Always dark — with the entry at the top-right of the home page header; tap to cycle, and the choice is remembered. Light is sunset warm tones, dark is the moon and the sea — both schemes share the same drawing code, so the celestial body in the header is the moon at night. UI text is still entirely Simplified Chinese and hardcoded in Kotlin; the project has no `strings.xml`.

**Where did the Nearby Room go?**

The code and tests are in the repository, but the home page entry has been turned off. Three reasons: it depends on Google Play services (a large number of devices in China do not have them), it does not support host transfer, and its capabilities overlap with the Wi-Fi Room. See [Room Modes](Room-Modes.md#nearby-room-shelved).

**Can it record? Can it send text?**

No. Currently it is real-time voice only — no recording, no text messages, no file transfer. The protocol payload limit is 512 bytes; it is not designed for file transfer either.

## Privacy

**Will voice be uploaded?**

No. There is no server to upload to. Audio travels only between devices with an established direct connection.

**Is the call encrypted?**

**There is no encryption at the application layer.** Security relies on the underlying link: Bluetooth RFCOMM uses secure mode by default (pairing encryption), and Wi-Fi Direct relies on WPA2 group keys. Note, however, that after a host transfer, the rebuilt Bluetooth connection uses **non-secure mode** (to avoid re-pairing).

If your use case has confidentiality requirements, evaluate it yourself — this project's design goal is "being able to talk without the internet", not "anti-eavesdropping".

**Does the room leave any records behind?**

No. No database, no persisted logs; once the room disbands, nothing remains.

## Build-Related

**What toolchain is required?**

JDK 17; everything else is handled by the Gradle 8.9 wrapper bundled with the repository. For the complete list, see [Build and Release](Build-and-Release.md).

**What if dependency downloads fail / the TLS connection breaks?**

`settings.gradle.kts` already places the Aliyun mirrors before `google()` / `mavenCentral()`, precisely for environments where direct access to `dl.google.com` suffers TLS interruption. If it still fails, check the proxy settings, or configure a proxy in `~/.gradle/gradle.properties`.

**Why not compile native libopus with the NDK?**

It uses Concentus, a pure-JVM Opus implementation. The cost: the codec runs on the JVM with slightly higher CPU overhead. The benefit: the build does not depend on the NDK, the artifacts contain no `.so` files, and no per-ABI packaging is needed. For the scale of 16 kHz mono 20 ms frames, the CPU overhead is entirely acceptable.

**Why can't I install even after changing `versionCode`?**

Most likely the signature differs. Android identifies the app's origin by its signing certificate; packages signed with a different key cannot install over the existing one. The debug and release builds installed during development also use two different signatures — uninstall first.

**`packageRelease` reports "missing local release signing configuration"?**

That is the `verifyReleaseSigning` guard task stopping you — the root directory lacks `keystore.properties`, or a field is missing, or the key file pointed to by `storeFile` does not exist. Fill it in following `keystore.properties.example`. The guard exists to prevent unsigned or wrongly signed artifacts.

**Do the tests need an emulator?**

No. All test cases are pure unit and component tests, runnable in seconds via `flutter test`.

## Project

**Can it be used in production?**

It is currently at the `0.1.0-alpha.11` testing stage. The core paths (Wi-Fi LAN/hotspot/direct full-duplex, Bluetooth PTT, near-field text messages, disconnect reconnection, host handover) all work and are covered by automated tests. It is recommended as a near-field emergency intercom and as a learning reference.

**What is the license?**

[Apache License 2.0](../../../LICENSE). Free to use, modify, distribute, and commercialize, with an explicit patent grant; it requires keeping the copyright notice and stating changes.

**What does the project name mean?**

The sun has already set, yet the ripple on the sea has not faded. Some sounds do not travel over the network and leave no server behind — they can only be heard while you are still close enough to one another. That is “落日后残波” — SunsetRipple.

## Related Pages

- [Troubleshooting](Troubleshooting.md) · [Build and Release](Build-and-Release.md) · [Home](Home.md)
