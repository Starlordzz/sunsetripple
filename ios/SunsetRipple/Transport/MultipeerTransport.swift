import Foundation
import MultipeerConnectivity

public final class MultipeerTransport: NSObject, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    private let serviceType = "sunset-ripple"
    private let myPeerId: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    public var onFrameReceived: ((Frame, MCPeerID) -> Void)?
    public var onPeersChanged: (([MCPeerID]) -> Void)?

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

    public func startAdvertising() {
        advertiser.startAdvertisingPeer()
    }

    public func startBrowsing() {
        browser.startBrowsingForPeers()
    }

    public func broadcast(frame: Frame) {
        guard !session.connectedPeers.isEmpty else { return }
        let data = frame.encode()
        let mode: MCSessionSendDataMode = (frame.type == .audio) ? .unreliable : .reliable
        try? session.send(data, toPeers: session.connectedPeers, with: mode)
    }

    public func close() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    // MARK: - MCSessionDelegate
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onPeersChanged?(self.session.connectedPeers)
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let frame = Frame.decode(data: data) {
            onFrameReceived?(frame, peerID)
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MARK: - Advertiser & Browser
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, self.session)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

