import 'dart:typed_data';

/// LEAVE (0x06) Payload
/// Format: [1 byte reason code] (0: normal leave, 1: timeout, 2: kicked)
class LeavePayload {
  final int reason;

  LeavePayload({this.reason = 0});

  Uint8List encode() => Uint8List.fromList([reason]);

  static LeavePayload? decode(Uint8List bytes) {
    if (bytes.isEmpty) return LeavePayload();
    return LeavePayload(reason: bytes[0]);
  }
}
