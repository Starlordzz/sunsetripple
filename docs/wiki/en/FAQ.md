> 🌐 English | [简体中文](../常见问题.md)

# FAQ

## Usage

**Does it need the internet? Does it need an account?**

Neither. No servers, no accounts, no cloud; voice travels only between devices that have an established direct link. The app requests the `INTERNET` permission, but that is an OS requirement for socket communication, not for accessing the internet. The app only reaches GitHub Releases when the user explicitly checks for an update.

**How many people at most?**

6 devices, including the Host. The Host takes member id 1 and up to 5 more devices can join; join requests beyond that are rejected without affecting members already in the room. The limit is enforced in both the session layer and the transport layer (there is no standalone `MAX_MEMBERS` constant).

**How does voice travel?**

In a star topology: every device links only to the Host, and the Host relays audio frames to the other members — devices do not send audio directly to each other. In a Wi-Fi Room, control frames use TCP 8988, audio uses UDP 8989, and the Host advertises the room on UDP 8990; in a Bluetooth Room everything runs over BLE L2CAP CoC, with relaying done in native code.

**How far does it reach?**

Wi-Fi Room (LAN / hotspot / Wi-Fi Direct): roughly tens of meters in open space; Bluetooth Room (PTT): about 10 meters. Walls and body obstruction shorten the range considerably.

**Does it drain the battery?**

The Wi-Fi Room is more power-hungry — a persistent TCP/UDP link plus a multicast lock and a foreground service. The Bluetooth Room (PTT) consumes far less power. For long sessions, prefer the Bluetooth Room.

**Why can't everyone talk at the same time in a Bluetooth Room?**

BLE L2CAP bandwidth cannot sustain multi-way full-duplex mixing. Rather than a choppy, uneven full-duplex experience, it is built as reliable Push-to-talk (PTT). See [Room Modes](Room-Modes.md).

**Why can't I hear others while holding Push-to-talk?**

By design — while Push-to-talk (PTT) is held, local playback is muted to prevent your own voice from looping back through the link as echo. Release the button to hear others.

**Why does the room expand directly from the button when I tap Create Room?**

The expanding area draws the actual room UI, not a transitional overlay that vanishes after playing. The home page and the room share the same sunset header motion and color scheme, so no page switch is needed when the animation ends, and no black frames or a second pop-in of the room page occur.

**Is the room gone once the Host leaves?**

Not in a Wi-Fi Room: using the handover snapshot the Host periodically broadcasts, the room automatically elects **the earliest-joined member who is still online** to take over and rebuild. The Host leaving voluntarily or losing connection can both trigger it. **Bluetooth Rooms do not support host transfer** — the room ends when the Host leaves. See [Host Transfer](Host-Transfer.md).

**Does it support dark mode? What about multiple languages?**

Both are supported. The color scheme has three settings — Follow system / Always light / Always dark — with the entry at the top-right of the home page header; tap to cycle, and the choice is remembered. Light is sunset warm tones, dark is the moon and the sea — both schemes share the same drawing code. UI text has Simplified Chinese and English variants and follows the system language; the strings live in `lib/l10n/app_strings.dart`. This is a Flutter project, so there is no `strings.xml`.

**Can it record? Can it send text?**

It can send text: open the message panel inside a room to exchange messages (protocol frames `FrameType.chat` / `chatSync` / `chatDelete`). Messages are kept in memory only and are cleared when you leave, with long-press recall supported. A single message is capped at 480 UTF-8 bytes; the protocol frame payload limit is 512 bytes. Recording and file transfer are not supported.

## Privacy

**Will voice be uploaded?**

No. There is no server to upload to. Audio travels only between devices with an established direct link, relayed by the Host.

**Is the call encrypted?**

**Plaintext by default.** The codebase includes an application-layer AES-256-GCM sealed-frame path (`SecureFrameCodec`), but it is only active when a `secureCodec` (a Dart object) is injected into the session; otherwise security relies on the underlying link.

If your use case has confidentiality requirements, evaluate it yourself — this project's design goal is "being able to talk without the internet", not "anti-eavesdropping".

**Does the room leave any records behind?**

No. No database, no persisted logs. Chat history lives in memory only and is cleared on your device when you leave.

## Build-Related

**What toolchain is required?**

The Flutter SDK (see `environment` in `pubspec.yaml`); Android release builds also need JDK 17 and the Android SDK. Dependencies are fetched with `flutter pub get`. Common commands: `flutter pub get` / `flutter test` / `flutter analyze` / `flutter run` / `flutter build apk --release`. For the complete list, see [Build and Release](Build-and-Release.md).

**What if dependency downloads fail?**

Re-run `flutter pub get` first; if the network is restricted, configure a mirror or proxy for pub / Git. If Android Gradle dependencies fail to download, handle Gradle's proxy or mirror settings separately.

**Why not compile native libopus with the NDK?**

Android uses Concentus 1.0.2, a pure-JVM Opus implementation declared in `android/app/build.gradle.kts`. The cost: the codec runs on the JVM with slightly higher CPU overhead. The benefit: the build does not depend on the NDK, and the artifacts contain no `.so` files. For the scale of 16 kHz mono 20 ms frames, the CPU overhead is entirely acceptable.

**Is there Opus on iOS?**

Not yet. The iOS audio channel sends and receives raw PCM and has no Opus codec integrated — a known cross-platform gap. The Android side uses Opus throughout.

**Why can't I install even after changing `versionCode`?**

Most likely the signature differs. Android identifies the app's origin by its signing certificate; packages signed with a different key cannot install over the existing one. The debug and release builds installed during development also use two different signatures — uninstall first.

**How is the release signed?**

Release signing is read from `android/key.properties` (that file is not committed). When it is missing or incomplete, `flutter build apk --release` falls back to debug signing — fine for self-testing, but not publishable. See the comments in `android/app/build.gradle.kts` for the field format.

**Do the tests need an emulator?**

No. All tests are pure Dart unit and widget tests, runnable directly with `flutter test` — currently 144/144 passing — with no emulator required.

## Project

**Can it be used in production?**

It is currently at the `0.1.0-alpha.13` testing stage. The core paths (Wi-Fi LAN/hotspot/direct full-duplex, Bluetooth PTT, in-room text messages, disconnect reconnection, Wi-Fi host handover) all work and are covered by automated tests. Note that iOS has no Opus codec yet, and Bluetooth Rooms support neither host transfer nor automatic reconnection. It is recommended as a near-field emergency intercom and as a learning reference.

**What is the license?**

[Apache License 2.0](../../../LICENSE). Free to use, modify, distribute, and commercialize, with an explicit patent grant; it requires keeping the copyright notice and stating changes.

**What does the project name mean?**

The sun has already set, yet the ripple on the sea has not faded. Some sounds do not travel over the network and leave no server behind — they can only be heard while you are still close enough to one another.

## Related Pages

- [Troubleshooting](Troubleshooting.md) · [Build and Release](Build-and-Release.md) · [Home](Home.md)
