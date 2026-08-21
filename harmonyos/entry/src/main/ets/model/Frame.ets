/**
 * 跨端二进制帧协议（与 Android / iOS 保持 1:1 字节序一致）
 * [类型 1B][发送者ID 1B][序号 2B][长度 2B][负载 ≤512B]
 */
export enum FrameType {
  AUDIO = 1,
  JOIN = 2,
  ROSTER = 3,
  PTT_STATE = 4,
  PING = 5,
  LEAVE = 6,
  HOST_TRANSFER = 7,
  HOST_SNAPSHOT = 8,
  HANDSHAKE_HELLO = 9,
  HANDSHAKE_CONFIRM = 10,
  SEALED = 11
}

export class Frame {
  public static readonly HEADER_SIZE: number = 6;
  public static readonly MAX_PAYLOAD: number = 512;

  public type: FrameType;
  public senderId: number;
  public seq: number;
  public payload: Uint8Array;

  constructor(type: FrameType, senderId: number, seq: number, payload: Uint8Array) {
    this.type = type;
    this.senderId = senderId & 0xFF;
    this.seq = seq & 0xFFFF;
    this.payload = payload;
  }

  encode(): Uint8Array {
    const totalLen = Frame.HEADER_SIZE + this.payload.length;
    const out = new Uint8Array(totalLen);
    out[0] = this.type;
    out[1] = this.senderId;
    out[2] = (this.seq >> 8) & 0xFF;
    out[3] = this.seq & 0xFF;
    out[4] = (this.payload.length >> 8) & 0xFF;
    out[5] = this.payload.length & 0xFF;
    out.set(this.payload, Frame.HEADER_SIZE);
    return out;
  }

  static decode(bytes: Uint8Array): Frame | null {
    if (bytes.length < Frame.HEADER_SIZE) return null;
    const type = bytes[0] as FrameType;
    const senderId = bytes[1];
    const seq = ((bytes[2] & 0xFF) << 8) | (bytes[3] & 0xFF);
    const len = ((bytes[4] & 0xFF) << 8) | (bytes[5] & 0xFF);
    if (bytes.length < Frame.HEADER_SIZE + len) return null;
    const payload = bytes.subarray(Frame.HEADER_SIZE, Frame.HEADER_SIZE + len);
    return new Frame(type, senderId, seq, payload);
  }
}

