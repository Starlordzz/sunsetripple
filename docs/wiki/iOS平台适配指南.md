# SunsetRipple iOS 平台适配指南

本文档提供 SunsetRipple 在 iOS 端的原生适配实现方案，包含通话级音频引擎（基于 `AudioUnit VoiceProcessingIO`）与近场 P2P 通信（基于 `MultipeerConnectivity`）。

---

## 1. 通话级音频引擎 (`VoiceProcessingAudioEngine.swift`)

在 iOS 上使用 `kAudioUnitSubType_VoiceProcessingIO` 可以直接调用 iPhone 硬件内置的回声消除（AEC）与环境降噪（NS），提供 16kHz, 16-bit, 单声道 PCM 数据：

```swift
import Foundation
import AudioToolbox
import AVFoundation

public final class VoiceProcessingAudioEngine {
    private var audioUnit: AudioComponentInstance?
    private var isRunning: Bool = false
    public var isMicMuted: Bool = false
    public var onPcmCaptured: (([Int16]) -> Void)?

    private let sampleRate: Double = 16000.0
    private let frameSamples: Int = 320 // 20ms

    public init() {}

    public func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.02) // 20ms
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
            mSampleRate: sampleRate,
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

    public func stop() {
        guard let unit = audioUnit, isRunning else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        audioUnit = nil
        isRunning = false
    }
}
```

---

## 2. 近场 P2P 传输 (`MultipeerTransport.swift`)

使用 iOS 内置的 `MultipeerConnectivity` 框架，在附近 iOS 设备间无需连接 Wi-Fi 路由器即可自组网，音频数据以 `.unreliable` 发送，控制信令以 `.reliable` 发送：

```swift
import Foundation
import MultipeerConnectivity

public final class MultipeerTransport: NSObject, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    private let serviceType = "sunset-ripple"
    private let myPeerId: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    public var onFrameReceived: ((Data, MCPeerID) -> Void)?

    public init(displayName: String) {
        self.myPeerId = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        self.advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        self.browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        super.init()
        self.session.delegate = self
        self.advertiser.delegate = self
        self.browser.delegate = self
    }

    public func broadcastAudioFrame(data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }

    public func broadcastSignalFrame(data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    // MCSessionDelegate
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {}
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onFrameReceived?(data, peerID)
    }
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // Advertiser & Browser
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, self.session)
    }
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
    }
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
```

