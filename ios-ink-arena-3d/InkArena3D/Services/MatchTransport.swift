import Foundation

/// Stable, transport-agnostic player identity. Generated once per transport
/// instance for the local player and assigned to each remote peer on connect.
/// No transport-specific type (MCPeerID, socket handle…) ever leaks past this.
nonisolated struct PlayerID: Hashable, Codable, Sendable {
    let raw: String

    init() {
        raw = UUID().uuidString
    }

    init(raw: String) {
        self.raw = raw
    }
}

/// Delivery guarantee for one outgoing message.
/// - `reliable`: ordered, retransmitted — events (fire, hit, wall, result).
/// - `unreliable`: fire-and-forget — high-frequency state spam where a lost
///   packet must never delay the ones behind it.
nonisolated enum NetChannel: Sendable {
    case reliable
    case unreliable
}

/// Transport-level failures surfaced to the lobby coordinator, which maps
/// them to user-facing copy. Kept as semantic cases so a future online
/// transport can reuse them.
nonisolated enum TransportError: Sendable {
    case advertisingFailed
    case browsingFailed
}

/// Abstraction of the match networking layer. `GameController` and
/// `LocalMatchService` only ever talk to this protocol; the concrete
/// implementation (MultipeerConnectivity today, WebSocket/WebRTC against an
/// authoritative server tomorrow) lives entirely behind it.
///
/// Design rules (locked in for the future online backend):
/// 1. Players are identified by abstract `PlayerID`s, never display names.
/// 2. `send` carries an explicit reliable/unreliable channel.
/// 3. Callbacks are per-peer — nothing assumes exactly two participants.
protocol MatchTransport: AnyObject {
    /// Identity of the local player on this transport instance.
    var localPlayerID: PlayerID { get }

    /// True while at least one remote peer is connected.
    var isConnected: Bool { get }

    /// A gameplay envelope arrived from a remote peer.
    var onMessage: ((NetEnvelope, PlayerID) -> Void)? { get set }
    /// A remote peer finished connecting (id + human-readable display name).
    var onPeerJoined: ((PlayerID, String) -> Void)? { get set }
    /// A remote peer disconnected or was lost.
    var onPeerLeft: ((PlayerID) -> Void)? { get set }
    /// A remote peer started connecting (pre-handshake).
    var onPeerConnecting: (() -> Void)? { get set }
    /// The list of joinable host names changed while browsing.
    var onDiscoveredPeersChanged: (([String]) -> Void)? { get set }
    /// The transport failed to start discovery.
    var onError: ((TransportError) -> Void)? { get set }

    /// Starts advertising this device as a joinable match host.
    func startHosting(displayName: String)
    /// Starts looking for nearby match hosts.
    func startBrowsing(displayName: String)
    /// Invites the named host from the discovered list.
    func join(peerNamed name: String)
    /// Restarts discovery after a mid-lobby disconnect, keeping the session.
    func resumeDiscovery()
    /// Sends one sealed envelope to every connected peer on the given channel.
    /// Envelopes are built by the coordinator (`LocalMatchService`), which owns
    /// the per-channel sequence counters — the transport only moves bytes.
    func send(_ envelope: NetEnvelope, channel: NetChannel)
    /// Full teardown — discovery, session and peer table.
    func stop()
}
