import 'dart:typed_data';

/// PTT_STATE (0x04) Payload
/// Format: [1 byte state] (0x01: pressed / speaking, 0x00: released)
class PttStatePayload {
  final bool isPressed;

  PttStatePayload({required this.isPressed});

  Uint8List encode() => Uint8List.fromList([isPressed ? 1 : 0]);

  static PttStatePayload? decode(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    return PttStatePayload(isPressed: bytes[0] != 0);
  }
}
