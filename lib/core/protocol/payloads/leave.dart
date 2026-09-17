import 'dart:typed_data';

/// LEAVE (0x06) Payload
/// Format: [1 byte reason code] (0: normal leave, 1: timeout, 2: kicked)
class LeavePayload {
  final int reason;

  LeavePayload({this.reason = 0});

  Uint8List encode() {
    if (reason < 0 || reason > 2) {
      throw ArgumentError('leave reason must be 0, 1, or 2.');
    }
    return Uint8List.fromList([reason]);
  }

  static LeavePayload? decode(Uint8List bytes) {
    if (bytes.length != 1 || bytes[0] > 2) return null;
    return LeavePayload(reason: bytes[0]);
  }
}
