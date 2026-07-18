import Foundation
import RealityKit
import UIKit
import simd

/// Partie personnalisée: host-simulated AI bots inside a local duel.
///
/// Both devices spawn the exact same bot roster (homes, names, netIDs) in
/// the same order. Only the HOST runs the bot AI, damage and respawns; the
/// guest renders network puppets driven by the `botState` stream, replays
/// `botFire` discharges (paint + victim-side damage) and mirrors deaths
/// from the host's explicit bot `kill` events.
extension GameController {
    /// Duel bot with this roster id — nil when the roster doesn't have it.
    func duelBot(netID: Int) -> BotAgent? {
        bots.first { $0.netID == netID }
    }

    /// Wire identity for a stats row: the local player's PlayerID, the
    /// peer's PlayerID for the remote puppet, or "bot:N" for a duel bot.
    func netFighterRaw(forStatsIndex index: Int) -> String? {
        if index == 0 { return localMatch.localPlayerID.raw }
        if index == remoteBot?.statsIndex { return localMatch.remotePlayerID?.raw }
        if let bot = bots.first(where: { $0.statsIndex == index }), let netID = bot.netID {
            return "bot:\(netID)"
        }
        return nil
    }

    /// Local stats row for a wire identity — inverse of `netFighterRaw`,
    /// resolved against THIS device's roster (statsIndexes are per-device).
    func netFighterIndex(fromRaw raw: String?) -> Int {
        guard let raw else { return -1 }
        if raw == localMatch.localPlayerID.raw { return 0 }
        if raw.hasPrefix("bot:"), let id = Int(raw.dropFirst(4)) {
            return duelBot(netID: id)?.statsIndex ?? -1
        }
        if raw == localMatch.remotePlayerID?.raw { return remoteBot?.statsIndex ?? -1 }
        return -1
    }

    // MARK: - Host side: authoritative broadcast

    /// Streams every AI bot's pose to the guest at ~12 Hz on the unreliable
    /// channel — same philosophy as the player state stream: a lost batch
    /// never delays the next one.
    func duelBotNetTick(dt: Float) {
        guard localMatch.isHost else { return }
        duelBotNetTimer -= Double(dt)
        guard duelBotNetTimer <= 0 else { return }
        duelBotNetTimer = 1.0 / 12.0
        let duelBots = bots.filter { $0.netID != nil }
        guard !duelBots.isEmpty else { return }
        let states = duelBots.map { bot -> NetBotState in
            let pos = bot.container.position
            let forward = bot.container.orientation.act([0, 0, 1])
            let velocity = fighterVelocities[bot.statsIndex] ?? .zero
            return NetBotState(
                id: bot.netID ?? 0,
                x: pos.x, y: pos.y, z: pos.z,
                yaw: atan2(forward.x, forward.z),
                moving: simd_length(SIMD2<Float>(velocity.x, velocity.z)) > 0.35,
                diving: bot.isDiving,
                down: bot.isDown
            )
        }
        localMatch.send(.botState(NetBotStates(bots: states)), channel: .unreliable)
    }

    /// Broadcasts one AI bot discharge so the guest replays identical
    /// projectiles (host only — a silent no-op in solo matches).
    func sendDuelBotFire(
        _ bot: BotAgent,
        kind: NetFireEvent.Kind,
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        charge: Float = 0
    ) {
        guard isLocalDuel, localMatch.isHost, let netID = bot.netID else { return }
        localMatch.send(.botFire(NetBotFire(
            id: netID, kind: kind,
            ox: origin.x, oy: origin.y, oz: origin.z,
            dx: direction.x, dy: direction.y, dz: direction.z,
            charge: charge
        )))
    }

    // MARK: - Guest side: puppets

    /// Applies one authoritative bot pose batch (guest only). Down/respawn
    /// transitions resolve here too, as a fallback when the explicit bot
    /// `kill` event was lost or arrived late.
    func applyDuelBotStates(_ batch: NetBotStates, seq: UInt32) {
        guard !localMatch.isHost else { return }
        if lastBotStateSeq != 0, seq <= lastBotStateSeq { return }
        lastBotStateSeq = seq
        for state in batch.bots {
            guard let bot = duelBot(netID: state.id) else { continue }
            let position = SIMD3<Float>(state.x, state.y, state.z)
            bot.netTargetPos = position
            bot.netTargetYaw = state.yaw
            bot.netIsMoving = state.moving
            if bot.isDiving != state.diving {
                bot.isDiving = state.diving
                bot.applyDiveVisibility()
            }
            if state.down, !bot.isDown {
                duelBotWentDown(bot, killerIndex: -1)
            } else if !state.down, bot.isDown {
                duelBotRespawned(bot, at: position)
            }
        }
    }

    /// Per-frame puppet driving for the duel bots (guest only): eased blend
    /// toward the latest streamed pose plus run/idle animation.
    func updateDuelBotPuppets(dt: Float) {
        for bot in bots where bot.isNetPuppet && !bot.isDown {
            bot.updateWeaponFollow(dt: dt)
            if bot.isDiving, let form = bot.diveForm {
                let bob = sinf(Float(elapsed) * 9) * 0.08
                form.position = [0, 0.05 + bob, 0]
            }
            guard let target = bot.netTargetPos else { continue }
            let pos = bot.container.position
            if simd_distance(pos, target) > 8 {
                // Teleport (respawn/desync) — never glide across the arena.
                bot.container.position = target
            } else {
                bot.container.position = pos + (target - pos) * min(1, dt * 10)
            }
            let forward = bot.container.orientation.act([0, 0, 1])
            let yaw = Self.lerpAngle(atan2(forward.x, forward.z), bot.netTargetYaw, min(1, dt * 12))
            bot.container.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            if bot.isDiving {
                bot.setLoop(nil)
            } else {
                bot.setLoop(bot.netIsMoving ? (bot.runAnim ?? bot.idleAnim) : bot.idleAnim)
            }
        }
    }

    /// Replays one AI bot discharge with the same ballistics as the local
    /// weapons — paint and player damage resolve in the local simulation
    /// (the guest is the authority on its own HP).
    func spawnDuelBotFire(_ event: NetBotFire) {
        guard !localMatch.isHost, let bot = duelBot(netID: event.id) else { return }
        let origin = SIMD3<Float>(event.ox, event.oy, event.oz)
        var dir = SIMD3<Float>(event.dx, event.dy, event.dz)
        guard simd_length(dir) > 0.001 else { return }
        dir = simd_normalize(dir)
        switch event.kind {
        case .jet:
            spawnJetDrop(at: origin, direction: dir, team: bot.team, weapon: .blaster, ownerIndex: bot.statsIndex)
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
                ownerIndex: bot.statsIndex,
                detonateAt: elapsed + GameConfig.grenadeFuse
            ))
        case .charged:
            // Designated sniper bot shot — identical ballistics to the
            // player's charger, damage derived from the streamed charge.
            let charge = event.charge ?? 0.5
            let speed = GameConfig.chargerMinSpeed
                + (GameConfig.chargerMaxSpeed - GameConfig.chargerMinSpeed) * charge
            let damage = GameConfig.chargerDamage(charge: charge, targetMaxHP: GameConfig.playerMaxHP)
            let radius = GameConfig.chargerMinPaintRadius
                + (GameConfig.chargerMaxPaintRadius - GameConfig.chargerMinPaintRadius) * charge
            spawnPaintDrop(
                at: origin, direction: dir, team: bot.team,
                speed: speed, gravity: GameConfig.chargerShotGravity,
                damage: damage, paintRadius: radius,
                dropScale: 1.3 + charge * 1.2, ownerIndex: bot.statsIndex
            )
        case .bucket:
            // Bots never use the bucket launcher.
            break
        }
        if event.kind != .jet || elapsed - lastJetSfx > 0.14 {
            lastJetSfx = elapsed
            AudioService.shared.playSplat(volume: spatialVolume(0.25, at: origin))
        }
    }

    /// The host announced an AI bot's death (explicit bot `kill` event, or
    /// the state-flag fallback) — splat locally in the killer's colors and
    /// credit the exact fighter attributed by the host.
    func duelBotWentDown(_ bot: BotAgent, killerIndex: Int) {
        guard !bot.isDown else { return }
        bot.isDown = true
        refreshEnemyStatuses()
        let pos = bot.container.position
        let paintTeam: Team = killerIndex >= 0 && killerIndex < liveStats.count
            ? liveStats[killerIndex].team
            : bot.team.opponent
        grid?.paint(atX: pos.x, z: pos.z, radius: GameConfig.killPaintRadius, team: paintTeam)
        recordKill(victimIndex: bot.statsIndex, killerIndex: killerIndex, attackers: [])
        // Only the local player's own kills get the explosion VFX; every other
        // kill plays a lightened splat sound only.
        if killerIndex == 0 {
            spawnKillExplosion(at: pos, team: paintTeam)
        }
        AudioService.shared.playEnemySplat(volume: spatialVolume(killerIndex == 0 ? 1.0 : 0.4, at: pos))
        if killerIndex == 0, bot.statsIndex < liveStats.count {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            showSplatEvent(headline: "Vous avez noyé", name: liveStats[bot.statsIndex].name, isPlayerVictim: false)
        }
        bot.setLoop(nil)
        bot.animator.playOnce(bot.splatAnim, restoreAfter: .milliseconds(900))
        Task { [weak bot] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let bot, bot.isDown else { return }
            bot.container.isEnabled = false
        }
    }

    /// The host respawned an AI bot — bring the puppet back at the streamed
    /// position, fresh and visible.
    func duelBotRespawned(_ bot: BotAgent, at position: SIMD3<Float>) {
        bot.isDown = false
        bot.container.isEnabled = true
        bot.container.position = position
        bot.netTargetPos = position
        bot.isDiving = false
        bot.applyDiveVisibility()
        refreshEnemyStatuses()
    }
}
