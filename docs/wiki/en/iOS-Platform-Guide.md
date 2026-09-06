> 🌐 English | [简体中文](../iOS平台适配指南.md)

# SunsetRipple iOS Platform Guide

This document describes the native adaptation implementation for SunsetRipple on iOS, covering the call-grade audio engine (based on `AudioUnit VoiceProcessingIO`) and near-field P2P communication (based on `MultipeerConnectivity`).

---

## 1. Call-Grade Audio Engine (`VoiceProcessingAudioEngine.swift`)

On iOS, `kAudioUnitSubType_VoiceProcessingIO` directly invokes the iPhone's built-in hardware echo cancellation (AEC) and noise suppression (NS), providing 16 kHz, 16-bit, mono PCM data:

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

## 2. Near-Field P2P Transport (`MultipeerTransport.swift`)

Uses the iOS built-in `MultipeerConnectivity` framework to form a network among nearby iOS devices without connecting to a Wi-Fi router. Audio data is sent as `.unreliable`, and control signaling is sent as `.reliable`:

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
