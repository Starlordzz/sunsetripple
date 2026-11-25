import Flutter
import UIKit
import AVFoundation
import AudioToolbox

enum IosPollResult: Equatable {
    case notReady
    case lost
    case packet([UInt8])
}

/// 16 位序号展开与乱序重排抖动缓冲，语义与 Android 端 `JitterBuffer` 对齐。
final class IosJitterBuffer {
    private let prebufferFrames: Int
    private let maxBuffer: Int
    private var buf: [Int64: [UInt8]] = [:]
    private var highestSeen: Int64 = -1
    private var nextSeq: Int64 = -1
    private var started: Bool = false

    init(prebufferFrames: Int = 3, maxBuffer: Int = 10) {
        self.prebufferFrames = prebufferFrames
        self.maxBuffer = maxBuffer
    }

    func put(seq16: Int, payload: [UInt8]) {
        let seq = unwrap(seq16)
        if started && seq < nextSeq { return }
        buf[seq] = payload
        while buf.count > maxBuffer, let oldest = buf.keys.min() {
            buf.removeValue(forKey: oldest)
        }
    }

    func poll() -> IosPollResult {
        if !started {
            guard buf.count >= prebufferFrames, let first = buf.keys.min() else {
                return .notReady
            }
            started = true
            nextSeq = first
        }
        guard !buf.isEmpty else { return .notReady }

        if let first = buf.keys.min(), first - nextSeq > Int64(maxBuffer) {
            nextSeq = first
        }

        let head = buf.removeValue(forKey: nextSeq)
        nextSeq += 1
        if let data = head {
            return .packet(data)
        }
        return .lost
    }

    func reset() {
        buf.removeAll()
        highestSeen = -1
        nextSeq = -1
        started = false
    }

    var hasStarted: Bool { started }
    var pendingCount: Int { buf.count }

    private func unwrap(_ seq16: Int) -> Int64 {
        let masked = seq16 & 0xFFFF
        if highestSeen < 0 {
            highestSeen = Int64(masked)
            return highestSeen
        }
        let low = Int(highestSeen & 0xFFFF)
        let delta = ((masked - low + 0x8000) & 0xFFFF) - 0x8000
        let v = highestSeen + Int64(delta)
        if v > highestSeen { highestSeen = v }
        return v
    }
}

public final class PlatformAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private static let methodChannelName = "host.msknet.sunsetripple/audio"
    private static let eventChannelName = "host.msknet.sunsetripple/audio_events"

    public static let sampleRate: Double = 16000.0
    public static let frameSamples: Int = 320 // 20ms @ 16kHz
    public static let bytesPerFrame: Int = frameSamples * 2 // 640 bytes

    private final class RemoteAudioStream {
        let decoder: OpaquePointer
        let jitter = IosJitterBuffer()
        var pcm: [Int16] = [Int16](repeating: 0, count: PlatformAudioPlugin.frameSamples)
        var pcmCount: Int = 0
        var pcmOffset: Int = 0

        init(decoder: OpaquePointer) {
            self.decoder = decoder
        }
    }

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    fileprivate var audioUnit: AudioComponentInstance?
    private var isCapturing: Bool = false
    private var isMuted: Bool = false
    private var isSessionActive: Bool = false
    private var userWantsSpeaker: Bool = true
    private var preferBuiltinMic: Bool = false
    private var currentBitrate: Int = 24000
    private let captureLock = NSLock()
    private var encoder: OpaquePointer?

    // CoreAudio 实时回调零分配暂存与异步编码环形缓冲
    private var inputScratchPtr: UnsafeMutablePointer<Int16>?
    private var inputScratchCapacity: Int = 0
    private let captureRingCapacity: Int = 16000
    private var captureRing: [Int16] = [Int16](repeating: 0, count: 16000)
    private var captureRingHead: Int = 0
    private var captureRingTail: Int = 0
    private var captureRingCount: Int = 0
    private var captureFrameScratch: [Int16] = [Int16](repeating: 0, count: frameSamples)
    private var encodePacketScratch: [UInt8] = [UInt8](repeating: 0, count: 512)
    private var captureGeneration: Int = 0
    private var activeCaptureSemaphore: DispatchSemaphore?

    // 远端音频流混音队列（按发送方 ID 分流，含 JitterBuffer + PLC）
    private let playbackLock = NSLock()
    private var remoteStreams: [Int: RemoteAudioStream] = [:]
    private var mixScratch: [Int32] = [Int32](repeating: 0, count: 4096)

    deinit {
        stopAudioEngine()
    }

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
                    self.stopAudioEngine()
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
                captureLock.lock()
                currentBitrate = bitrate
                if let encoder = encoder { _ = sunset_opus_set_bitrate(encoder, Int32(bitrate)) }
                captureLock.unlock()
            }
            result(nil)

        case "submitRemoteFrame":
            if let args = call.arguments as? [String: Any],
               let typedData = args["data"] as? FlutterStandardTypedData {
                let data = typedData.data
                handleRemoteFrameData(data)
            }
            result(nil)

        case "removeRemoteMember":
            if let args = call.arguments as? [String: Any], let memberId = args["memberId"] as? Int {
                playbackLock.lock()
                if let stream = remoteStreams.removeValue(forKey: memberId) {
                    opus_decoder_destroy(stream.decoder)
                }
                playbackLock.unlock()
            }
            result(nil)

        case "clearRemoteMembers":
            playbackLock.lock()
            clearRemoteAudioLocked()
            playbackLock.unlock()
            result(nil)

        case "stopPlayback":
            stopAudioEngine()
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

    private func checkStatus(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else {
            throw NSError(
                domain: "PlatformAudioPlugin",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "\(action) 失败: \(status)"]
            )
        }
    }

    private func startAudioEngine() throws {
        guard !isCapturing else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setPreferredSampleRate(PlatformAudioPlugin.sampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        isSessionActive = true

        var codecError: Int32 = 0
        guard let codec = opus_encoder_create(16000, 1, OPUS_APPLICATION_VOIP, &codecError), codecError == OPUS_OK else {
            throw NSError(domain: "Opus", code: Int(codecError), userInfo: nil)
        }

        captureLock.lock()
        encoder = codec
        captureRingHead = 0
        captureRingTail = 0
        captureRingCount = 0
        let bitrateStatus = sunset_opus_set_bitrate(codec, Int32(currentBitrate))
        captureLock.unlock()
        guard bitrateStatus == OPUS_OK else {
            throw NSError(domain: "Opus", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Opus bitrate"])
        }

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
        try checkStatus(
            AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, UInt32(MemoryLayout<UInt32>.size)),
            "启用 AudioUnit Input"
        )
        try checkStatus(
            AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, UInt32(MemoryLayout<UInt32>.size)),
            "启用 AudioUnit Output"
        )

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

        try checkStatus(
            AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
            "设置录音流格式"
        )
        try checkStatus(
            AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
            "设置播放流格式"
        )

        // 录音输入回调
        var inputCallback = AURenderCallbackStruct(
            inputProc: audioInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try checkStatus(
            AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &inputCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
            "设置录音回调"
        )

        // 播放渲染回调
        var renderCallback = AURenderCallbackStruct(
            inputProc: audioRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try checkStatus(
            AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
            "设置播放回调"
        )

        try checkStatus(AudioUnitInitialize(audioUnit), "初始化 AudioUnit")

        let preallocSamples = 4096
        inputScratchPtr = UnsafeMutablePointer<Int16>.allocate(capacity: preallocSamples)
        inputScratchCapacity = preallocSamples

        captureLock.lock()
        captureGeneration += 1
        let generation = captureGeneration
        let semaphore = DispatchSemaphore(value: 0)
        activeCaptureSemaphore = semaphore
        isCapturing = true
        captureLock.unlock()

        let worker = Thread { [weak self] in
            self?.runCaptureWorker(generation: generation, semaphore: semaphore)
        }
        worker.name = "sunset-ios-opus-capture"
        worker.qualityOfService = .userInteractive
        worker.start()

        do {
            try checkStatus(AudioOutputUnitStart(audioUnit), "启动 AudioUnit")
        } catch {
            stopAudioEngine()
            throw error
        }

        updateAudioRouting()
    }

    private func stopAudioEngine() {
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }

        if let scratch = inputScratchPtr {
            scratch.deallocate()
            inputScratchPtr = nil
            inputScratchCapacity = 0
        }

        captureLock.lock()
        isCapturing = false
        captureGeneration += 1
        if let encoder = encoder { opus_encoder_destroy(encoder) }
        encoder = nil
        captureRingHead = 0
        captureRingTail = 0
        captureRingCount = 0
        let pendingSemaphore = activeCaptureSemaphore
        activeCaptureSemaphore = nil
        captureLock.unlock()
        pendingSemaphore?.signal()

        playbackLock.lock()
        clearRemoteAudioLocked()
        playbackLock.unlock()

        if isSessionActive {
            isSessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func clearRemoteAudioLocked() {
        for stream in remoteStreams.values { opus_decoder_destroy(stream.decoder) }
        remoteStreams.removeAll()
    }

    private func updateAudioRouting() {
        let session = AVAudioSession.sharedInstance()
        do {
            let externalInput = session.availableInputs?.first(where: {
                $0.portType == .headsetMic || $0.portType == .bluetoothHFP || $0.portType == .usbAudio
            })
            let usingExternalInput = !preferBuiltinMic && externalInput != nil

            if preferBuiltinMic {
                if let builtin = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try session.setPreferredInput(builtin)
                }
            } else if let headset = externalInput {
                try session.setPreferredInput(headset)
            }

            let hasExternalOutput = session.currentRoute.outputs.contains(where: {
                $0.portType == .headphones ||
                $0.portType == .bluetoothHFP ||
                $0.portType == .bluetoothA2DP ||
                $0.portType == .bluetoothLE ||
                $0.portType == .usbAudio
            })

            if usingExternalInput || (preferBuiltinMic && hasExternalOutput) {
                try session.overrideOutputAudioPort(.none)
            } else if userWantsSpeaker {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
        } catch {
            print("[SunsetAudio] 音频路由切换失败: \(error)")
        }
    }

    // MARK: - 远端数据入队与混音

    private func handleRemoteFrameData(_ data: Data) {
        guard data.count >= 6 else { return }
        // 二进制帧协议：[0]=Type, [1]=SenderId, [2..3]=Seq(BigEndian), [4..5]=Len(BigEndian)
        let base = data.startIndex
        let frameType = data[base]
        let senderId = Int(data[base + 1])
        let seq = (Int(data[base + 2]) << 8) | Int(data[base + 3])
        let payloadLength = (Int(data[base + 4]) << 8) | Int(data[base + 5])
        guard frameType == 0x01, senderId > 0, payloadLength > 0,
              payloadLength <= 512, data.count == 6 + payloadLength else { return }

        let payloadStart = base + 6
        let payloadEnd = payloadStart + payloadLength
        let payloadBytes = Array(data[payloadStart..<payloadEnd])

        playbackLock.lock()
        defer { playbackLock.unlock() }
        if remoteStreams[senderId] == nil {
            var error: Int32 = 0
            guard let decoder = opus_decoder_create(16000, 1, &error), error == OPUS_OK else { return }
            remoteStreams[senderId] = RemoteAudioStream(decoder: decoder)
        }
        remoteStreams[senderId]?.jitter.put(seq16: seq, payload: payloadBytes)
    }

    // MARK: - 音频回调处理 (C 函数)

    fileprivate func renderScratchPointer(capacity: Int) -> UnsafeMutablePointer<Int16>? {
        guard capacity > 0 else { return nil }
        if capacity <= inputScratchCapacity, let ptr = inputScratchPtr {
            return ptr
        }
        inputScratchPtr?.deallocate()
        let allocated = UnsafeMutablePointer<Int16>.allocate(capacity: capacity)
        inputScratchPtr = allocated
        inputScratchCapacity = capacity
        return allocated
    }

    fileprivate func enqueueCapturedSamples(_ ptr: UnsafePointer<Int16>, count: Int) {
        guard count > 0 else { return }
        captureLock.lock()
        let active = isCapturing && !isMuted && encoder != nil
        var shouldSignal = false
        if active {
            let toWrite = min(count, captureRingCapacity)
            let startOffset = count - toWrite
            if captureRingCount + toWrite > captureRingCapacity {
                let overflow = captureRingCount + toWrite - captureRingCapacity
                captureRingTail = (captureRingTail + overflow) % captureRingCapacity
                captureRingCount -= overflow
            }
            for i in 0..<toWrite {
                captureRing[captureRingHead] = ptr[startOffset + i]
                captureRingHead = (captureRingHead + 1) % captureRingCapacity
            }
            captureRingCount += toWrite
            shouldSignal = captureRingCount >= PlatformAudioPlugin.frameSamples
        }
        let semaphore = activeCaptureSemaphore
        captureLock.unlock()

        if shouldSignal {
            semaphore?.signal()
        }
    }

    private func runCaptureWorker(generation: Int, semaphore: DispatchSemaphore) {
        while true {
            semaphore.wait()
            while true {
                var packetData: Data?
                var level = 0.0
                var hasMore = false

                captureLock.lock()
                if !isCapturing || captureGeneration != generation {
                    captureLock.unlock()
                    return
                }
                if isMuted {
                    captureRingHead = 0
                    captureRingTail = 0
                    captureRingCount = 0
                    captureLock.unlock()
                    break
                }
                guard captureRingCount >= PlatformAudioPlugin.frameSamples, let enc = encoder else {
                    captureLock.unlock()
                    break
                }

                for i in 0..<PlatformAudioPlugin.frameSamples {
                    captureFrameScratch[i] = captureRing[captureRingTail]
                    captureRingTail = (captureRingTail + 1) % captureRingCapacity
                }
                captureRingCount -= PlatformAudioPlugin.frameSamples
                hasMore = captureRingCount >= PlatformAudioPlugin.frameSamples

                let count = captureFrameScratch.withUnsafeBufferPointer { pcm in
                    encodePacketScratch.withUnsafeMutableBufferPointer { output in
                        opus_encode(enc, pcm.baseAddress, Int32(PlatformAudioPlugin.frameSamples),
                                    output.baseAddress, Int32(output.count))
                    }
                }
                if count > 0 {
                    var sum = 0.0
                    for s in captureFrameScratch {
                        let v = Double(s)
                        sum += v * v
                    }
                    let rms = sqrt(sum / Double(PlatformAudioPlugin.frameSamples))
                    level = min(1.0, rms / 32768.0)
                    packetData = Data(encodePacketScratch.prefix(Int(count)))
                }
                captureLock.unlock()

                if let data = packetData {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self,
                              self.isCapturing,
                              self.captureGeneration == generation,
                              let sink = self.eventSink else { return }
                        sink(["data": FlutterStandardTypedData(bytes: data), "level": level])
                    }
                }
                if !hasMore { break }
            }
        }
    }

    fileprivate func providePlaybackPcm(into buffer: UnsafeMutablePointer<Int16>, sampleCount: Int) {
        guard sampleCount > 0 else { return }

        playbackLock.lock()
        defer { playbackLock.unlock() }

        if remoteStreams.isEmpty {
            buffer.initialize(repeating: 0, count: sampleCount)
            return
        }

        if mixScratch.count < sampleCount {
            mixScratch = [Int32](repeating: 0, count: sampleCount)
        } else {
            for i in 0..<sampleCount { mixScratch[i] = 0 }
        }
        var activeStreams = 0

        for stream in remoteStreams.values {
            var written = 0
            while written < sampleCount {
                if stream.pcmOffset >= stream.pcmCount {
                    let polled = stream.jitter.poll()
                    let decoded: Int32
                    switch polled {
                    case .notReady:
                        decoded = -1
                    case .packet(let bytes):
                        decoded = bytes.withUnsafeBufferPointer { input in
                            stream.pcm.withUnsafeMutableBufferPointer { output in
                                opus_decode(stream.decoder, input.baseAddress, Int32(bytes.count),
                                            output.baseAddress, Int32(PlatformAudioPlugin.frameSamples), 0)
                            }
                        }
                    case .lost:
                        decoded = stream.pcm.withUnsafeMutableBufferPointer { output in
                            opus_decode(stream.decoder, nil, 0,
                                        output.baseAddress, Int32(PlatformAudioPlugin.frameSamples), 0)
                        }
                    }
                    if case .notReady = polled { break }
                    if decoded <= 0 {
                        stream.pcmCount = 0
                        stream.pcmOffset = 0
                        continue
                    }
                    stream.pcmCount = Int(decoded)
                    stream.pcmOffset = 0
                }

                let available = stream.pcmCount - stream.pcmOffset
                let count = min(sampleCount - written, available)
                for i in 0..<count {
                    mixScratch[written + i] += Int32(stream.pcm[stream.pcmOffset + i])
                }
                written += count
                stream.pcmOffset += count
            }
            if written > 0 { activeStreams += 1 }
        }

        if activeStreams == 0 {
            buffer.initialize(repeating: 0, count: sampleCount)
            return
        }

        // 混音饱和截断（Saturation Clipping）
        for i in 0..<sampleCount {
            let val = mixScratch[i]
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
    let sampleCount = Int(inNumberFrames)
    guard let unit = plugin.audioUnit,
          let scratch = plugin.renderScratchPointer(capacity: sampleCount) else {
        return noErr
    }

    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: inNumberFrames * 2,
            mData: UnsafeMutableRawPointer(scratch)
        )
    )

    let status = AudioUnitRender(
        unit,
        ioActionFlags,
        inTimeStamp,
        1,
        inNumberFrames,
        &bufferList
    )

    if status == noErr, let rawData = bufferList.mBuffers.mData {
        let ptr = rawData.bindMemory(to: Int16.self, capacity: sampleCount)
        plugin.enqueueCapturedSamples(ptr, count: sampleCount)
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
