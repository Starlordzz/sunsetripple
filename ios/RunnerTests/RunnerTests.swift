import XCTest
import SunsetOpus
@testable import Runner

class RunnerTests: XCTestCase {
    func testOpusRoundTripFitsProtocolFrame() throws {
        var error: Int32 = 0
        let encoder = try XCTUnwrap(opus_encoder_create(16000, 1, OPUS_APPLICATION_VOIP, &error))
        XCTAssertEqual(error, OPUS_OK)
        defer { opus_encoder_destroy(encoder) }
        let decoder = try XCTUnwrap(opus_decoder_create(16000, 1, &error))
        XCTAssertEqual(error, OPUS_OK)
        defer { opus_decoder_destroy(decoder) }
        let samples = (0..<320).map { Int16(8000 * sin(2 * .pi * 440 * Double($0) / 16000)) }
        var packet = [UInt8](repeating: 0, count: 512)
        let length = samples.withUnsafeBufferPointer { input -> Int32 in
            guard let inBase = input.baseAddress else { return -1 }
            return packet.withUnsafeMutableBufferPointer { output -> Int32 in
                guard let outBase = output.baseAddress else { return -1 }
                return opus_encode(encoder, inBase, 320, outBase, 512)
            }
        }
        XCTAssertGreaterThan(length, 0)
        XCTAssertLessThanOrEqual(length, 512)
        var decoded = [Int16](repeating: 0, count: 320)
        let count = packet.withUnsafeBufferPointer { input -> Int32 in
            decoded.withUnsafeMutableBufferPointer { output -> Int32 in
                guard let outBase = output.baseAddress else { return -1 }
                return opus_decode(decoder, input.baseAddress, length, outBase, 320, 0)
            }
        }
        XCTAssertEqual(count, 320)
        XCTAssertGreaterThan(decoded.reduce(0) { $0 + abs(Int($1)) }, 100000)

        var plc = [Int16](repeating: 0, count: 320)
        let plcCount = plc.withUnsafeMutableBufferPointer { output -> Int32 in
            guard let outBase = output.baseAddress else { return -1 }
            return opus_decode(decoder, nil, 0, outBase, 320, 0)
        }
        XCTAssertEqual(plcCount, 320)
    }

    func testJitterBufferReordersLostAndWrapAround() {
        let jb = IosJitterBuffer()
        jb.put(seq16: 65535, payload: [2])
        XCTAssertEqual(jb.poll(), .notReady)
        jb.put(seq16: 65534, payload: [1])
        XCTAssertEqual(jb.poll(), .notReady)
        jb.put(seq16: 1, payload: [4])

        XCTAssertEqual(jb.poll(), .packet([1]))
        XCTAssertEqual(jb.poll(), .packet([2]))
        XCTAssertEqual(jb.poll(), .lost)
        XCTAssertEqual(jb.poll(), .packet([4]))
        XCTAssertEqual(jb.poll(), .notReady)
    }
}
