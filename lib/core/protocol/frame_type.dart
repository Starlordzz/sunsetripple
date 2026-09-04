/// 11 supported binary frame types in SunsetRipple protocol.
enum FrameType {
  audio(0x01),
  joinReq(0x02),
  roster(0x03),
  pttState(0x04),
  heartbeat(0x05),
  leave(0x06),
  hostHandover(0x07),
  hostAnnounce(0x08),
  handshakeHello(0x09),
  handshakeConfirm(0x0a),
  sealed(0x0b),
  chat(0x0c);

  final int value;
  const FrameType(this.value);

  static FrameType? fromValue(int value) {
    for (final type in FrameType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}
