> 🌐 [简体中文](../协议规范.md) | English
# Protocol Specification

The current Flutter implementation uses protocol version 2. This document describes
only the byte formats used by `lib/core/protocol/` and `lib/core/session/`; the old
`app/` Kotlin project is not part of the current protocol implementation.

## Frame Format

Every link shares the same frame structure. All multi-byte integers are **big-endian** (BE).

```
 0        1        2        3        4        5        6
 +--------+--------+--------+--------+--------+--------+-------------//
 |  type  |senderId|      seq        |   payloadLen    |   payload
 +--------+--------+--------+--------+--------+--------+-------------//
   1 byte   1 byte       2 bytes BE          2 bytes BE       0..512 bytes
```

| Field | Width | Value | Notes |
| --- | --- | --- | --- |
| `type` | 1 B | 1..14 | Frame type, see the table below |
| `senderId` | 1 B | 0..255 | Sender member ID; the host is `1` |
| `seq` | 2 B BE | 0..65535 | Sequence number, wraps via `& 0xFFFF` |
| `payloadLen` | 2 B BE | 0..512 | Payload length |
| `payload` | variable | — | See each type's encoding |

Constants: `HEADER_SIZE = 6`, `MAX_PAYLOAD = 512`.

Constructing a frame with a payload over 512 bytes throws `ArgumentError`.
`Frame.decode` returns `null` for an unknown type, an out-of-range length, or a
length that does not match the actual bytes; the caller drops the frame.

## Frame Types

The `FrameType` enum in `lib/core/protocol/frame_type.dart`:

```dart
enum FrameType {
  audio(0x01), joinReq(0x02), roster(0x03), pttState(0x04),
  heartbeat(0x05), leave(0x06), hostHandover(0x07), hostAnnounce(0x08),
  handshakeHello(0x09), handshakeConfirm(0x0a), sealed(0x0b),
  chat(0x0c), chatSync(0x0d), chatDelete(0x0e);
}
```

| ID | Type | Direction | Payload | Notes |
| --- | --- | --- | --- | --- |
| 1 (`0x01`) | `audio` | both | Opus frame | Voice |
| 2 (`0x02`) | `joinReq` | client → host | nickname + session token | Join request / reconnect identity |
| 3 (`0x03`) | `roster` | host → each member | personalized roster | Member list snapshot |
| 4 (`0x04`) | `pttState` | both | 1-byte boolean | PTT state toggle |
| 5 (`0x05`) | `heartbeat` | both | empty | Liveness heartbeat |
| 6 (`0x06`) | `leave` | both | 1-byte reason | Leave notice |
| 7 (`0x07`) | `hostHandover` | host → each member | transfer plan | Execute host transfer now |
| 8 (`0x08`) | `hostAnnounce` | host → each member | same transfer plan | Failover snapshot, cached only |
| 9 (`0x09`) | `handshakeHello` | client ⇄ host | ECDH/ECDSA hello | End-to-end handshake (optional) |
| 10 (`0x0a`) | `handshakeConfirm` | client ⇄ host | negotiated signature | End-to-end handshake confirm (optional) |
| 11 (`0x0b`) | `sealed` | both | AES-GCM envelope | Encrypted control/media envelope |
| 12 (`0x0c`) | `chat` | both | version + timestamp + code + text | In-room text chat |
| 13 (`0x0d`) | `chatSync` | host → unicast/broadcast | history entry | Backfill history to a new member |
| 14 (`0x0e`) | `chatDelete` | both | author code + message ID | Recall/delete a message |

## Framing

TCP is a byte stream; `_FrameAccumulator` inside
`lib/core/transport/lan_transport.dart` splits it by the frame header's length field.
Frames are self-delimiting, so no extra length prefix is needed. Half-frames that
span callbacks are held in the native C++ lock-free ring buffer (`NativeRingBuffer`);
when the native library is unavailable it falls back to a pure-Dart buffer with
identical semantics. An out-of-range payload length is treated as stream desync and
the whole buffer is dropped.

UDP (Wi-Fi audio) and BLE L2CAP (one native event per frame) are naturally delimited —
one datagram / one payload is exactly one frame, handed straight to `Frame.decode`.

## Payload Encodings

### JOIN (`0x02`)

Joining and **reconnect identity recovery** share this frame; there is only the current format:

```
[nicknameLen 1B][nickname UTF-8 1..64B][sessionToken 16B]
```

- `sessionToken` — 16 bytes, must contain at least one non-zero byte. **On reconnect the same token restores the original member ID and join order**; a mismatched token cannot claim a reserved slot. An all-zero placeholder is rejected.
- `nickname` — UTF-8, 1..64 bytes.
- `endpoint` is not in the JOIN payload; the transport layer maintains it from the actual connection. It is only used for host transfer.

Decoding rejects: a token shorter than 16 bytes, an all-zero token, an out-of-range or
zero nickname length, invalid UTF-8, and trailing bytes.

### ROSTER (`0x03`)

```
[hostId 1B][memberCount 1B]
  repeated memberCount times:
    [memberId 1B][flags 1B][nickLen 1B][nick UTF-8]
```

- `hostId` — the host's member ID. The frame is still **unicast** per member: the host
  delivers it over each connection, and a client only accepts a roster whose
  `frame.senderId == hostId`.
- `flags` bits: `0x01` = host, `0x02` = muted, `0x04` = speaking.
- Nicknames are UTF-8, at most `maxNicknameBytes = 64` bytes; the whole roster is at
  most `512` bytes and at most `6` members.
- Generated by `RosterPayload.encode()`; invalid fields (zero hostId, duplicate members,
  missing/multiple host flags, over-limit) throw `ArgumentError`, and
  `RosterPayload.decode()` returns `null`.

### PTT_STATE (`0x04`)

Exactly 1 byte: `0` = released, `1` = pressed. Any other length or value is rejected.
Used only by PTT rooms.

### HEARTBEAT (`0x05`)

Empty payload. Members send it every **2 seconds** to refresh their liveness. The host
removes a member and re-broadcasts the roster after **10 seconds** without any frame.

### LEAVE (`0x06`)

Exactly 1 byte: `0` = normal, `1` = timeout, `2` = kicked. Empty payloads and any other
length/value are rejected.

### HOST_HANDOVER (`0x07`) / HOST_ANNOUNCE (`0x08`)

Both have the same structure; only the semantics differ: `HOST_HANDOVER` means
"execute the transfer now", `HOST_ANNOUNCE` means "keep this and follow it if I die".

```
[version=2 1B][successorId 1B][memberCount 1B]
  repeated memberCount times:
    [memberId 1B][joinOrder 8B BE][nickLen 1B][nick UTF-8][endpointLen 1B][endpoint ASCII][sessionToken 16B]
```

Only v2 is sent and accepted. Every member must carry a unique, non-all-zero 16-byte
`sessionToken`, which the new host uses to restore identities; a plan that fails this is
rejected outright.

Decoding rejects: a version other than `2`, a member count outside `1..6`, a non-ASCII
endpoint, invalid UTF-8, an incomplete token, and trailing bytes. See
[Host Transfer](Host-Transfer.md).

### HANDSHAKE_HELLO (`0x09`) / HANDSHAKE_CONFIRM (`0x0a`) / SEALED (`0x0b`)

Reserved frames for the end-to-end security layer (`lib/core/security/`). The default
product configuration is plaintext with `RoomSession.secureCodec == null`; once a
`SecureFrameCodec` is injected, `sendFrame` wraps ordinary control/media frames in a
`SEALED` frame.

- `SEALED` payload: `[nonce 12B][ciphertext + tag]`. Associated data binds
  `(type=0x0b, senderId, seq, protocolVersion=1)`. Max payload:
  `512 - 6 - 12 - 16 = 478` bytes.
- The handshake verifies the peer with P-256 ECDSA signatures (DER) and derives the
  session key.

### CHAT (`0x0c`)

Encoded by `ChatMessagePayload`. Pure in-memory, zero-server short-text messaging among
the online members of the same room.

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| Version(1B) |       Timestamp (8B, Big-Endian) ...            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| SenderCode (4B ASCII) | TextLength (2B, Big-Endian)           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                   UTF-8 Encoded Text Bytes...                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

| Field | Width | Constraints |
| --- | --- | --- |
| `version` | 1 B | Fixed at `0x02`; non-2 frames are dropped |
| `timestamp` | 8 B BE | Unix milliseconds |
| `senderCode` | 4 B ASCII | Sender device code, space-padded when shorter than 4 bytes |
| `textLength` | 2 B BE | UTF-8 byte count of the following text, `1..368` |
| `textBytes` | variable | UTF-8 text; empty/whitespace-only rejected, at most 368 bytes (shared budget with chatSync, see below) |

- **Channel isolation**: in Wi-Fi rooms CHAT frames take the TCP 8988 control channel and
  host relay and **never** enter the UDP 8989 audio port; Bluetooth rooms use the L2CAP channel.
- **Encryption**: plaintext by default; with `secureCodec` injected, `sendFrame` seals
  them as `FrameType.sealed (0x0b)`.
- **Session policy**: each side deduplicates on `(senderId, seq)` with a bounded LRU;
  the last 100 messages are kept in memory and dropped on leaving the room — never persisted.

### CHAT_SYNC (`0x0d`)

Used by the host to backfill history to a newly joined member; encoded by `ChatSyncPayload`:

```
[targetMemberId 1B][senderId 1B][senderCode 4B ASCII][timestamp 8B BE]
[msgIdLen 1B][messageId UTF-8][nickLen 1B][nickname UTF-8]
[textLen 2B BE][text UTF-8]
```

- `targetMemberId == 0` means broadcast; otherwise it is sent only to that member. The
  receiver verifies the actual sender is the host, preventing forged history.
- `messageId`/`nickname` are at most 64 bytes; the whole frame still obeys the 512-byte limit.

### CHAT_DELETE (`0x0e`)

Recalls a message; encoded by `ChatDeletePayload`:

```
[version=1 1B][senderCode 4B ASCII][msgIdLen 1B][messageId UTF-8]
```

- `version` is fixed at `0x01`.
- Authorization does not trust the payload's `senderCode` (anyone can fill it). It uses
  the **actual frame sender's** device code from the roster and compares it against the
  target message's author before deleting.

## Transport Differences

### Wi-Fi (LAN / hotspot / Wi-Fi Direct)

| Item | Value |
| --- | --- |
| Signaling port | TCP `8988` |
| Audio port | UDP `8989` |
| Discovery broadcast | UDP `8990` (magic `SUNSET_RIPPLE_DISCOVERY_V1`) |
| Wi-Fi Direct GO address | `192.168.49.1` (fixed Android P2P group owner) |
| Host member ID | `1` |
| Max members | 6 (host + 5 clients) |
| JOIN timeout | 5000 ms (first frame must be JOIN) |
| Client connect timeout | 4000 ms |
| UDP heartbeat | 2000 ms |

Signaling (JOIN / ROSTER / HEARTBEAT / LEAVE / chat / HOST_*) goes over TCP, audio over
UDP. A client sends its AUDIO datagrams to the host, which relays them to the rest:
control frames are broadcast via `_relayControl` (JOIN is not broadcast), and audio
frames are forwarded via `_relayAudio` to every registered endpoint except the sender.

### Bluetooth BLE L2CAP

| Item | Value |
| --- | --- |
| Channel | BLE L2CAP CoC (connection-oriented channel) |
| PSM | Allocated dynamically by the system when the host starts listening, published via BLE advertising manufacturer data; clients read it and connect |
| Platform channels | `host.msknet.sunsetripple/ble_l2cap` (method) / `.../ble_l2cap_data`, `.../ble_l2cap_scan` (events) |
| Scan result TTL | 6 seconds |

There is a single reliable stream shared by signaling and audio. In the star topology,
frame forwarding happens natively: the host distributes `sendL2capData` to the other
members. Host transfer is not supported (it would require rebuilding the PSM and advertising).

### Platform Matrix

| Platform | Wi-Fi data plane | BLE L2CAP data plane |
| --- | --- | --- |
| Android | ✅ TCP + UDP | ✅ native plugin |
| iOS | ⚠️ LAN TCP only; UDP audio not wired | ⚠️ The plugin already does length-prefixed reassembly and host forwarding, but outbound is not MTU-fragmented, forwarding loses the original sender identity, and it is not device-validated |
| HarmonyOS | ❌ UDP discovery only | ❌ not connected |

## Reconnect

`ReconnectController` uses the backoff sequence `[1000, 2000, 4000]` ms; after three
failures it invokes `onMaxRetriesReached` (the session enters `disconnected`). On link
recovery or receiving a roster, call `cancel()` to reset.

After a member drops, the host releases the slot when the **10-second** heartbeat timeout
fires (`pruneStaleMembers`); a member that reconnects within that window with the same
`sessionToken` restores its original ID and join order. There is no separate transfer-grace
constant in the current implementation.

## Related Pages

- [Architecture Overview](Architecture-Overview.md) · [Host Transfer](Host-Transfer.md) · [Room Modes](Room-Modes.md)
