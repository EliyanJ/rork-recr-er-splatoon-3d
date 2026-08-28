import Foundation
import Observation

/// Lobby coordinator for local duels. Owns an abstract `MatchTransport`
/// (MultipeerConnectivity today, a server transport tomorrow) and exposes
/// lobby state (phase, remote player info, discovered hosts, errors) to the
/// UI plus a gameplay message pipe to the live GameController.
///
/// This type never touches MultipeerConnectivity directly — everything
/// transport-specific lives behind the `MatchTransport` protocol.
@Observable
final class LocalMatchService {
    static let shared = LocalMatchService()

    enum Phase: Equatable {
        case idle
        case hosting
        case browsing
        case connecting
        case connected
        case inMatch
    }

    private(set) var phase: Phase = .idle
    private(set) var isHost = false
    private(set) var remoteName: String = "Adversaire"
    private(set) var remoteWeapon: WeaponType = .blaster
    /// Hosts discovered while browsing — display names shown in the join list.
    private(set) var foundPeers: [String] = []
    /// One-shot connection error surfaced in the lobby UI.
    private(set) var lastError: String?

    /// Fired on the guest when the host launches the match — arena,
    /// win-condition and AI bots added per team (0 = pure 1v1).
    var onStart: ((ArenaMap, MatchMode, Int) -> Void)?
    /// Gameplay envelopes routed to the live GameController (message +
    /// sender/seq/timestamp metadata for ordering and attribution).
    var onGameMessage: ((NetEnvelope) -> Void)?

    /// Local player identity on the current transport.
    var localPlayerID: PlayerID { transport.localPlayerID }
    /// Identity of the connected remote peer, nil while disconnected.
    private(set) var remotePlayerID: PlayerID?

    @ObservationIgnored private let transport: any MatchTransport
    /// Per-channel monotonic sequence counters stamped into every envelope.
    @ObservationIgnored private var reliableSeq: UInt32 = 0
    @ObservationIgnored private var unreliableSeq: UInt32 = 0

    private init(transport: any MatchTransport = MultipeerTransport()) {
        self.transport = transport
        wireTransport()
    }

    // MARK: - Lobby control

    /// Starts advertising this device as a duel host.
    func host() {
        stop()
        isHost = true
        phase = .hosting
        transport.startHosting(displayName: localDisplayName())
    }

    /// Starts browsing for nearby duel hosts.
    func browse() {
        stop()
        isHost = false
        phase = .browsing
        transport.startBrowsing(displayName: localDisplayName())
    }

    /// Invites the tapped host from the discovery list.
    func join(peerNamed name: String) {
        guard phase == .browsing || phase == .connecting else { return }
        phase = .connecting
        transport.join(peerNamed: name)
    }

    /// Host only: launches the match on both devices, with `bots` AI fighters
    /// added to each team (simulated by the host, mirrored on the guest).
    func startMatch(map: ArenaMap, mode: MatchMode, bots: Int, botLevel: BotDifficulty) {
        guard isHost, phase == .connected else { return }
        send(.start(map: map.rawValue, mode: mode.rawValue, bots: bots, botLevel: botLevel.rawValue))
        phase = .inMatch
    }

    /// Seals one gameplay message into a versioned envelope (sender, per-
    /// channel seq, send timestamp) and hands it to the transport. Events
    /// ride the reliable channel; the high-frequency `state` stream rides
    /// `.unreliable` (step 5) so a lost snapshot never delays anything.
    func send(_ message: NetMessage, channel: NetChannel = .reliable) {
        transport.send(makeEnvelope(message, channel: channel), channel: channel)
    }

    /// Clean teardown — notifies the peer, then disconnects everything.
    func stop() {
        if transport.isConnected {
            transport.send(makeEnvelope(.leave, channel: .reliable), channel: .reliable)
        }
        transport.stop()
        foundPeers = []
        phase = .idle
        isHost = false
        lastError = nil
        remotePlayerID = nil
        reliableSeq = 0
        unreliableSeq = 0
    }

    // MARK: - Transport wiring

    private func wireTransport() {
        transport.onPeerJoined = { [weak self] id, name in
            self?.remotePlayerID = id
            self?.handleConnected(peerName: name)
        }
        transport.onPeerLeft = { [weak self] _ in
            self?.remotePlayerID = nil
            self?.handleDisconnected()
        }
        transport.onPeerConnecting = { [weak self] in
            guard let self, self.phase != .inMatch else { return }
            self.phase = .connecting
        }
        transport.onDiscoveredPeersChanged = { [weak self] names in
            self?.foundPeers = names
        }
        transport.onMessage = { [weak self] envelope, _ in
            self?.handle(envelope)
        }
        transport.onError = { [weak self] error in
            guard let self else { return }
            switch error {
            case .advertisingFailed:
                self.lastError = "Impossible d'héberger — vérifie l'accès au réseau local dans Réglages."
            case .browsingFailed:
                self.lastError = "Impossible de chercher des parties — vérifie l'accès au réseau local dans Réglages."
            }
            self.phase = .idle
        }
    }

    // MARK: - Private helpers

    private func localDisplayName() -> String {
        let name = ProfileStore.shared.playerName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Peintre" : name
    }

    private func handleConnected(peerName: String) {
        remoteName = peerName
        phase = .connected
        send(.hello(
            name: ProfileStore.shared.playerName,
            weapon: ProfileStore.shared.selectedWeapon.rawValue
        ))
    }

    private func handleDisconnected() {
        if phase == .inMatch {
            // Synthesized locally so the controller runs its normal leave path.
            onGameMessage?(makeEnvelope(.leave, channel: .reliable))
            phase = .idle
        } else if phase == .connected || phase == .connecting {
            lastError = "Connexion perdue — réessaie."
            phase = isHost ? .hosting : .browsing
            transport.resumeDiscovery()
        }
    }

    private func handle(_ envelope: NetEnvelope) {
        guard envelope.version == NetProtocol.version else {
            handleVersionMismatch()
            return
        }
        switch envelope.message {
        case .hello(let name, let weapon):
            remoteName = name
            remoteWeapon = WeaponType(rawValue: weapon) ?? .blaster
        case .start(let mapRaw, let modeRaw, let bots, _):
            let map = ArenaMap(rawValue: mapRaw) ?? .nexusDocks
            let mode = MatchMode(rawValue: modeRaw) ?? .turfWar
            phase = .inMatch
            onStart?(map, mode, max(0, min(bots, 2)))
        case .unknown:
            // Message kind from a newer build we both tolerate — ignored.
            break
        case .state, .fire, .hit, .wall, .kill, .paintOps, .botState, .botFire, .clock, .coverage, .result, .leave:
            onGameMessage?(envelope)
        }
    }

    /// The peer runs an incompatible protocol version — refuse cleanly in the
    /// lobby instead of silently misreading its messages.
    private func handleVersionMismatch() {
        if phase != .inMatch {
            stop()
        }
        lastError = "Versions du jeu différentes — mets à jour Splash sur les deux appareils."
    }

    private func makeEnvelope(_ message: NetMessage, channel: NetChannel) -> NetEnvelope {
        let seq: UInt32
        switch channel {
        case .reliable:
            reliableSeq &+= 1
            seq = reliableSeq
        case .unreliable:
            unreliableSeq &+= 1
            seq = unreliableSeq
        }
        return NetEnvelope(
            version: NetProtocol.version,
            sender: transport.localPlayerID,
            seq: seq,
            timestamp: Date().timeIntervalSince1970,
            message: message
        )
    }
}
