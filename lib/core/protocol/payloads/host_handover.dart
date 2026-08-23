import 'dart:typed_data';

/// HOST_HANDOVER (0x07) Payload
/// Format: [1 byte target new host memberId][2 bytes handover epoch]
class HostHandoverPayload {
  final int newHostId;
  final int epoch;

  HostHandoverPayload({
    required this.newHostId,
    required this.epoch,
  });

  Uint8List encode() {
    final buffer = Uint8List(3);
    final bd = ByteData.sublistView(buffer);
    bd.setUint8(0, newHostId);
    bd.setUint16(1, epoch, Endian.big);
    return buffer;
  }

  static HostHandoverPayload? decode(Uint8List bytes) {
    if (bytes.length < 3) return null;
    final bd = ByteData.sublistView(bytes);
    return HostHandoverPayload(
      newHostId: bd.getUint8(0),
      epoch: bd.getUint16(1, Endian.big),
    );
  }
}

/// HOST_ANNOUNCE (0x08) Payload
/// Format: [1 byte current host memberId][2 bytes current epoch]
class HostAnnouncePayload {
  final int hostId;
  final int epoch;

  HostAnnouncePayload({
    required this.hostId,
    required this.epoch,
  });

  Uint8List encode() {
    final buffer = Uint8List(3);
    final bd = ByteData.sublistView(buffer);
    bd.setUint8(0, hostId);
    bd.setUint16(1, epoch, Endian.big);
    return buffer;
  }

  static HostAnnouncePayload? decode(Uint8List bytes) {
    if (bytes.length < 3) return null;
    final bd = ByteData.sublistView(bytes);
    return HostAnnouncePayload(
      hostId: bd.getUint8(0),
      epoch: bd.getUint16(1, Endian.big),
    );
  }
}
