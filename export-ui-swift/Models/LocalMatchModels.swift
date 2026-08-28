import Foundation

/// Wire protocol constants shared by every transport implementation.
nonisolated enum NetProtocol {
    /// Bumped whenever the message format changes incompatibly. Two devices
    /// with different versions refuse to play together (clean lobby error)
    /// instead of silently misinterpreting each other's messages.
    /// v3: step-4 host authority — live `coverage` broadcast added, `paintOps`
    /// and `clock` actually emitted/consumed.
    /// v4: Partie personnalisée with AI bots — `start` carries the bot roster,
    /// `botState`/`botFire` stream the host-simulated bots to the guest.
    static let version = 5
}

/// Envelope wrapped around every gameplay message on the wire. Carries the
/// metadata the sync layer needs regardless of the payload: protocol version
/// (compatibility check), stable sender identity, per-channel sequence number
/// (out-of-order rejection on the future unreliable channel) and the sender's
/// send-time clock (snapshot interpolation, step 5).
nonisolated struct NetEnvelope: Codable {
    var version: Int
    var sender: PlayerID
    /// Monotonic per-channel counter — receivers drop anything older than
    /// the last applied number for continuous streams.
    var seq: UInt32
    /// Sender wall clock (seconds since 1970) at the moment of sending.
    var timestamp: TimeInterval
    var message: NetMessage
}

/// Wire-format messages exchanged between devices during a local duel.
/// Everything is plain Codable data — no UI types cross the network.
///
/// Encoding is a manual `kind` discriminator + payload so that a receiver
/// running an OLDER build decodes an unknown case as `.unknown` (ignored)
/// instead of failing the whole decode — two slightly different builds keep
/// talking for every message they both understand.
nonisolated enum NetMessage {
    /// Handshake sent right after the connection is established.
    case hello(name: String, weapon: String)
    /// Host → guest: the match starts on this arena, under this win-condition,
    /// with `bots` AI fighters added to EACH team (0 = pure 1v1). `botLevel`
    /// is informative — only the host simulates the bot AI.
    case start(map: String, mode: String, bots: Int, botLevel: String?)
    /// Continuous player state, ~15 Hz.
    case state(NetPlayerState)
    /// One weapon discharge — the receiver replays identical projectiles.
    case fire(NetFireEvent)
    /// "Your projectile touched me" — the puppet owner applies real damage.
    case hit(damage: Int)
    /// A gadget shield wall was raised — the peer rebuilds its own instance.
    case wall(NetWall)
    /// Explicit death event sent by the VICTIM's device the instant it goes
    /// down — replaces the old "hit landed < 3 s ago" attribution guess.
    case kill(NetKill)
    /// Batch of exact paint operations applied locally by the sender — the
    /// receiver replays them on its own grid so both grids converge on the
    /// same tile ownership (host authority, step 4).
    case paintOps(NetPaintOps)
    /// Host → guest: authoritative pose batch for every AI bot (~12 Hz,
    /// unreliable). The guest drives its bot puppets from this stream.
    case botState(NetBotStates)
    /// Host → guest: one AI bot weapon discharge — the guest replays
    /// identical projectiles from its puppet (paint + victim-side damage).
    case botFire(NetBotFire)
    /// Host → guest match clock sync (~2 Hz) — the guest snaps its own timer
    /// to the host's so the match ends at the same instant on both devices.
    case clock(NetClock)
    /// Host → guest live authoritative coverage counters (~2 Hz). The guest
    /// HUD displays these instead of its own locally-drifting grid counters.
    /// Shared world frame: no swap needed on either side. `modeOrange`/
    /// `modePurple` carry the mode-specific team scores (zone points) so both
    /// HUDs show the exact same objective score.
    case coverage(orange: Int, purple: Int, total: Int, modeOrange: Int?, modePurple: Int?)
    /// Host → guest: authoritative final counts, so both devices show the
    /// exact same end-of-match score instead of two drifting local ones.
    /// `orange`/`purple` are paint tiles; `modeOrange`/`modePurple` are the
    /// mode-specific team scores (kills / zone points) when relevant.
    case result(orange: Int, purple: Int, total: Int, modeOrange: Int?, modePurple: Int?)
    /// Clean disconnect (back button, match ended).
    case leave
    /// A message kind this build doesn't know — silently ignored.
    case unknown
}

// MARK: - NetMessage tolerant Codable

extension NetMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case payload
    }

    private enum Kind: String {
        case hello, start, state, fire, hit, wall, kill, paintOps, botState, botFire, clock, coverage, result, leave
    }

    /// Small payload boxes for the cases that carry loose tuples.
    private struct HelloPayload: Codable { var name: String; var weapon: String }
    /// `bots`/`botLevel` decode as nil from older builds — tolerant.
    private struct StartPayload: Codable {
        var map: String
        var mode: String
        var bots: Int?
        var botLevel: String?
    }
    private struct HitPayload: Codable { var damage: Int }
    /// Optional mode scores decode as nil from older builds — tolerant.
    private struct ResultPayload: Codable {
        var orange: Int
        var purple: Int
        var total: Int
        var modeOrange: Int?
        var modePurple: Int?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            self = .unknown
            return
        }
        switch kind {
        case .hello:
            let p = try container.decode(HelloPayload.self, forKey: .payload)
            self = .hello(name: p.name, weapon: p.weapon)
        case .start:
            let p = try container.decode(StartPayload.self, forKey: .payload)
            self = .start(map: p.map, mode: p.mode, bots: p.bots ?? 0, botLevel: p.botLevel)
        case .state:
            self = .state(try container.decode(NetPlayerState.self, forKey: .payload))
        case .fire:
            self = .fire(try container.decode(NetFireEvent.self, forKey: .payload))
        case .hit:
            let p = try container.decode(HitPayload.self, forKey: .payload)
            self = .hit(damage: p.damage)
        case .wall:
            self = .wall(try container.decode(NetWall.self, forKey: .payload))
        case .kill:
            self = .kill(try container.decode(NetKill.self, forKey: .payload))
        case .paintOps:
            self = .paintOps(try container.decode(NetPaintOps.self, forKey: .payload))
        case .botState:
            self = .botState(try container.decode(NetBotStates.self, forKey: .payload))
        case .botFire:
            self = .botFire(try container.decode(NetBotFire.self, forKey: .payload))
        case .clock:
            self = .clock(try container.decode(NetClock.self, forKey: .payload))
        case .coverage:
            let p = try container.decode(ResultPayload.self, forKey: .payload)
            self = .coverage(
                orange: p.orange, purple: p.purple, total: p.total,
                modeOrange: p.modeOrange, modePurple: p.modePurple
            )
        case .result:
            let p = try container.decode(ResultPayload.self, forKey: .payload)
            self = .result(
                orange: p.orange, purple: p.purple, total: p.total,
                modeOrange: p.modeOrange, modePurple: p.modePurple
            )
        case .leave:
            self = .leave
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let name, let weapon):
            try container.encode(Kind.hello.rawValue, forKey: .kind)
            try container.encode(HelloPayload(name: name, weapon: weapon), forKey: .payload)
        case .start(let map, let mode, let bots, let botLevel):
            try container.encode(Kind.start.rawValue, forKey: .kind)
            try container.encode(StartPayload(map: map, mode: mode, bots: bots, botLevel: botLevel), forKey: .payload)
        case .state(let state):
            try container.encode(Kind.state.rawValue, forKey: .kind)
            try container.encode(state, forKey: .payload)
        case .fire(let event):
            try container.encode(Kind.fire.rawValue, forKey: .kind)
            try container.encode(event, forKey: .payload)
        case .hit(let damage):
            try container.encode(Kind.hit.rawValue, forKey: .kind)
            try container.encode(HitPayload(damage: damage), forKey: .payload)
        case .wall(let wall):
            try container.encode(Kind.wall.rawValue, forKey: .kind)
            try container.encode(wall, forKey: .payload)
        case .kill(let kill):
            try container.encode(Kind.kill.rawValue, forKey: .kind)
            try container.encode(kill, forKey: .payload)
        case .paintOps(let ops):
            try container.encode(Kind.paintOps.rawValue, forKey: .kind)
            try container.encode(ops, forKey: .payload)
        case .botState(let states):
            try container.encode(Kind.botState.rawValue, forKey: .kind)
            try container.encode(states, forKey: .payload)
        case .botFire(let fire):
            try container.encode(Kind.botFire.rawValue, forKey: .kind)
            try container.encode(fire, forKey: .payload)
        case .clock(let clock):
            try container.encode(Kind.clock.rawValue, forKey: .kind)
            try container.encode(clock, forKey: .payload)
        case .coverage(let orange, let purple, let total, let modeOrange, let modePurple):
            try container.encode(Kind.coverage.rawValue, forKey: .kind)
            try container.encode(
                ResultPayload(orange: orange, purple: purple, total: total, modeOrange: modeOrange, modePurple: modePurple),
                forKey: .payload
            )
        case .result(let orange, let purple, let total, let modeOrange, let modePurple):
            try container.encode(Kind.result.rawValue, forKey: .kind)
            try container.encode(
                ResultPayload(orange: orange, purple: purple, total: total, modeOrange: modeOrange, modePurple: modePurple),
                forKey: .payload
            )
        case .leave:
            try container.encode(Kind.leave.rawValue, forKey: .kind)
        case .unknown:
            try container.encode("unknown", forKey: .kind)
        }
    }
}

// MARK: - Payload structs

/// Snapshot of one player's pose, streamed continuously during the duel.
nonisolated struct NetPlayerState: Codable {
    var x: Float
    var y: Float
    var z: Float
    /// Facing yaw in radians.
    var yaw: Float
    /// Velocity (m/s) derived from the last streamed position — feeds the
    /// receiver-side extrapolation of step 5.
    var vx: Float
    var vy: Float
    var vz: Float
    var isMoving: Bool
    var isDiving: Bool
    var isDown: Bool
    var weapon: String
    /// Present while the player rides a zipline. Both devices build the exact
    /// same cable table, so the receiver re-derives the hang position from
    /// its own copy of cable `index` at progress `t`.
    var zipline: NetZiplineState?
}

/// Zipline ride state: which cable, how far along it, and travel direction.
nonisolated struct NetZiplineState: Codable {
    var index: Int
    /// Progress along the cable, 0...1 from start to end.
    var t: Float
    var forward: Bool
}

/// Explicit death event, always sent by the victim's own device (it is the
/// authority on its own HP). `killer` is nil for environment/self splats.
nonisolated struct NetKill: Codable {
    /// PlayerID.raw of the fighter who went down.
    var victim: String
    /// PlayerID.raw of the finisher, nil when nobody gets the credit.
    var killer: String?
}

/// One replayable paint primitive — compact enough to batch dozens per
/// message. Only the sender's OWN paint travels (its team colour); the
/// receiver applies each op verbatim so both grids converge exactly.
nonisolated struct NetPaintOp: Codable {
    nonisolated enum Kind: Int, Codable {
        /// Circular ground splat at (x, z) with `radius`.
        case splat = 0
    }

    var kind: Kind
    /// Team raw value of the painter.
    var team: Int
    var x: Float
    var z: Float
    var radius: Float
}

/// Batch of paint operations flushed a few times per second.
nonisolated struct NetPaintOps: Codable {
    var ops: [NetPaintOp]
}

/// Host → guest match clock: seconds remaining on the host timer.
nonisolated struct NetClock: Codable {
    var remaining: Float
}

/// One AI bot pose snapshot inside a `botState` batch. `id` is the stable
/// roster netID shared by both devices (same spawn order on host & guest).
nonisolated struct NetBotState: Codable {
    var id: Int
    var x: Float
    var y: Float
    var z: Float
    /// Facing yaw in radians.
    var yaw: Float
    var moving: Bool
    var diving: Bool
    var down: Bool
}

/// Authoritative AI-bot poses broadcast by the host at ~12 Hz.
nonisolated struct NetBotStates: Codable {
    var bots: [NetBotState]
}

/// One AI bot weapon discharge (host authority), replayed on the guest with
/// the exact same ballistics as local weapons. Bots use the blaster jet, the
/// paint grenade, and — for the designated sniper bot — the charged shot.
nonisolated struct NetBotFire: Codable {
    var id: Int
    var kind: NetFireEvent.Kind
    var ox: Float
    var oy: Float
    var oz: Float
    var dx: Float
    var dy: Float
    var dz: Float
    /// Charger charge fraction (0...1) — only meaningful for `.charged`.
    var charge: Float?
}

/// A gadget shield wall raised by a player, streamed once so the peer can
/// rebuild it. Position is in the sender's world frame; the receiver mirrors
/// it across the arena centre plane like every other remote coordinate.
nonisolated struct NetWall: Codable {
    var cx: Float
    var cy: Float
    var cz: Float
    var halfX: Float
    var halfZ: Float
    var baseY: Float
}

/// One weapon discharge, replayed symmetrically on the other device.
nonisolated struct NetFireEvent: Codable {
    nonisolated enum Kind: Int, Codable {
        case jet = 0
        case bucket = 1
        case charged = 2
        case grenade = 4
    }

    var kind: Kind
    var weapon: String
    var ox: Float
    var oy: Float
    var oz: Float
    var dx: Float
    var dy: Float
    var dz: Float
    /// Charger charge fraction (0...1) — only meaningful for `.charged`.
    var charge: Float
}
