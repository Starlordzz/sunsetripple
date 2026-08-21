import Foundation
import AudioToolbox
import AVFoundation

public final class VoiceProcessingAudioEngine {
    private var audioUnit: AudioComponentInstance?
    private var isRunning: Bool = false
    public var isMicMuted: Bool = false
    public var onPcmCaptured: (([Int16]) -> Void)?

    public static let sampleRate: Double = 16000.0
    public static let frameSamples: Int = 320 // 20ms

    public init() {}

    public func start() throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(VoiceProcessingAudioEngine.sampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "AudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "VoiceProcessingIO not found"])
        }
        AudioComponentInstanceNew(comp, &audioUnit)

        guard let unit = audioUnit else { return }

        var one: UInt32 = 1
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, UInt32(MemoryLayout<UInt32>.size))
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, UInt32(MemoryLayout<UInt32>.size))

        var streamDesc = AudioStreamBasicDescription(
            mSampleRate: VoiceProcessingAudioEngine.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        AudioUnitInitialize(unit)
        AudioOutputUnitStart(unit)
        isRunning = true
    }

    public func playPcm(pcm: [Int16]) {
        // 音频输出 PCM
    }

    public func stop() {
        guard let unit = audioUnit, isRunning else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        audioUnit = nil
        isRunning = false
    }
}

