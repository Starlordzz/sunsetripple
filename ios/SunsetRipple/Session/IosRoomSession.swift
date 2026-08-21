import Foundation
import Combine

public final class IosRoomSession: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var pttPressed: Bool = false
    @Published public var isMicMuted: Bool = false
    @Published public var isSpeakerOn: Bool = true
    @Published public var members: [String] = []

    public let selfNickname: String
    private let audioEngine = VoiceProcessingAudioEngine()
    private var transport: MultipeerTransport?

    public init(nickname: String) {
        self.selfNickname = nickname
    }

    public func start(isHost: Bool) {
        transport = MultipeerTransport(displayName: selfNickname)
        if isHost {
            transport?.startAdvertising()
        } else {
            transport?.startBrowsing()
        }
        try? audioEngine.start()
        isConnected = true
        members = [selfNickname]
    }

    public func setPtt(pressed: Bool) {
        pttPressed = pressed
        audioEngine.isMicMuted = !pressed
    }

    public func toggleMute() {
        isMicMuted.toggle()
        audioEngine.isMicMuted = isMicMuted
    }

    public func leave() {
        audioEngine.stop()
        transport?.close()
        transport = nil
        isConnected = false
        members.removeAll()
    }
}

