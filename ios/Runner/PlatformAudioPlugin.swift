import Flutter
import UIKit
import AVFoundation
import AudioToolbox

public final class PlatformAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private static let methodChannelName = "host.msknet.sunsetripple/audio"
    private static let eventChannelName = "host.msknet.sunsetripple/audio_events"

    public static let sampleRate: Double = 16000.0
    public static let frameSamples: Int = 320 // 20ms @ 16kHz
    public static let bytesPerFrame: Int = frameSamples * 2 // 640 bytes

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private var audioUnit: AudioComponentInstance?
    private var isCapturing: Bool = false
    private var isMuted: Bool = false
    private var userWantsSpeaker: Bool = true
    private var preferBuiltinMic: Bool = false
    private var currentBitrate: Int = 24000

    // 远端音频流混音队列（按发送方 ID 分流）
    private let playbackLock = NSLock()
    private var remoteQueues: [Int: [[Int16]]] = [:]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PlatformAudioPlugin()
        instance.setupChannels(messenger: registrar.messenger())
    }

    public func setupChannels(messenger: FlutterBinaryMessenger) {
        let mChannel = FlutterMethodChannel(name: PlatformAudioPlugin.methodChannelName, binaryMessenger: messenger)
        mChannel.setMethodCallHandler(self.handle)
        self.methodChannel = mChannel

        let eChannel = FlutterEventChannel(name: PlatformAudioPlugin.eventChannelName, binaryMessenger: messenger)
        eChannel.setStreamHandler(self)
        self.eventChannel = eChannel
    }

    public func detachChannels() {
        stopAudioEngine()
        methodChannel?.setMethodCallHandler(nil)
        methodChannel = nil
        eventChannel?.setStreamHandler(nil)
        eventChannel = nil
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - FlutterMethodCallHandler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCapture":
            let args = call.arguments as? [String: Any]
            currentBitrate = args?["bitrate"] as? Int ?? 24000
            checkMicrophonePermission { [weak self] granted in
                guard let self = self else { return }
                if !granted {
                    result(FlutterError(code: "PERMISSION_DENIED", message: "缺少麦克风权限，无法开启语音对讲", details: nil))
                    return
                }
                do {
                    try self.startAudioEngine()
                    result(nil)
                } catch {
                    result(FlutterError(code: "AUDIO_INIT_FAILED", message: "音频引擎初始化失败: \(error.localizedDescription)", details: nil))
                }
            }

        case "stopCapture":
            stopAudioEngine()
            result(nil)

        case "setMuted":
            if let args = call.arguments as? [String: Any], let muted = args["muted"] as? Bool {
                isMuted = muted
            }
            result(nil)

        case "setSpeakerphone":
            if let args = call.arguments as? [String: Any], let enabled = args["enabled"] as? Bool {
                userWantsSpeaker = enabled
                updateAudioRouting()
            }
            result(nil)

        case "setUseBuiltinMic":
            if let args = call.arguments as? [String: Any], let useBuiltin = args["useBuiltinMic"] as? Bool {
                preferBuiltinMic = useBuiltin
                updateAudioRouting()
            }
            result(nil)

        case "setBitrate":
            if let args = call.arguments as? [String: Any], let bitrate = args["bitrate"] as? Int {
                currentBitrate = bitrate
            }
            result(nil)

        case "submitRemoteFrame":
            if let args = call.arguments as? [String: Any],
               let typedData = args["data"] as? FlutterStandardTypedData {
                let data = typedData.data
                handleRemoteFrameData(data)
            }
            result(nil)

        case "dispose":
            detachChannels()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 权限检查

    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        @unknown default:
            completion(false)
        }
    }

    // MARK: - VoiceProcessingIO 音频引擎

    private func startAudioEngine() throws {
        guard !isCapturing else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setPreferredSampleRate(PlatformAudioPlugin.sampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "PlatformAudioPlugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "VoiceProcessingIO 未找到"])
        }

        var unit: AudioComponentInstance?
        let statusNew = AudioComponentInstanceNew(comp, &unit)
        guard statusNew == noErr, let audioUnit = unit else {
            throw NSError(domain: "PlatformAudioPlugin", code: Int(statusNew), userInfo: [NSLocalizedDescriptionKey: "创建 AudioUnit 失败: \(statusNew)"])
        }
        self.audioUnit = audioUnit

        // 启用 Input (录音: Element 1) 与 Output (播放: Element 0)
        var one: UInt32 = 1
        AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, UInt32(MemoryLayout<UInt32>.size))
        AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, UInt32(MemoryLayout<UInt32>.size))

        // 音频流格式定义：16kHz, 单声道, 16-bit 线性 PCM
        var streamDesc = AudioStreamBasicDescription(
            mSampleRate: PlatformAudioPlugin.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        // 录音输入回调
        var inputCallback = AURenderCallbackStruct(
            inputProc: audioInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &inputCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        // 播放渲染回调
        var renderCallback = AURenderCallbackStruct(
            inputProc: audioRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        AudioUnitInitialize(audioUnit)
        AudioOutputUnitStart(audioUnit)
        isCapturing = true

        updateAudioRouting()
    }

    private func stopAudioEngine() {
        guard let unit = audioUnit else { return }
        isCapturing = false
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.audioUnit = nil

        playbackLock.lock()
        remoteQueues.removeAll()
        playbackLock.unlock()
    }

    private func updateAudioRouting() {
        let session = AVAudioSession.sharedInstance()
        do {
            if userWantsSpeaker {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }

            if preferBuiltinMic {
                if let builtin = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try session.setPreferredInput(builtin)
                }
            } else {
                if let headset = session.availableInputs?.first(where: {
                    $0.portType == .headsetMic || $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP
                }) {
                    try session.setPreferredInput(headset)
                }
            }
        } catch {
            print("[SunsetAudio] 音频路由切换失败: \(error)")
        }
    }

    // MARK: - 远端数据入队与混音

    private func handleRemoteFrameData(_ data: Data) {
        guard data.count >= 6 else { return }
        // 帧头协议：前 4 字节为发送方 ID，后 2 字节为序号
        let senderId = Int(data[0]) | (Int(data[1]) << 8) | (Int(data[2]) << 16) | (Int(data[3]) << 24)
        let payload = data.subdata(in: 6..<data.count)

        // 解码 payload 为 16-bit PCM 采样
        var pcmSamples = [Int16](repeating: 0, count: PlatformAudioPlugin.frameSamples)
        let sampleBytes = min(payload.count, PlatformAudioPlugin.bytesPerFrame)
        payload.withUnsafeBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }
            let count = sampleBytes / 2
            let src = baseAddress.bindMemory(to: Int16.self, capacity: count)
            for i in 0..<min(count, PlatformAudioPlugin.frameSamples) {
                pcmSamples[i] = src[i]
            }
        }

        playbackLock.lock()
        if remoteQueues[senderId] == nil {
            remoteQueues[senderId] = []
        }
        remoteQueues[senderId]?.append(pcmSamples)
        // 抖动缓冲区保护：限制最多保留 10 帧 (200ms)，防止累积延迟
        if let count = remoteQueues[senderId]?.count, count > 10 {
            remoteQueues[senderId]?.removeFirst(count - 10)
        }
        playbackLock.unlock()
    }

    // MARK: - 音频回调处理 (C 函数)

    fileprivate func processCapturedPcm(samples: [Int16]) {
        guard isCapturing, !isMuted else { return }

        // 计算 RMS 能量与峰值音量 (0.0 ~ 1.0)
        var sumSquares: Double = 0
        for s in samples {
            let val = Double(s)
            sumSquares += val * val
        }
        let rms = sqrt(sumSquares / Double(samples.count))
        let level = min(1.0, max(0.0, rms / 32768.0 * 3.5))

        // 构造数据字节并上送给 Flutter
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            let dest = baseAddress.bindMemory(to: Int16.self, capacity: samples.count)
            for i in 0..<samples.count {
                dest[i] = samples[i]
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let sink = self.eventSink else { return }
            sink([
                "data": FlutterStandardTypedData(bytes: data),
                "level": level
            ])
        }
    }

    fileprivate func providePlaybackPcm(into buffer: UnsafeMutablePointer<Int16>, sampleCount: Int) {
        playbackLock.lock()
        defer { playbackLock.unlock() }

        if remoteQueues.isEmpty {
            buffer.initialize(repeating: 0, count: sampleCount)
            return
        }

        var mixed = [Int32](repeating: 0, count: sampleCount)
        var activeStreams = 0

        for (senderId, queue) in remoteQueues {
            guard !queue.isEmpty else { continue }
            let frame = queue.first!
            remoteQueues[senderId]?.removeFirst()
            activeStreams += 1

            let count = min(sampleCount, frame.count)
            for i in 0..<count {
                mixed[i] += Int32(frame[i])
            }
        }

        if activeStreams == 0 {
            buffer.initialize(repeating: 0, count: sampleCount)
            return
        }

        // 混音饱和截断（Saturation Clipping）
        for i in 0..<sampleCount {
            let val = mixed[i]
            if val > 32767 {
                buffer[i] = 32767
            } else if val < -32768 {
                buffer[i] = -32768
            } else {
                buffer[i] = Int16(val)
            }
        }
    }
}

// MARK: - AudioUnit 回调 C 桥接

private func audioInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let plugin = Unmanaged<PlatformAudioPlugin>.fromOpaque(inRefCon).takeUnretainedValue()

    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: inNumberFrames * 2,
            mData: nil
        )
    )

    let bufferSize = Int(inNumberFrames) * 2
    let dataPtr = malloc(bufferSize)
    defer { free(dataPtr) }
    bufferList.mBuffers.mData = dataPtr

    guard let unit = plugin.value(forKey: "audioUnit") as? AudioComponentInstance else {
        return noErr
    }

    let status = AudioUnitRender(
        unit,
        ioActionFlags,
        inTimeStamp,
        1,
        inNumberFrames,
        &bufferList
    )

    if status == noErr, let rawData = bufferList.mBuffers.mData {
        let sampleCount = Int(inNumberFrames)
        let ptr = rawData.bindMemory(to: Int16.self, capacity: sampleCount)
        var samples = [Int16](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            samples[i] = ptr[i]
        }
        plugin.processCapturedPcm(samples: samples)
    }

    return noErr
}

private func audioRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let plugin = Unmanaged<PlatformAudioPlugin>.fromOpaque(inRefCon).takeUnretainedValue()

    guard let bufferList = ioData else { return noErr }
    let buffer = bufferList.pointee.mBuffers
    guard let destPtr = buffer.mData?.bindMemory(to: Int16.self, capacity: Int(inNumberFrames)) else {
        return noErr
    }

    plugin.providePlaybackPcm(into: destPtr, sampleCount: Int(inNumberFrames))
    return noErr
}
