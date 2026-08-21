import Foundation

public enum FrameType: UInt8 {
    case audio = 1
    case join = 2
    case roster = 3
    case pttState = 4
    case ping = 5
    case leave = 6
    case hostTransfer = 7
    case hostSnapshot = 8
    case handshakeHello = 9
    case handshakeConfirm = 10
    case sealed = 11
}

public struct Frame {
    public static let headerSize: Int = 6
    public static let maxPayload: Int = 512

    public let type: FrameType
    public let senderId: UInt8
    public let seq: UInt16
    public let payload: Data

    public init(type: FrameType, senderId: UInt8, seq: UInt16, payload: Data) {
        self.type = type
        self.senderId = senderId
        self.seq = seq
        self.payload = payload
    }

    public func encode() -> Data {
        var data = Data(count: Frame.headerSize + payload.count)
        data[0] = type.rawValue
        data[1] = senderId
        data[2] = UInt8((seq >> 8) & 0xFF)
        data[3] = UInt8(seq & 0xFF)
        data[4] = UInt8((payload.count >> 8) & 0xFF)
        data[5] = UInt8(payload.count & 0xFF)
        data.replaceSubrange(Frame.headerSize..<(Frame.headerSize + payload.count), with: payload)
        return data
    }

    public static func decode(data: Data) -> Frame? {
        guard data.count >= Frame.headerSize else { return nil }
        guard let type = FrameType(rawValue: data[0]) else { return nil }
        let senderId = data[1]
        let seq = (UInt16(data[2]) << 8) | UInt16(data[3])
        let len = (Int(data[4]) << 8) | Int(data[5])
        guard data.count >= Frame.headerSize + len else { return nil }
        let payload = data.subdata(in: Frame.headerSize..<(Frame.headerSize + len))
        return Frame(type: type, senderId: senderId, seq: seq, payload: payload)
    }
}

