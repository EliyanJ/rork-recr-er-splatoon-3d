import Foundation
import MultipeerConnectivity

/// MultipeerConnectivity implementation of `MatchTransport` — direct
/// iPhone-to-iPhone connection over Wi-Fi/Bluetooth, no server involved.
/// One device advertises (host), the other browses and invites; all MPC
/// types (MCPeerID, MCSession, delegates) stay private to this file.
final class MultipeerTransport: NSObject, MatchTransport {
    let localPlayerID = PlayerID()

    var onMessage: ((NetEnvelope, PlayerID) -> Void)?
    var onPeerJoined: ((PlayerID, String) -> Void)?
    var onPeerLeft: ((PlayerID) -> Void)?
    var onPeerConnecting: (() -> Void)?
    var onDiscoveredPeersChanged: (([String]) -> Void)?
    var onError: ((TransportError) -> Void)?

    /// Bonjour service type — must match NSBonjourServices in the Info.plist.
    private static let serviceType = "ink-arena3d"

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var isHostMode = false
    /// Hosts discovered while browsing, keyed by display name.
    private var discovered: [String: MCPeerID] = [:]
    /// Stable abstract identity assigned to each connected MPC peer.
    private var peerIdentities: [MCPeerID: PlayerID] = [:]
    private let encoder = JSONEncoder()

    var isConnected: Bool {
        session?.connectedPeers.isEmpty == false
    }

    // MARK: - Lifecycle

    func startHosting(displayName: String) {
        teardown()
        isHostMode = true
        let peer = makePeerID(displayName: displayName)
        session = makeSession(peer: peer)
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peer,
            discoveryInfo: nil,
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    func startBrowsing(displayName: String) {
        teardown()
        isHostMode = false
        let peer = makePeerID(displayName: displayName)
        session = makeSession(peer: peer)
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func join(peerNamed name: String) {
        guard let peerID = discovered[name], let session, let browser else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 12)
    }

    func resumeDiscovery() {
        advertiser?.startAdvertisingPeer()
        browser?.startBrowsingForPeers()
    }

    func send(_ envelope: NetEnvelope, channel: NetChannel) {
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? encoder.encode(envelope) else { return }
        let mode: MCSessionSendDataMode = channel == .reliable ? .reliable : .unreliable
        try? session.send(data, toPeers: session.connectedPeers, with: mode)
    }

    func stop() {
        teardown()
    }

    // MARK: - Private helpers

    private func teardown() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        discovered = [:]
        peerIdentities = [:]
        isHostMode = false
        onDiscoveredPeersChanged?([])
    }

    private func makePeerID(displayName: String) -> MCPeerID {
        var name = displayName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Peintre" }
        return MCPeerID(displayName: String(name.prefix(24)))
    }

    private func makeSession(peer: MCPeerID) -> MCSession {
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }

    private func identity(for peerID: MCPeerID) -> PlayerID {
        if let existing = peerIdentities[peerID] { return existing }
        let fresh = PlayerID()
        peerIdentities[peerID] = fresh
        return fresh
    }

    private func handlePeerConnected(_ peerID: MCPeerID) {
        let id = identity(for: peerID)
        // Pause discovery while a peer is attached; resumeDiscovery restarts
        // it after a mid-lobby drop.
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        onPeerJoined?(id, peerID.displayName)
    }

    private func handlePeerDisconnected(_ peerID: MCPeerID) {
        guard let id = peerIdentities.removeValue(forKey: peerID) else {
            onPeerLeft?(PlayerID())
            return
        }
        onPeerLeft?(id)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.handlePeerConnected(peerID)
            case .notConnected:
                self.handlePeerDisconnected(peerID)
            case .connecting:
                self.onPeerConnecting?()
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Unknown message kinds decode to `.unknown` (tolerant protocol);
        // only a structurally broken envelope is dropped here.
        guard let envelope = try? JSONDecoder().decode(NetEnvelope.self, from: data) else { return }
        Task { @MainActor in
            self.onMessage?(envelope, self.identity(for: peerID))
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            // First come, first served — one match, one guest (for now; the
            // protocol itself supports N peers for the future online mode).
            let accept = self.isHostMode && self.session?.connectedPeers.isEmpty != false
            invitationHandler(accept, accept ? self.session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        Task { @MainActor in
            self.onError?(.advertisingFailed)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            self.discovered[peerID.displayName] = peerID
            self.onDiscoveredPeersChanged?(Array(self.discovered.keys).sorted())
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discovered.removeValue(forKey: peerID.displayName)
            self.onDiscoveredPeersChanged?(Array(self.discovered.keys).sorted())
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        Task { @MainActor in
            self.onError?(.browsingFailed)
        }
    }
}
