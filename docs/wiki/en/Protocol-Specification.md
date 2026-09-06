> 🌐 English | [简体中文](../协议规范.md)

# Protocol Specification

Version 1. Defined by the codec objects under `app/src/main/kotlin/host/msknet/sunsetripple/protocol/` and in `transport/`, `session/`.

## Frame Format

All links share the same frame structure; multi-byte integers are always **big-endian** (BE).

```
 0        1        2        3        4        5        6
 +--------+--------+--------+--------+--------+--------+-------------//
 |  type  |senderId|      seq        |   payloadLen    |   payload
 +--------+--------+--------+--------+--------+--------+-------------//
   1 byte   1 byte       2 bytes BE        2 bytes BE      0..512 bytes
```

| Field | Width | Values | Description |
| --- | --- | --- | --- |
| `type` | 1 B | 1..8 | Frame type; see the table below |
| `senderId` | 1 B | 0..255 | Sender's member ID; the Host is fixed at `0` |
| `seq` | 2 B BE | 0..65535 | Sequence number, wrapping around on overflow (`and 0xFFFF`) |
| `payloadLen` | 2 B BE | 0..512 | Payload length |
| `payload` | Variable | — | See each type's encoding |

Constants: `HEADER_SIZE = 6`, `MAX_PAYLOAD = 512`.

Building a frame with a payload larger than 512 bytes throws immediately; `FrameType.from(id)` throws `IllegalArgumentException("未知帧类型 $id")` on an unknown type.

## Frame Types

```kotlin
enum class FrameType(val id: Int) {
    AUDIO(1), JOIN(2), ROSTER(3), PTT_STATE(4),
    PING(5), LEAVE(6), HOST_TRANSFER(7), HOST_SNAPSHOT(8)
```dart
enum FrameType {
  audio(0x01), joinReq(0x02), roster(0x03), pttState(0x04),
  heartbeat(0x05), leave(0x06), hostHandover(0x07), hostAnnounce(0x08),
  handshakeHello(0x09), handshakeConfirm(0x0a), sealed(0x0b),
  chat(0x0c);
}
```

| ID | Type | Direction | Payload |
| --- | --- | --- | --- |
| 1 | `AUDIO` | Both ways | Opus-encoded frame |
| 2 | `JOIN` | Client → Host | Token + endpoint + nickname |
| 3 | `ROSTER` | Host → single client | Personalized roster |
| 4 | `PTT_STATE` | Both ways (Bluetooth only) | 1-byte boolean |
| 5 | `PING` | Client → Host | Empty |
| 6 | `LEAVE` | Both ways | Empty |
| 7 | `HOST_TRANSFER` | Host → each member | Transfer plan |
| 8 | `HOST_SNAPSHOT` | Host → each member | Same structure, as a disaster-recovery snapshot |
| ID (Hex) | Type | Direction | Payload | Description |
| --- | --- | --- | --- | --- |
| 1 (`0x01`) | `AUDIO` | Both ways | Opus-encoded frame | Voice packet |
| 2 (`0x02`) | `JOIN` | Client → Host | Token + endpoint + nickname | Room-join request |
| 3 (`0x03`) | `ROSTER` | Host → single client | Personalized roster | Member list snapshot |
| 4 (`0x04`) | `PTT_STATE` | Both ways (Bluetooth only) | 1-byte boolean | PTT state toggle |
| 5 (`0x05`) | `PING / HEARTBEAT` | Client → Host | Empty | Liveness heartbeat |
| 6 (`0x06`) | `LEAVE` | Both ways | Empty | Leave-room notification |
| 7 (`0x07`) | `HOST_TRANSFER` | Host → each member | Transfer plan | Host transfer |
| 8 (`0x08`) | `HOST_SNAPSHOT` | Host → each member | Same structure | Disaster-recovery snapshot |
| 9 (`0x09`) | `HANDSHAKE_HELLO` | Client ⇄ Host | ECDH negotiation hello | End-to-end encryption negotiation |
| 10 (`0x0a`) | `HANDSHAKE_CONFIRM`| Client ⇄ Host | Negotiation confirmation signature | End-to-end encryption handshake confirmation |
| 11 (`0x0b`) | `SEALED` | Both ways | AES-GCM ciphertext envelope | Encrypted control/media envelope |
| 12 (`0x0c`) | `CHAT` | Both ways | Version + text length + UTF-8 text | Near-field lightweight text chat |

## Framing

TCP and RFCOMM are byte streams and need `FrameStreamReader` to split them by length prefix. It is blocking and returns `null` on EOF or when `payloadLen > MAX_PAYLOAD`. Callers usually wrap it in `readFrameSafely()`, which turns protocol errors into `null` with the semantics "drop this peer; the rest of the room is unaffected".

UDP (Wi-Fi audio) and Nearby BYTES payloads are naturally delimited — one datagram / one payload is exactly one frame. The Nearby side additionally checks `bytes.size == HEADER_SIZE + payloadSize` and disconnects the endpoint on mismatch.

## Per-Type Payload Encoding

### JOIN

Joining and **identity recovery on reconnect** share this frame; it has two versions.

**v1:**
```
[0x01][token 16B][nickname UTF-8...]
```

**v2:**
```
[0x02][token 16B][endpointLen 1B][endpoint ASCII][nickname UTF-8...]
```

- `token` — a 16-byte `SecureRandom` value, stored by the host keyed by its lowercase hex form. **On reconnect, the same token restores the original member ID and join order**; with a mismatched token you cannot claim the reserved slot.
- `endpoint` — a stable reconnect/takeover identifier. In a Wi-Fi Room it is the P2P device address (with the anonymous placeholder `02:00:00:00:00:00` filtered out); in a Bluetooth Room (PTT) it is derived by the server from `connection.remoteAddress`, so `BluetoothClientTransport` only needs to send v1.
- `nickname` — UTF-8, truncated by the same rules as the roster.

Decoding rejects: a wrong version, a token shorter than 16 bytes, an oversized payload, invalid UTF-8. The token is defensively copied at decode time.

### ROSTER

```
[yourId 1B][memberCount 1B]
  repeat memberCount times:
    [id 1B][nickLen 1B][nick UTF-8][ipLen 1B][ip ASCII]
```

- Nicknames are truncated at **UTF-8 character boundaries** to `MAX_NICK_BYTES = 60`, never cutting a character in half.
- The roster is **personalized** — every receiver's `yourId` is different, so it must be unicast, never broadcast.
- Generated by `RosterFrames.encode(hostId, yourId, members)`; if the payload would overflow, it returns `null` and logs instead of throwing.
- The `ip` field means different things by room type: in a Wi-Fi Room it is an IP address; in a Bluetooth Room (PTT) the host fills in the literal `"host"` for itself while clients fill in their Bluetooth MAC; in a Nearby Room the host fills in `"host"` for itself.

### PTT_STATE

Exactly 1 byte: `0` = released, `1` = pressed. Any other value throws. Used only by the Bluetooth Room (PTT).

### PING

Empty payload. Sent by clients only, every 3 seconds (`PING_INTERVAL_MS = 3_000L`), to keep the host's read timeout alive.

### LEAVE

Empty payload. Sent when leaving the room voluntarily; when the host receives it, the member's slot is freed immediately.

### HOST_TRANSFER / HOST_SNAPSHOT

The two have exactly the same structure; the difference is semantic: `HOST_TRANSFER` means "execute the transfer now", while `HOST_SNAPSHOT` means "hold on to this — if I go down, follow it".

```
[version=1 1B][successorId 1B][memberCount 1B]
  repeat memberCount times:
    [memberId 1B][joinOrder 8B][nickLen 1B][nick UTF-8][endpointLen 1B][endpoint ASCII]
```

Decoding rejects: a version other than 1, a member count outside `1..6`, endpoints containing non-ASCII characters, invalid UTF-8, and stray trailing bytes. Plan validation additionally requires member IDs / endpoints / join orders to each be unique, the successor to be in the member list, and `successorId in 1..255`.

See [Host Transfer](Host-Transfer.md) for details.

### CHAT (Text Chat)

Frame type `0x0c`, encoded and decoded by `ChatMessagePayload`. Used for pure in-memory, zero-server short-text messaging between online members of the same room.

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Version(1B)  |       TextLength (2B, Big-Endian)             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                   UTF-8 Encoded Text Bytes...                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

| Field | Width | Constraints and description |
| --- | --- | --- |
| `version` | 1 B | Fixed at `0x01`; frames with any other value are dropped |
| `textLength` | 2 B BE | Actual UTF-8 byte count of the text that follows, range `1..480` |
| `textBytes` | Variable | UTF-8 encoded text; empty and whitespace-only text is rejected, and it must not exceed 480 bytes |

- **Security boundary**: the total payload is at most 483 bytes, strictly below the 512-byte frame limit, so nothing gets truncated underneath.
- **Channel isolation**: in a Wi-Fi Room, CHAT frames travel over the TCP 8988 control channel with the host relaying, and **never** enter the UDP 8989 audio port; in a Bluetooth Room (PTT) they travel over the L2CAP channel.
- **Encryption behavior**: plaintext by default; when a `secureCodec` is injected, `sendFrame` wraps them automatically as `FrameType.sealed (0x0b)`.
- **Session policy**: each end performs bounded LRU deduplication keyed on `(senderId, seq)`; memory keeps the latest 100 messages, everything is cleared on leaving the room, and nothing is written to disk.

## Transport Layer Differences

### Wi-Fi Direct

| Item | Value |
| --- | --- |
| Signaling port | TCP `8988` |
| Audio port | UDP `8989` |
| Host IP | `192.168.49.1` (the fixed group-owner address in Android Wi-Fi Direct) |
| Host member ID | `0` |
| Max members | 6 |
| UDP buffer | 2048 B |
| Handshake timeout | 5000 ms (the first frame must be JOIN) |
| Read timeout | 10000 ms |
| Client connect timeout | 5000 ms |
| Reconnect grace | 7000 ms |

Signaling (JOIN / ROSTER / PING / LEAVE / HOST_TRANSFER / HOST_SNAPSHOT) goes over TCP; audio goes over UDP.

**Audio is sent mesh-direct, not relayed through the host** — a client sends AUDIO datagrams to every member IP in the roster except itself; the group owner is just an ordinary participant.

On both sides, `broadcast()` uses `require` to reject HOST_TRANSFER and HOST_SNAPSHOT, because these two frame types must be directed unicasts.

### Bluetooth RFCOMM

| Item | Value |
| --- | --- |
| Service UUID | `7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b003` |
| Service name | `SunsetRipple Bluetooth Room` |
| Security mode | Secure by default; insecure mode when rebuilt after a host transfer |
| Discoverable duration | 300 seconds |

There is a single reliable stream shared by signaling and audio. Under the star topology: `sendTo(memberId, frame)` sends AUDIO to a specific member, and `broadcastSignal(frame)` sends everything else (using `require` to reject AUDIO / HOST_TRANSFER / HOST_SNAPSHOT).

**The host rewrites the sender identity**: a received frame is re-wrapped as `Frame(frame.type, client.id, frame.seq, frame.payload)`; a client-reported `senderId` is not trusted.

### Nearby Connections

`Strategy.P2P_CLUSTER`, `SERVICE_ID = "host.msknet.sunsetripple"`, one frame per `Payload.Type.BYTES`. A client initiates connections only to peers with `member.id > selfId`, avoiding duplicate links in both directions.

## Reconnect

`ReconnectPolicy` backs off through the sequence `[1000, 2000, 4000]` ms; after the third attempt, `nextDelayMs()` returns `null`, meaning give up. `reset()` is called when a roster arrives or the link recovers.

The host keeps a disconnected member's slot reserved for 7 seconds (`RECONNECT_GRACE_MS`); after a host transfer, the successor keeps slots reserved for members who have not reconnected for the same 7 seconds (`TRANSFER_RESERVATION_GRACE_MS`), releasing them when the window expires so room capacity is not occupied forever.

## Related Pages

- [Architecture Overview](Architecture-Overview.md) · [Host Transfer](Host-Transfer.md) · [Room Modes](Room-Modes.md)
