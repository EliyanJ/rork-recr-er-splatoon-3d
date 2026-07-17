import Foundation
import RealityKit
import UIKit
import simd

/// Bot AI: per-frame movement, target scan, grenade/fire decisions,
/// tactical diving, dodging, and waypoint selection. Every AI fighter shares
/// the match's frozen `botDifficulty` tier, which tunes aim, reaction speed,
/// dive usage and dodge behaviour.
extension GameController {
    func updateBots(dt: Float, grid: PaintGrid) {
        guard !isMatchOver else { return }
        if isLocalDuel {
            updateRemotePuppet(dt: dt, grid: grid)
            guard localMatch.isHost else {
                // Guest: every AI bot is a network puppet driven by the
                // host's `botState` stream — no local AI at all.
                updateDuelBotPuppets(dt: dt)
                return
            }
            // Host with no lobby bots: only the remote puppet lives in
            // `bots`, nothing to simulate below.
            if !bots.contains(where: { $0.netID != nil }) { return }
        }

        let diff = botDifficulty
        // Duel Mortel: bots hunt kills harder — wider engagement range and a
        // higher chance to actually pull the trigger/lob a grenade when a
        // target is in range, still scaled by the chosen difficulty tier.
        let engageRange = matchMode == .deathmatch ? diff.engageRange * 1.25 : diff.engageRange
        let engagementChance = matchMode == .deathmatch ? min(1, diff.engagementChance * 1.3) : diff.engagementChance

        // Per-fighter velocity estimates (m/s, player = index 0) — harder
        // bots use them to lead their shots at moving targets.
        if dt > 0.0001 {
            if let playerPos = playerContainer?.position {
                let last = fighterLastPositions[0] ?? playerPos
                fighterVelocities[0] = (playerPos - last) / dt
                fighterLastPositions[0] = playerPos
            }
            for bot in bots where !bot.isDown {
                let p = bot.container.position
                let last = fighterLastPositions[bot.statsIndex] ?? p
                fighterVelocities[bot.statsIndex] = (p - last) / dt
                fighterLastPositions[bot.statsIndex] = p
            }
        }

        // Spread the (O(n) target scan) AI decisions across frames so the bots
        // never all evaluate targets in the same image — movement still runs
        // every frame, only the grenade/fire target scan is staggered. The
        // stagger window itself widens on lighter quality presets (bots don't
        // need a 60 Hz reaction time to feel sharp).
        botThinkFrame &+= 1
        let thinkDivisor = max(2, Int((qualitySettings.botThinkInterval / (1.0 / 60.0)).rounded()))
        for (i, bot) in bots.enumerated() {
            // The remote player's puppet is network-driven, never AI-driven.
            if bot === remoteBot { continue }
            let shouldThink = (botThinkFrame &+ i) % thinkDivisor == 0
            if bot.isDown {
                bot.respawnTimer -= Double(dt)
                if bot.respawnTimer <= 0 {
                    respawnBot(bot)
                }
                continue
            }

            bot.updateWeaponFollow(dt: dt)

            let pos = bot.container.position
            // The designated sniper bot knows its rifle's reach — it tracks
            // and engages from much further than the blaster carriers.
            let botRange = bot.currentWeapon == .charger ? max(engageRange * 1.6, 26) : engageRange
            let standing = grid.team(atX: pos.x, z: pos.z)
            bot.waypointTimer -= Double(dt)
            bot.flinchTimer = max(0, bot.flinchTimer - Double(dt))
            bot.diveDecisionTimer -= Double(dt)
            bot.dodgeTimer -= Double(dt)

            // Out-of-combat HP regen, mirroring the player's own recovery —
            // faster while submerged in friendly ink, like a real player.
            if bot.hp < GameConfig.maxHP, elapsed - bot.lastDamageTime > GameConfig.hpRegenDelay {
                bot.hpRegenTick -= Double(dt)
                if bot.hpRegenTick <= 0 {
                    bot.hpRegenTick = (bot.isDiving && standing == bot.team)
                        ? GameConfig.hpRegenInterval * 0.4
                        : GameConfig.hpRegenInterval
                    bot.hp = min(GameConfig.maxHP, bot.hp + 1)
                }
            }

            let hpFraction = Double(bot.hp) / Double(GameConfig.maxHP)

            // MARK: Tactical dive decision — travel faster on friendly paint,
            // retreat-heal when low, or stay submerged (stealth) until a
            // target strays close enough to ambush.
            if bot.diveDecisionTimer <= 0 {
                bot.diveDecisionTimer = Double.random(in: 0.5...0.9)
                if bot.isDiving {
                    let target = nearestOpponentPosition(for: bot, from: pos, within: botRange)
                    let closeEnough = target.map { simd_distance($0, pos) < diff.engageRange * 0.55 } ?? false
                    let stillFleeing = hpFraction <= diff.fleeHPThreshold
                    if standing != bot.team || (closeEnough && !stillFleeing) {
                        bot.isDiving = false
                        bot.applyDiveVisibility()
                    }
                } else if standing == bot.team {
                    let wantsToFlee = hpFraction <= diff.fleeHPThreshold
                    let wantsToTravel = Double.random(in: 0...1) < diff.diveTravelChance
                    if wantsToFlee || wantsToTravel {
                        bot.isDiving = true
                        bot.applyDiveVisibility()
                    }
                }
            } else if bot.isDiving, standing != bot.team {
                // Swam off friendly ink mid-dive — pop straight back up.
                bot.isDiving = false
                bot.applyDiveVisibility()
            }

            // Follow the A* route node by node; pick a fresh destination on
            // arrival or when the roam timer expires.
            let toWaypoint = SIMD2<Float>(bot.waypoint.x - pos.x, bot.waypoint.z - pos.z)
            if simd_length(toWaypoint) < 0.8 || bot.waypointTimer <= 0 {
                newWaypoint(for: bot)
            }
            while bot.pathIndex < bot.path.count {
                let node = bot.path[bot.pathIndex]
                guard simd_length(SIMD2<Float>(node.x - pos.x, node.z - pos.z)) < 0.7 else { break }
                bot.pathIndex += 1
            }
            let steerTarget = bot.pathIndex < bot.path.count ? bot.path[bot.pathIndex] : bot.waypoint

            var dir = steerTarget - pos
            dir.y = 0
            guard simd_length(dir) > 0.001 else { continue }
            dir = simd_normalize(dir)

            // Harder bots strafe sideways while an opponent is in range
            // instead of walking a straight line into return fire.
            // The O(n) scan only runs on this bot's think frames — running
            // it every frame for every bot was a hidden O(n²) cost.
            if shouldThink || !bot.hasEngagedScan {
                bot.cachedEngagedTarget = nearestOpponentPosition(for: bot, from: pos, within: botRange)
                bot.hasEngagedScan = true
            }
            let engagedTarget = bot.cachedEngagedTarget
            // The strafe decision is rolled ONCE per dodge window — rolling
            // it per frame made the heading flip dozens of times a second,
            // which is exactly the "vibrating / looking everywhere" glitch.
            if !bot.isDiving, engagedTarget != nil, diff.dodgeChance > 0 {
                if bot.dodgeTimer <= 0 {
                    bot.dodgeTimer = Double.random(in: 0.6...1.1)
                    bot.dodgeSign = Bool.random() ? 1 : -1
                    bot.dodgeActive = Double.random(in: 0...1) < diff.dodgeChance
                }
                if bot.dodgeActive {
                    let perp = SIMD3<Float>(-dir.z, 0, dir.x) * bot.dodgeSign
                    dir = simd_normalize(dir + perp * 0.6)
                }
            } else {
                bot.dodgeActive = false
            }

            // Look-ahead wall probe: if the next step ahead is inside a
            // blocker (dynamic shield wall, geometry the dodge pushed us
            // toward), steer along the wall tangent instead of pushing into
            // it — no more face-first sprinting into walls.
            let probe = pos + dir * 0.9
            let resolvedProbe = resolveObstacles(probe, currentY: pos.y, team: bot.team)
            let probePush = SIMD2<Float>(resolvedProbe.x - probe.x, resolvedProbe.z - probe.z)
            if simd_length(probePush) > 0.04 {
                let normal = simd_normalize(probePush)
                var tangent = SIMD3<Float>(-normal.y, 0, normal.x)
                if simd_dot(tangent, dir) < 0 { tangent = -tangent }
                dir = simd_normalize(dir * 0.25 + tangent * 0.75)
            }

            var speed = GameConfig.botSpeed * diff.moveSpeedMultiplier
            if bot.isDiving {
                if standing == bot.team {
                    speed *= GameConfig.swimBoost
                } else if standing != nil {
                    speed *= GameConfig.swimEnemyPaintPenalty
                } else {
                    speed *= GameConfig.swimNeutralPenalty
                }
            } else if standing == bot.team {
                speed *= GameConfig.ownPaintWalkBoost
            } else if standing != nil {
                speed *= GameConfig.enemyPaintPenalty
            }

            var next = pos + dir * speed * dt
            next = clampToArena(next)
            next = resolveObstacles(next, currentY: pos.y, team: bot.team)
            next = resolveRamps(next, currentY: pos.y)
            next = resolveWater(next, currentY: pos.y)
            // The opposing spawn bubble is a hard wall for bots too.
            next = pushOutOfEnemyZone(next, team: bot.team)
            next.y = settledHeight(from: pos.y, atX: next.x, z: next.z, dt: dt)

            // Stuck recovery: trying to move but barely progressing means the
            // bot is grinding against geometry. First re-path to the same
            // waypoint from here; if that still doesn't free it, abandon the
            // destination entirely.
            let movedFlat = simd_length(SIMD2<Float>(next.x - pos.x, next.z - pos.z))
            let intendedStep = speed * dt
            var isBlocked = intendedStep > 0.0001 && movedFlat < intendedStep * 0.3
            // Ledge scramble: while working a climb route (elevated zone
            // target), a bot pinned against a small lip right under its next
            // elevated node hoists itself over it instead of grinding — the
            // bot equivalent of a quick mantle. Prevents the "vibrating at
            // the summit edge" bug on any leftover geometry seam.
            if isBlocked, bot.waypoint.y > 1.0, steerTarget.y > pos.y + 0.25,
               simd_length(SIMD2<Float>(steerTarget.x - pos.x, steerTarget.z - pos.z)) < 2.4 {
                next.y = min(steerTarget.y, pos.y + 3.0 * dt)
                isBlocked = false
                bot.stuckTime = 0
            }
            if isBlocked {
                bot.stuckTime += Double(dt)
                if bot.stuckTime > 0.5 {
                    bot.stuckTime = 0
                    bot.repathAttempts += 1
                    if bot.repathAttempts >= 2 {
                        bot.repathAttempts = 0
                        newWaypoint(for: bot)
                    } else if bot.waypoint.y > 1.0, assignZoneClimbRoute(for: bot, to: bot.waypoint) {
                        // Elevated zone target: re-run the scripted climb
                        // instead of ground A* (which can't see platforms
                        // and would beeline into the pyramid wall).
                    } else {
                        assignPath(for: bot, to: bot.waypoint)
                    }
                }
            } else {
                bot.stuckTime = 0
                if movedFlat > intendedStep * 0.7 { bot.repathAttempts = 0 }
            }

            bot.container.position = next
            bot.face(dir, dt: dt)
            if bot.isDiving {
                bot.setLoop(nil)
            } else if isBlocked {
                // Never play the sprint cycle while pinned against geometry —
                // that's the "running into the wall" glitch. Idle reads calm
                // and intentional for the split second before the repath.
                bot.setLoop(bot.idleAnim)
            } else {
                // Near-death bots limp so their remaining health reads at a glance.
                bot.setLoop(
                    bot.isNearDeath
                        ? (bot.injuredRunAnim ?? bot.runAnim ?? bot.idleAnim)
                        : (bot.runAnim ?? bot.idleAnim)
                )
            }

            // Submerged bots stay out of the fight entirely — no weapon, no
            // grenade, just travel, stealth and healing until they surface.
            guard !bot.isDiving else { continue }

            // Paint grenade: bots use the grenade mechanic like the player —
            // a fixed-fuse lob toward a mid-range opponent.
            bot.grenadeCooldown -= Double(dt)
            if bot.grenadeCooldown <= 0, shouldThink, Double.random(in: 0...1) < engagementChance,
               let target = nearestOpponentPosition(for: bot, from: pos, within: botRange) {
                let flat = SIMD2<Float>(target.x - pos.x, target.z - pos.z)
                if simd_length(flat) > 5 {
                    bot.grenadeCooldown = Double.random(in: diff.grenadeCooldownRange)
                    let lob = simd_normalize(SIMD3<Float>(flat.x, 0, flat.y))
                    let grenadeOrigin = pos + SIMD3<Float>(0, GameConfig.characterHeight * 0.8, 0) + lob * 0.5
                    let entity = makeGrenadeEntity()
                    entity.position = grenadeOrigin
                    worldRoot?.addChild(entity)
                    projectiles.append(Projectile(
                        entity: entity,
                        velocity: lob * GameConfig.grenadeSpeed + SIMD3<Float>(0, 5.2, 0),
                        team: bot.team,
                        kind: .grenade,
                        gravity: 9.5,
                        damage: GameConfig.grenadePlayerDamage,
                        paintRadius: GameConfig.grenadePaintRadius,
                        ownerIndex: bot.statsIndex,
                        detonateAt: elapsed + GameConfig.grenadeFuse
                    ))
                    AudioService.shared.playSplat(volume: spatialVolume(0.4, at: pos))
                    sendDuelBotFire(bot, kind: .grenade, origin: grenadeOrigin, direction: lob)
                }
            }

            bot.fireCooldown -= Double(dt)
            if bot.fireCooldown <= 0, shouldThink, Double.random(in: 0...1) < engagementChance {
                if bot.currentWeapon == .charger {
                    fireSniperShot(from: bot, at: pos, range: botRange, diff: diff, dt: dt)
                    continue
                }
                bot.fireCooldown = Double.random(in: diff.fireCooldownRange)
                var aim = dir
                let socketOrigin = bot.weaponSocket?.position(relativeTo: nil)
                let muzzle = socketOrigin ?? pos + SIMD3<Float>(0, GameConfig.weaponSocketPosition.y + 0.06, 0)
                if let target = nearestOpponentTarget(for: bot, from: pos, within: botRange) {
                    // Harder bots lead the shot: aim where the target will be
                    // when the jet arrives, not where it is right now.
                    var aimPoint = target.position
                    if diff.aimLeadFactor > 0, var velocity = fighterVelocities[target.statsIndex] {
                        velocity.y = 0
                        let velocityLength = simd_length(velocity)
                        if velocityLength > 0.05 {
                            let travelTime = simd_distance(pos, target.position) / WeaponType.blaster.projectileSpeed
                            let leadLength = min(velocityLength * travelTime * diff.aimLeadFactor, 3.5)
                            aimPoint += (velocity / velocityLength) * leadLength
                        }
                    }
                    var toTarget = aimPoint - pos
                    if diff.aimsVertically {
                        // Elite tier: full 3D aim with ballistic-drop
                        // compensation — a target perched on a platform gets
                        // hit dead-on instead of being safely out of plane.
                        toTarget = (aimPoint + SIMD3<Float>(0, GameConfig.characterHeight * 0.55, 0)) - muzzle
                        let travelTime = simd_length(toTarget) / WeaponType.blaster.projectileSpeed
                        toTarget.y += 0.5 * WeaponType.blaster.projectileGravity * travelTime * travelTime * 0.85
                    } else {
                        toTarget.y = 0
                    }
                    if simd_length(toTarget) > 0.001 {
                        aim = simd_normalize(toTarget)
                        aim += SIMD3<Float>(Float.random(in: -diff.aimSpread...diff.aimSpread), 0, Float.random(in: -diff.aimSpread...diff.aimSpread))
                        aim = simd_normalize(aim)
                        // Fast but still smoothed turn toward the shot — the
                        // projectile aim stays exact, only the body rotation
                        // is eased so it never snaps.
                        bot.face(aim, dt: dt, turnRate: 15)
                    }
                }
                // Jet leaves at the bot's tracked weapon position, matching the player.
                let jetOrigin = muzzle + aim * 0.6
                spawnJetDrop(
                    at: jetOrigin,
                    direction: aim,
                    team: bot.team,
                    weapon: .blaster,
                    ownerIndex: bot.statsIndex
                )
                sendDuelBotFire(bot, kind: .jet, origin: jetOrigin, direction: aim)
            }
        }
    }

    /// One picked charger shot from the designated sniper bot — full 3D aim
    /// (lead + gravity-drop compensation, it knows its rifle), charge level
    /// and cadence scaled by the difficulty tier. At 50%+ charge the shot
    /// one-shots per the charger rule, so only elite snipers do reliably.
    func fireSniperShot(
        from bot: BotAgent,
        at pos: SIMD3<Float>,
        range: Float,
        diff: BotDifficulty,
        dt: Float
    ) {
        guard let target = nearestOpponentTarget(for: bot, from: pos, within: range) else {
            // No target in scope — re-scan again shortly instead of wasting
            // the full sniper cooldown on an empty lane.
            bot.fireCooldown = 0.35
            return
        }
        bot.fireCooldown = Double.random(in: diff.sniperFireCooldownRange)
        let charge = Float.random(in: diff.sniperChargeRange)
        let speed = GameConfig.chargerMinSpeed
            + (GameConfig.chargerMaxSpeed - GameConfig.chargerMinSpeed) * charge

        let socketOrigin = bot.weaponSocket?.position(relativeTo: nil)
        let muzzle = socketOrigin ?? pos + SIMD3<Float>(0, GameConfig.weaponSocketPosition.y + 0.06, 0)

        // Aim at the chest, lead the movement, then compensate the (nearly
        // flat) charger ballistics for the travel distance.
        var aimPoint = target.position + SIMD3<Float>(0, GameConfig.characterHeight * 0.55, 0)
        if diff.aimLeadFactor > 0, var velocity = fighterVelocities[target.statsIndex] {
            velocity.y = 0
            let velocityLength = simd_length(velocity)
            if velocityLength > 0.05 {
                let travelTime = simd_distance(pos, target.position) / speed
                let leadLength = min(velocityLength * travelTime * diff.aimLeadFactor, 4.5)
                aimPoint += (velocity / velocityLength) * leadLength
            }
        }
        var toTarget = aimPoint - muzzle
        let travelTime = simd_length(toTarget) / speed
        toTarget.y += 0.5 * GameConfig.chargerShotGravity * travelTime * travelTime
        guard simd_length(toTarget) > 0.001 else { return }
        var aim = simd_normalize(toTarget)
        let spread = diff.aimSpread * 0.6
        aim += SIMD3<Float>(
            Float.random(in: -spread...spread),
            Float.random(in: -spread...spread) * 0.5,
            Float.random(in: -spread...spread)
        )
        aim = simd_normalize(aim)
        bot.face(aim, dt: dt, turnRate: 15)

        let damage = GameConfig.chargerDamage(
            charge: charge,
            targetMaxHP: target.statsIndex == 0 ? GameConfig.playerMaxHP : GameConfig.maxHP
        )
        let radius = GameConfig.chargerMinPaintRadius
            + (GameConfig.chargerMaxPaintRadius - GameConfig.chargerMinPaintRadius) * charge
        let origin = muzzle + aim * 0.7
        spawnPaintDrop(
            at: origin, direction: aim, team: bot.team,
            speed: speed, gravity: GameConfig.chargerShotGravity,
            damage: damage, paintRadius: radius,
            dropScale: 1.3 + charge * 1.2, ownerIndex: bot.statsIndex
        )
        AudioService.shared.playSplat(volume: spatialVolume(0.35, at: pos))
        sendDuelBotFire(bot, kind: .charged, origin: origin, direction: aim, charge: charge)
    }

    /// Closest live opposing character (player counts for purple bots).
    /// Diving fighters are submerged/stealthed and never register as a
    /// target — for bots scanning AND for the player being scanned.
    func nearestOpponentPosition(
        for bot: BotAgent,
        from pos: SIMD3<Float>,
        within range: Float
    ) -> SIMD3<Float>? {
        nearestOpponentTarget(for: bot, from: pos, within: range)?.position
    }

    /// Same scan as `nearestOpponentPosition` but also identifies WHO the
    /// target is (statsIndex, player = 0) so aiming can look up its velocity
    /// and lead the shot.
    func nearestOpponentTarget(
        for bot: BotAgent,
        from pos: SIMD3<Float>,
        within range: Float
    ) -> (position: SIMD3<Float>, statsIndex: Int)? {
        var best: (position: SIMD3<Float>, statsIndex: Int)?
        var bestDist = range
        // Fighters standing inside their own spawn bubble are never targeted
        // — bots don't waste shots on protected opponents.
        if bot.team == enemyTeam, !isPlayerDown, !isDiving, let playerPos = playerContainer?.position,
           !isProtected(playerPos, team: localTeam) {
            let dist = simd_distance(pos, playerPos)
            if dist < bestDist {
                best = (playerPos, 0)
                bestDist = dist
            }
        }
        for other in bots where other !== bot && !other.isDown && !other.isDiving && other.team != bot.team {
            guard !isProtected(other.container.position, team: other.team) else { continue }
            let dist = simd_distance(pos, other.container.position)
            if dist < bestDist {
                best = (other.container.position, other.statsIndex)
                bestDist = dist
            }
        }
        return best
    }

    func newWaypoint(for bot: BotAgent) {
        bot.waypointTimer = Double.random(in: 3.5...6.5)
        bot.stuckTime = 0

        // The designated sniper bot spends most of its time on the map's
        // vantage perches, overwatching the lanes — it only occasionally
        // drops down to roam, contest a zone or hunt like the others.
        if bot.currentWeapon == .charger, Double.random(in: 0...1) < 0.75,
           assignSniperPerch(for: bot) {
            return
        }

        // Contrôle de Zones: bots actively path toward the most valuable
        // capture zone instead of roaming randomly — how often they bother
        // scales with the chosen bot difficulty.
        if matchMode == .zoneControl, Double.random(in: 0...1) < botDifficulty.engagementChance,
           let zoneTarget = bestZoneWaypoint(for: bot) {
            if zoneTarget.y > 1.0, assignZoneClimbRoute(for: bot, to: zoneTarget) {
                return
            }
            assignPath(for: bot, to: zoneTarget)
            return
        }

        // Duel Mortel: hunt — route toward the nearest visible opponent's
        // area (orbit offset so the approach isn't a straight beeline).
        if matchMode == .deathmatch, Double.random(in: 0...1) < botDifficulty.engagementChance * 0.85,
           let hunt = huntWaypoint(for: bot) {
            assignPath(for: bot, to: hunt)
            return
        }

        // Default roaming: mostly travel between the arena's patrol points
        // (open lanes/plazas computed at match start) so movement reads as
        // deliberate routes; occasionally a random unpainted spot instead.
        if !botPatrolPoints.isEmpty, Double.random(in: 0...1) < 0.65 {
            let pos = bot.container.position
            let options = botPatrolPoints.filter {
                simd_length(SIMD2<Float>($0.x - pos.x, $0.z - pos.z)) > 4
                    && !isProtected($0, team: bot.team.opponent)
            }
            if let choice = options.randomElement() {
                let jitter = SIMD3<Float>(Float.random(in: -1.2...1.2), 0, Float.random(in: -1.2...1.2))
                assignPath(for: bot, to: clampToArena(choice + jitter))
                return
            }
        }

        let halfW = GameConfig.arenaWidth / 2 - 1.4
        let halfD = GameConfig.arenaDepth / 2 - 1.4
        var chosen = SIMD3<Float>(Float.random(in: -halfW...halfW), 0, Float.random(in: -halfD...halfD))
        for _ in 0..<6 {
            let candidate = SIMD3<Float>(Float.random(in: -halfW...halfW), 0, Float.random(in: -halfD...halfD))
            chosen = candidate
            if grid?.team(atX: candidate.x, z: candidate.z) != bot.team,
               !isProtected(candidate, team: bot.team.opponent),
               !isInWater(x: candidate.x, z: candidate.z) {
                break
            }
        }
        // Never path into the opposing spawn bubble — pull the point back
        // toward the middle of the arena instead.
        if isProtected(chosen, team: bot.team.opponent) {
            chosen.x *= 0.45
        }
        // Never aim a waypoint into a water pool either.
        if isInWater(x: chosen.x, z: chosen.z) {
            chosen.x *= 0.4
            chosen.z *= 0.4
        }
        assignPath(for: bot, to: chosen)
    }

    /// Duel Mortel hunting destination: a point orbiting the nearest visible
    /// opponent at combat range — the bot closes in without walking a
    /// perfectly straight, predictable line.
    func huntWaypoint(for bot: BotAgent) -> SIMD3<Float>? {
        guard let target = nearestOpponentPosition(for: bot, from: bot.container.position, within: 1000) else {
            return nil
        }
        let angle = Float.random(in: 0..<(2 * .pi))
        let orbit = Float.random(in: 2.5...5)
        return clampToArena(target + SIMD3<Float>(cos(angle) * orbit, 0, sin(angle) * orbit))
    }

    /// Contrôle de Zones targeting — ONE fighter per zone maximum.
    ///
    /// Each zone counts its "committed" allies: anyone standing inside it OR
    /// already routing toward it. Zones with zero commitment score highest
    /// (free points or a retake), covered zones score rock-bottom so the bot
    /// leaves them to the ally on duty. When EVERY zone is already covered,
    /// the bot flips to defense: it intercepts the closest enemy threatening
    /// one of the held zones, and if nobody threatens anything it returns nil
    /// and falls back to natural patrol roaming — no more everyone
    /// sprinting at the same objective in a single-minded conga line.
    func bestZoneWaypoint(for bot: BotAgent) -> SIMD3<Float>? {
        guard !captureZoneVisuals.isEmpty else { return nil }

        var infos: [(zone: CaptureZoneVisual, friendlyCommitted: Int, enemy: Int)] = []
        for zone in captureZoneVisuals {
            var friendly = 0
            var enemy = 0
            for other in bots where other !== bot && !other.isDown {
                if captureZoneContains(other.container.position, zone: zone) {
                    if other.team == bot.team { friendly += 1 } else { enemy += 1 }
                } else if other.team == bot.team, !other.isNetPuppet,
                          simd_length(SIMD2<Float>(other.waypoint.x - zone.center.x, other.waypoint.z - zone.center.z)) < zone.radius + 0.6 {
                    // Ally already en route to this zone counts as committed.
                    friendly += 1
                }
            }
            if !isPlayerDown, let pos = playerContainer?.position,
               captureZoneContains(pos, zone: zone) {
                if localTeam == bot.team { friendly += 1 } else { enemy += 1 }
            }
            infos.append((zone, friendly, enemy))
        }

        var best: (zone: CaptureZoneVisual, score: Double)?
        for info in infos {
            var score: Double
            if info.friendlyCommitted == 0 {
                // Free zone or a retake — top priority either way.
                score = info.enemy > 0 ? 9 : 10
            } else {
                // An ally is on it (or heading there): leave it to them.
                score = 1
            }
            score += Double.random(in: 0...0.8)
            if best == nil || score > best!.score {
                best = (info.zone, score)
            }
        }
        if let best, best.score >= 5 {
            let angle = Float.random(in: 0..<(2 * .pi))
            let dist = Float.random(in: 0...(best.zone.radius * 0.6))
            return best.zone.center + SIMD3<Float>(cos(angle) * dist, 0, sin(angle) * dist)
        }

        // Every zone is covered — defend: intercept the nearest enemy
        // closing in on one of the zones an ally is holding.
        var intercept: (point: SIMD3<Float>, threat: Float)?
        for info in infos where info.friendlyCommitted > 0 {
            var enemies: [SIMD3<Float>] = bots
                .filter { $0 !== bot && !$0.isDown && !$0.isDiving && $0.team != bot.team }
                .map { $0.container.position }
            if bot.team == enemyTeam, !isPlayerDown, !isDiving, let playerPos = playerContainer?.position {
                enemies.append(playerPos)
            }
            for enemyPos in enemies {
                let toZone = simd_length(SIMD2<Float>(enemyPos.x - info.zone.center.x, enemyPos.z - info.zone.center.z))
                guard toZone < 15, toZone > info.zone.radius else { continue }
                if intercept == nil || toZone < intercept!.threat {
                    // Cut the attacker off between them and the zone edge.
                    let midpoint = (enemyPos + info.zone.center) * 0.5
                    intercept = (clampToArena(SIMD3<Float>(midpoint.x, 0, midpoint.z)), toZone)
                }
            }
        }
        return intercept?.point
    }

    /// Elevated overwatch spots per map, each with its scripted access route
    /// (ground entry → ramp → perch) — the same node-following mechanics as
    /// the zone climb routes, so ground A* handles the approach and the
    /// scripted nodes handle the ascent.
    var sniperPerchRoutes: [[SIMD3<Float>]] {
        switch GameConfig.currentMap {
        case .nexusDocks:
            [
                // West control deck (+2.5) via its outer ramp.
                [SIMD3<Float>(-21.5, 0, -13.5), SIMD3<Float>(-18, 2.5, -13.5), SIMD3<Float>(-13, 2.5, -13.5)],
                // East control deck (+2.5), mirrored.
                [SIMD3<Float>(21.5, 0, -13.5), SIMD3<Float>(18, 2.5, -13.5), SIMD3<Float>(13, 2.5, -13.5)],
            ]
        case .templeLost:
            [
                // West corner of the pyramid base deck (+2) via the grand stair.
                [SIMD3<Float>(-13.5, 0, 0), SIMD3<Float>(-9.5, 1, 0), SIMD3<Float>(-6, 2, 0), SIMD3<Float>(-5.5, 2, -3.4)],
                // East corner, mirrored on the other diagonal.
                [SIMD3<Float>(13.5, 0, 0), SIMD3<Float>(9.5, 1, 0), SIMD3<Float>(6, 2, 0), SIMD3<Float>(5.5, 2, 3.4)],
            ]
        }
    }

    /// Routes the sniper bot to (or keeps it shuffling around) an elevated
    /// perch. Returns false when the map has no perch data.
    func assignSniperPerch(for bot: BotAgent) -> Bool {
        let routes = sniperPerchRoutes
        guard !routes.isEmpty else { return false }
        let pos = bot.container.position

        // Already posted on a perch: hold the position, shuffling a little
        // so the silhouette keeps living instead of freezing statue-still.
        for route in routes {
            guard let perch = route.last else { continue }
            if abs(pos.y - perch.y) < 0.8,
               simd_length(SIMD2<Float>(pos.x - perch.x, pos.z - perch.z)) < 3 {
                var hold = perch + SIMD3<Float>(Float.random(in: -1.2...1.2), 0, Float.random(in: -1.2...1.2))
                hold.y = perch.y
                bot.path = [hold]
                bot.pathIndex = 0
                bot.waypoint = hold
                bot.waypointTimer = Double.random(in: 6...10)
                return true
            }
        }

        // Head for the nearest perch: real ground A* to the route entry,
        // then the scripted ramp nodes up to the vantage point.
        var bestRoute: [SIMD3<Float>]?
        var bestDist = Float.greatestFiniteMagnitude
        for route in routes {
            guard let entry = route.first else { continue }
            let d = simd_length(SIMD2<Float>(entry.x - pos.x, entry.z - pos.z))
            if d < bestDist {
                bestDist = d
                bestRoute = route
            }
        }
        guard let route = bestRoute, let perch = route.last else { return false }
        var full: [SIMD3<Float>] = []
        if pos.y < 1.0, let entry = route.first, entry.y < 1.0 {
            full = findBotPath(from: pos, to: entry)
        }
        full.append(contentsOf: route)
        bot.path = full
        bot.pathIndex = 0
        bot.waypoint = perch
        // The walk + climb takes a while — don't abandon it halfway up.
        bot.waypointTimer = Double.random(in: 12...16)
        return true
    }

    /// Installs a scripted climbing path toward an ELEVATED zone target
    /// (Temple Lost summit). Picks the route whose entry is closest, resumes
    /// mid-route when the bot is already partway up, and prefixes a real A*
    /// leg from the bot's position to the route entry on the ground.
    /// Returns false when the map has no climb routes (ground zones).
    func assignZoneClimbRoute(for bot: BotAgent, to target: SIMD3<Float>) -> Bool {
        guard !zoneClimbRoutes.isEmpty else { return false }
        let pos = bot.container.position

        // Already at summit altitude: just a short hop inside the zone.
        if abs(pos.y - target.y) < 1.2 {
            bot.path = [target]
            bot.pathIndex = 0
            bot.waypoint = target
            return true
        }

        var bestRoute: [SIMD3<Float>]?
        var bestDist = Float.greatestFiniteMagnitude
        for route in zoneClimbRoutes {
            guard let entry = route.first else { continue }
            let d = simd_length(SIMD2<Float>(entry.x - pos.x, entry.z - pos.z))
            if d < bestDist {
                bestDist = d
                bestRoute = route
            }
        }
        guard let route = bestRoute else { return false }

        // Resume from the nearest node at (or below) the bot's current
        // altitude — a bot already on the base deck skips the ground stair.
        var startIndex = 0
        var nearest = Float.greatestFiniteMagnitude
        for (index, node) in route.enumerated() where node.y <= pos.y + 0.6 {
            let d = simd_length(SIMD2<Float>(node.x - pos.x, node.z - pos.z))
            if d < nearest {
                nearest = d
                startIndex = index
            }
        }
        let remaining = Array(route[startIndex...])

        var full: [SIMD3<Float>] = []
        if pos.y < 1.0, let entry = remaining.first, entry.y < 1.0 {
            // Real ground pathfinding to the stair entrance — walls, water
            // and crates still get routed around properly.
            full = findBotPath(from: pos, to: entry)
        }
        full.append(contentsOf: remaining)
        full.append(target)

        bot.path = full
        bot.pathIndex = 0
        bot.waypoint = target
        // A full climb takes longer than a flat stroll — don't let the roam
        // timer abandon the ascent halfway up.
        bot.waypointTimer = Double.random(in: 10...14)
        return true
    }
}
