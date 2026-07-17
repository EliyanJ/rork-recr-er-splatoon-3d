import Foundation
import RealityKit
import UIKit
import simd

/// Local duel networking: transport streaming, message handling, host
/// authority, paint sync, and the remote-player puppet interpolation.
/// Extracted verbatim from `GameController` — no behaviour change.
extension GameController {
    /// Streams the local player's pose to the other device at ~24 Hz on the
    /// unreliable channel — a lost snapshot never delays the ones behind it
    /// (nor the reliable events), the interpolation buffer absorbs the gap.
    func networkTick(dt: Float) {
        netStateTimer -= Double(dt)
        guard netStateTimer <= 0, let container = playerContainer else { return }
        netStateTimer = 1.0 / 24.0
        let forward = container.orientation.act([0, 0, 1])
        let moving = simd_length(joystick) > 0.06 || simd_length(diveStick) > 0.06
        let pos = container.position
        // Velocity derived from the previous snapshot — carried for the
        // receiver-side extrapolation of step 5.
        var velocity = SIMD3<Float>.zero
        if let last = lastNetSentPosition, lastNetSentAt >= 0 {
            let interval = Float(elapsed - lastNetSentAt)
            if interval > 0.001 {
                velocity = (pos - last) / interval
            }
        }
        lastNetSentPosition = pos
        lastNetSentAt = elapsed
        localMatch.send(.state(NetPlayerState(
            x: pos.x,
            y: pos.y,
            z: pos.z,
            yaw: atan2(forward.x, forward.z),
            vx: velocity.x,
            vy: velocity.y,
            vz: velocity.z,
            isMoving: moving,
            isDiving: isDiving,
            isDown: isPlayerDown,
            weapon: weapon.rawValue,
            zipline: ziplineRide.map {
                NetZiplineState(index: $0.index, t: $0.t, forward: $0.forward)
            }
        )), channel: .unreliable)
    }

    // MARK: Paint sync (step-4 host authority)

    /// Wire code for a team in `NetPaintOp` (0 = orange, 1 = purple).
    static func netTeamCode(_ team: Team) -> Int { team == .orange ? 0 : 1 }

    static func team(fromNetCode code: Int) -> Team? {
        switch code {
        case 0: .orange
        case 1: .purple
        default: nil
        }
    }

    /// Queues one locally-applied paint primitive for the peer. Only OUR OWN
    /// paint is streamed — the peer's paint arrives through its own ops, and
    /// replayed remote projectiles (enemy team) never re-emit.
    func queueNetPaint(_ op: NetPaintOp, team: Team) {
        guard isLocalDuel, team == localTeam, !isMatchOver else { return }
        pendingPaintOps.append(op)
    }

    func netPaintSplat(x: Float, z: Float, radius: Float, team: Team) {
        queueNetPaint(
            NetPaintOp(kind: .splat, team: Self.netTeamCode(team), x: x, z: z, radius: radius),
            team: team
        )
    }

    /// Ships the queued paint primitives in compact batches (~8 Hz) — the
    /// peer replays them verbatim so both grids converge on the exact same
    /// tile ownership.
    func flushNetPaintOps(dt: Double) {
        netPaintFlushTimer -= dt
        guard netPaintFlushTimer <= 0 else { return }
        netPaintFlushTimer = 0.12
        guard !pendingPaintOps.isEmpty else { return }
        localMatch.send(.paintOps(NetPaintOps(ops: pendingPaintOps)))
        pendingPaintOps.removeAll(keepingCapacity: true)
    }

    /// Applies the peer's exact paint primitives to our grid. Rendering stays
    /// predictive (replayed remote projectiles already painted most of these
    /// tiles); these ops close the gap so both grids converge. No stats
    /// credit here — personal tallies were already credited by the predictive
    /// replay, and the team counters are the host's authority anyway.
    func applyRemotePaintOps(_ batch: NetPaintOps) {
        guard let grid else { return }
        for op in batch.ops {
            guard let team = Self.team(fromNetCode: op.team) else { continue }
            switch op.kind {
            case .splat:
                grid.paint(atX: op.x, z: op.z, radius: op.radius, team: team)
            }
        }
    }

    /// Broadcasts one local weapon discharge so the other device replays
    /// identical projectiles from the remote puppet.
    func sendFire(
        kind: NetFireEvent.Kind,
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        charge: Float = 0
    ) {
        guard isLocalDuel else { return }
        localMatch.send(.fire(NetFireEvent(
            kind: kind,
            weapon: weapon.rawValue,
            ox: origin.x, oy: origin.y, oz: origin.z,
            dx: direction.x, dy: direction.y, dz: direction.z,
            charge: charge
        )))
    }

    /// Entry point for every gameplay envelope received from the peer.
    func handleNetMessage(_ envelope: NetEnvelope) {
        guard isLocalDuel else { return }
        switch envelope.message {
        case .state(let state):
            // Drop snapshots older than the last applied one — the state
            // stream rides the unreliable channel, packets CAN arrive out
            // of order or duplicated.
            if lastRemoteStateSeq != 0, envelope.seq <= lastRemoteStateSeq { return }
            lastRemoteStateSeq = envelope.seq
            applyRemoteState(state, at: envelope.timestamp)
        case .fire(let event):
            spawnRemoteFire(event)
        case .hit(let damage):
            guard !isPlayerDown, !isMatchOver, let pos = playerContainer?.position else { return }
            hitPlayer(at: pos, damage: damage, by: remoteBot?.statsIndex ?? -1)
        case .kill(let kill):
            // Host-authoritative AI bot death — the guest mirrors it on its
            // local puppet with the exact attribution.
            if kill.victim.hasPrefix("bot:") {
                guard !localMatch.isHost, let id = Int(kill.victim.dropFirst(4)),
                      let bot = duelBot(netID: id) else { return }
                duelBotWentDown(bot, killerIndex: netFighterIndex(fromRaw: kill.killer))
                return
            }
            // Sent by the victim about itself — the sender must be the peer.
            guard let bot = remoteBot, kill.victim == envelope.sender.raw else { return }
            remoteWentDown(bot, killerIndex: netFighterIndex(fromRaw: kill.killer))
        case .wall(let netWall):
            spawnRemoteInkWall(netWall)
        case .paintOps(let batch):
            applyRemotePaintOps(batch)
        case .botState(let batch):
            applyDuelBotStates(batch, seq: envelope.seq)
        case .botFire(let event):
            spawnDuelBotFire(event)
        case .clock(let clock):
            // Guest only: snap the local timer to the host's authoritative
            // clock when they drift apart — both matches end simultaneously.
            guard !localMatch.isHost, !isMatchOver else { return }
            if abs(timeLeftExact - Double(clock.remaining)) > 0.4 {
                timeLeftExact = Double(clock.remaining)
            }
        case .coverage(let orange, let purple, let total, let modeOrange, let modePurple):
            // Guest only: adopt the host's live counters — displayed by
            // `updateCoverage` instead of the local grid's drifting tallies.
            guard !localMatch.isHost else { return }
            hostCoverage = (orange, purple, total)
            // Contrôle de Zones: the host is the single scoring authority —
            // mirror its zone totals on the guest HUD instead of accumulating
            // a drifting local copy from the interpolated puppet position.
            if matchMode == .zoneControl, let modeOrange, let modePurple {
                zoneScoreExactOrange = Double(modeOrange)
                zoneScoreExactPurple = Double(modePurple)
                if modeOrange != zoneScoreOrange { zoneScoreOrange = modeOrange }
                if modePurple != zoneScorePurple { zoneScorePurple = modePurple }
            }
        case .result(let orange, let purple, let total, let modeOrange, let modePurple):
            // Guest only: adopt the host's authoritative counts. Both
            // devices share one world frame now — no swap, `finalizeMatch`
            // picks the local share via `localTeam`.
            guard !localMatch.isHost, !hasPublishedResult else { return }
            if !isMatchOver { beginMatchOver() }
            let modeScores: (orange: Int, purple: Int)?
            if let modeOrange, let modePurple {
                modeScores = (modeOrange, modePurple)
            } else {
                modeScores = nil
            }
            finalizeMatch(orange: orange, purple: purple, total: total, modeScores: modeScores)
        case .leave:
            guard !isMatchOver else { return }
            endMatch()
        case .hello, .start, .unknown:
            break
        }
    }

    /// Builds the sponge dive form for any AI fighter (solo bot or remote
    /// duel puppet) — the same generated model the local player uses,
    /// hidden until the fighter dives. Mirrors `buildDiveForm` but targets
    /// the bot's container.
    func buildBotDiveForm(for bot: BotAgent) async {
        let form = Entity()
        form.name = "bot_dive_form"
        let spec = ModelCatalog.sponge
        var loaded: Entity?
        if let name = spec.resourceName {
            loaded = try? await Entity(named: name)
        }
        attachGeneratedModelVisual(
            loaded ?? Self.fallbackSponge(),
            to: form,
            targetSize: 0.85,
            scaleAxis: .positiveY,
            anchor: .bottom,
            localFrontAxis: spec.localFrontAxis,
            localUpAxis: spec.localUpAxis,
            desiredWorldForward: spec.localFrontAxis == nil ? nil : [0, 0, 1]
        )
        form.findEntity(named: "generated_model_runtime")?.name = "bot_dive_runtime"
        form.isEnabled = false
        bot.container.addChild(form)
        bot.diveForm = form
    }

    /// (Re)attaches the weapon model matching `weapon` to the remote puppet's
    /// hand socket, replacing whatever it previously held. Mirrors the local
    /// `applyWeaponVisual`.
    func applyRemoteWeaponVisual(_ weapon: WeaponType, to bot: BotAgent) async {
        guard let socket = bot.weaponSocket else { return }
        socket.findEntity(named: "weapon_runtime")?.removeFromParent()

        let spec = Self.weaponSpec(for: weapon)
        var loaded: Entity?
        if let name = spec.resourceName {
            loaded = try? await Entity(named: name)
        }
        Self.attachWeaponVisual(
            loaded ?? Self.fallbackWeaponVisual(for: weapon),
            to: socket,
            spec: spec,
            targetSize: Self.weaponVisualSize(for: weapon)
        )
        // Keep the socket hidden if the puppet is currently in sponge form.
        socket.isEnabled = !bot.isDiving
    }

    /// Buffers one received pose snapshot (timestamped with the sender's
    /// send clock) for the interpolated puppet rendering, and resolves the
    /// binary flags (dive, weapon, down/respawn) as "last received state".
    func applyRemoteState(_ state: NetPlayerState, at timestamp: TimeInterval) {
        guard let bot = remoteBot else { return }
        // Shared world frame: streamed coordinates apply as-is, no mirroring.
        let position = SIMD3<Float>(state.x, state.y, state.z)
        var snapshot = RemoteSnapshot(
            time: timestamp,
            position: position,
            yaw: state.yaw,
            velocity: [state.vx, state.vy, state.vz]
        )
        if let ride = state.zipline, ride.index >= 0, ride.index < ziplines.count {
            // Zipline ride: both devices build the exact same cable table, so
            // the hang point is re-derived from OUR copy of the cable — keeps
            // the puppet glued to the cable even between two snapshots.
            let line = ziplines[ride.index]
            let t = min(max(ride.t, 0), 1)
            let cable = simd_mix(line.start, line.end, SIMD3<Float>(repeating: t))
            snapshot.position = [cable.x, cable.y - GameConfig.ziplineHangHeight, cable.z]
            let dir = ride.forward ? line.end - line.start : line.start - line.end
            snapshot.yaw = atan2(dir.x, dir.z)
            snapshot.velocity = .zero
        }
        // Seq filtering already dropped out-of-order packets; the timestamp
        // guard only protects against a stalled sender clock.
        if snapshot.time > (remoteSnapshots.last?.time ?? -.infinity) {
            remoteSnapshots.append(snapshot)
            // Hard cap — never let a paused render loop grow the buffer.
            if remoteSnapshots.count > 48 {
                remoteSnapshots.removeFirst(remoteSnapshots.count - 48)
            }
        }
        remoteIsMoving = state.isMoving
        // Sponge form: mirror the opponent's dive so the puppet visibly turns
        // into the sponge here, not just moves faster.
        if bot.isDiving != state.isDiving {
            bot.isDiving = state.isDiving
            bot.applyDiveVisibility()
        }
        // Held weapon: re-attach the matching model whenever the opponent
        // swaps loadout mid-match.
        if let received = WeaponType(rawValue: state.weapon), received != bot.currentWeapon {
            bot.currentWeapon = received
            Task { await applyRemoteWeaponVisual(received, to: bot) }
        }
        if state.isDown, !bot.isDown {
            // Fallback only — the explicit `.kill` message normally arrives
            // first (reliable channel, sent the instant the victim drops) and
            // carries the proper attribution.
            remoteWentDown(bot, killerIndex: -1)
        } else if !state.isDown, bot.isDown {
            remoteRespawned(bot, at: position)
        }
    }

    /// The remote announced its own death (explicit `.kill` event, or the
    /// state-flag fallback) — play the splat locally and credit the killer
    /// exactly as attributed by the victim's own device.
    func remoteWentDown(_ bot: BotAgent, killerIndex: Int) {
        guard !bot.isDown else { return }
        bot.isDown = true
        refreshEnemyStatuses()
        let pos = bot.container.position
        let gained = grid?.paint(atX: pos.x, z: pos.z, radius: 1.7, team: localTeam) ?? 0
        credit(paint: gained, to: 0)
        netPaintSplat(x: pos.x, z: pos.z, radius: 1.7, team: localTeam)
        recordKill(victimIndex: bot.statsIndex, killerIndex: killerIndex, attackers: [])
        AudioService.shared.playEnemySplat(volume: spatialVolume(1.0, at: pos))
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        if killerIndex == 0, bot.statsIndex < liveStats.count {
            showSplatEvent(headline: "TU AS ÉCLABOUSSÉ", name: liveStats[bot.statsIndex].name, isPlayerVictim: false)
        }
        bot.setLoop(nil)
        bot.animator.playOnce(bot.splatAnim, restoreAfter: .milliseconds(900))
        Task { [weak bot] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let bot, bot.isDown else { return }
            bot.container.isEnabled = false
        }
    }

    func remoteRespawned(_ bot: BotAgent, at position: SIMD3<Float>) {
        bot.isDown = false
        bot.container.isEnabled = true
        bot.container.position = position
        // Fresh timeline — never glide from the death spot to the base.
        remoteSnapshots.removeAll(keepingCapacity: true)
        remoteRenderTime = -1
        refreshEnemyStatuses()
    }

    /// Per-frame puppet driving: eased interpolation toward the streamed
    /// pose and run/idle animations.
    func updateRemotePuppet(dt: Float, grid: PaintGrid) {
        guard let bot = remoteBot, !bot.isDown else { return }
        bot.updateWeaponFollow(dt: dt)

        // Gentle bob of the sponge form while the puppet is diving.
        if bot.isDiving, let form = bot.diveForm {
            let bob = sinf(Float(elapsed) * 9) * 0.08
            form.position = [0, 0.05 + bob, 0]
        }

        if let pose = interpolatedRemotePose(advancing: TimeInterval(dt)) {
            let pos = bot.container.position
            if simd_distance(pos, pose.position) > 8 {
                // Teleport (respawn/desync) — never glide across the arena.
                bot.container.position = pose.position
            } else {
                // The interpolated timeline is already smooth — apply as-is.
                bot.container.position = pose.position
            }
            bot.container.orientation = simd_quatf(angle: pose.yaw, axis: [0, 1, 0])
        }
        bot.setLoop(remoteIsMoving ? (bot.runAnim ?? bot.idleAnim) : bot.idleAnim)
    }

    /// Produces the puppet pose for this frame: the render cursor runs on
    /// the SENDER's clock, ~120 ms behind the newest snapshot, so there are
    /// almost always two buffered snapshots bracketing it — position and yaw
    /// interpolate exactly between real streamed poses instead of easing
    /// toward a single moving target (the old "elastic/delayed" look).
    func interpolatedRemotePose(advancing dt: TimeInterval) -> RemotePose? {
        guard let newest = remoteSnapshots.last else { return nil }
        let ideal = newest.time - Self.remoteInterpDelay
        if remoteRenderTime < 0 || abs(remoteRenderTime - ideal) > 0.35 {
            // First snapshot or major stall — snap the cursor.
            remoteRenderTime = ideal
        } else {
            // Advance with the local frame clock, gently re-synced toward
            // the ideal delay point to absorb send/receive jitter.
            remoteRenderTime += dt
            remoteRenderTime += (ideal - remoteRenderTime) * min(1, dt * 3)
        }
        // Drop snapshots fully behind the cursor, keeping the bracketing one.
        while remoteSnapshots.count >= 2, remoteSnapshots[1].time <= remoteRenderTime {
            remoteSnapshots.removeFirst()
        }
        if remoteSnapshots.count >= 2 {
            let a = remoteSnapshots[0]
            let b = remoteSnapshots[1]
            if remoteRenderTime <= a.time {
                return RemotePose(position: a.position, yaw: a.yaw)
            }
            let span = max(b.time - a.time, 0.0001)
            let t = Float(min(max((remoteRenderTime - a.time) / span, 0), 1))
            return RemotePose(
                position: simd_mix(a.position, b.position, SIMD3<Float>(repeating: t)),
                yaw: Self.lerpAngle(a.yaw, b.yaw, t)
            )
        }
        // Buffer ran dry (packet loss) — extrapolate along the streamed
        // velocity, hard-capped so a stale snapshot never slides away.
        let overshoot = Float(min(
            max(0, remoteRenderTime - newest.time),
            Self.remoteExtrapolationCap
        ))
        return RemotePose(
            position: newest.position + newest.velocity * overshoot,
            yaw: newest.yaw
        )
    }

    /// Shortest-arc angle interpolation (yaw wraps at ±π).
    static func lerpAngle(_ a: Float, _ b: Float, _ t: Float) -> Float {
        var delta = fmodf(b - a, 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return a + delta * t
    }

    /// Replays one remote weapon discharge with the exact same ballistics
    /// as the local weapons — projectiles, paint and damage are then
    /// resolved by the shared simulation.
    func spawnRemoteFire(_ event: NetFireEvent) {
        guard let bot = remoteBot else { return }
        // Shared world frame: origin and direction apply as-is.
        let origin = SIMD3<Float>(event.ox, event.oy, event.oz)
        var dir = SIMD3<Float>(event.dx, event.dy, event.dz)
        guard simd_length(dir) > 0.001 else { return }
        dir = simd_normalize(dir)
        let remoteWeapon = WeaponType(rawValue: event.weapon) ?? .blaster
        let owner = bot.statsIndex

        switch event.kind {
        case .jet:
            spawnJetDrop(at: origin, direction: dir, team: bot.team, weapon: remoteWeapon, ownerIndex: owner)
            spawnJetDrop(at: origin - dir * 0.24, direction: dir, team: bot.team, weapon: remoteWeapon, ownerIndex: owner)
            spawnJetDrop(at: origin - dir * 0.48, direction: dir, team: bot.team, weapon: remoteWeapon, ownerIndex: owner)
        case .bucket:
            spawnPaintDrop(
                at: origin, direction: dir, team: bot.team,
                speed: WeaponType.bucket.projectileSpeed,
                gravity: WeaponType.bucket.projectileGravity,
                damage: WeaponType.bucket.damagePerHit,
                paintRadius: WeaponType.bucket.paintRadius,
                dropScale: 3.2, ownerIndex: owner,
                splashRange: GameConfig.bucketSplashRange
            )
        case .charged:
            let charge = min(max(event.charge, 0), 1)
            let speed = GameConfig.chargerMinSpeed
                + (GameConfig.chargerMaxSpeed - GameConfig.chargerMinSpeed) * charge
            let damage = GameConfig.chargerDamage(charge: charge, targetMaxHP: GameConfig.playerMaxHP)
            let radius = GameConfig.chargerMinPaintRadius
                + (GameConfig.chargerMaxPaintRadius - GameConfig.chargerMinPaintRadius) * charge
            spawnPaintDrop(
                at: origin, direction: dir, team: bot.team,
                speed: speed, gravity: GameConfig.chargerShotGravity,
                damage: damage, paintRadius: radius,
                dropScale: 1.3 + charge * 1.2, ownerIndex: owner
            )
            spawnPaintDrop(
                at: origin, direction: dir, team: bot.team,
                speed: speed * 0.72, gravity: GameConfig.chargerShotGravity * 2.4,
                damage: 1, paintRadius: radius * 0.7,
                dropScale: 1.1, ownerIndex: owner
            )
        case .grenade:
            guard let worldRoot else { return }
            let entity = makeGrenadeEntity()
            entity.position = origin
            worldRoot.addChild(entity)
            projectiles.append(Projectile(
                entity: entity,
                velocity: dir * GameConfig.grenadeSpeed + SIMD3<Float>(0, 5.2, 0),
                team: bot.team,
                kind: .grenade,
                gravity: 9.5,
                damage: GameConfig.grenadePlayerDamage,
                paintRadius: GameConfig.grenadePaintRadius,
                ownerIndex: owner,
                detonateAt: elapsed + GameConfig.grenadeFuse
            ))
        }
        if event.kind != .jet || elapsed - lastJetSfx > 0.14 {
            lastJetSfx = elapsed
            AudioService.shared.playSplat(volume: spatialVolume(0.25, at: origin))
        }
    }
}
