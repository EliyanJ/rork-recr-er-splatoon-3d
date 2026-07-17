import Foundation
import RealityKit
import UIKit
import simd

/// Hits, damage feedback, respawns, coverage publishing and stats
/// attribution. Verbatim from `GameController` — no behaviour change.
extension GameController {
    func hitBot(_ bot: BotAgent, at position: SIMD3<Float>, damage: Int, by attacker: Team, ownerIndex: Int = -1) {
        // Total immunity inside the bot's own spawn bubble.
        guard !isProtected(bot.container.position, team: bot.team) else { return }
        // Local duel, guest side: duel-bot puppets are host-simulated —
        // show the hit feedback only, the host's own copy of this projectile
        // applies the real damage on its authoritative roster.
        if isLocalDuel, bot.isNetPuppet {
            botHitFeedback(bot, at: position, attacker: attacker)
            return
        }
        // Local duel: the puppet's real HP lives on the other device —
        // show the hit feedback here and forward the damage to its owner.
        // Only the LOCAL PLAYER's own hits travel as damage messages: AI bot
        // projectiles are replayed on the guest and hurt it there (victim
        // authority), so forwarding those too would double the damage.
        if isLocalDuel, bot === remoteBot {
            botHitFeedback(bot, at: position, attacker: attacker)
            if ownerIndex == 0 {
                localMatch.send(.hit(damage: damage))
            }
            return
        }
        bot.hp -= damage
        bot.lastDamageTime = elapsed
        bot.hpRegenTick = GameConfig.hpRegenInterval
        if ownerIndex >= 0 {
            bot.recentAttackers.insert(ownerIndex)
        }
        guard bot.hp <= 0 else {
            botHitFeedback(bot, at: position, attacker: attacker)
            return
        }
        bot.isDown = true
        bot.respawnTimer = GameConfig.respawnDelay
        refreshEnemyStatuses()
        let gained = grid?.paint(atX: position.x, z: position.z, radius: GameConfig.killPaintRadius, team: attacker) ?? 0
        credit(paint: gained, to: ownerIndex)
        recordKill(victimIndex: bot.statsIndex, killerIndex: ownerIndex, attackers: bot.recentAttackers)
        bot.recentAttackers.removeAll()
        // Host → guest: authoritative AI bot death with exact attribution.
        if isLocalDuel, localMatch.isHost, let netID = bot.netID {
            localMatch.send(.kill(NetKill(
                victim: "bot:\(netID)",
                killer: netFighterRaw(forStatsIndex: ownerIndex)
            )))
        }
        spawnKillExplosion(at: position, team: attacker)
        AudioService.shared.playEnemySplat(volume: spatialVolume(1.0, at: position))
        if bot.team != localTeam, ownerIndex == 0, bot.statsIndex < liveStats.count {
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

    /// Hit reaction on a surviving enemy: ink splash burst + squash flinch,
    /// throttled so the continuous jet doesn't spam animations.
    func botHitFeedback(_ bot: BotAgent, at position: SIMD3<Float>, attacker: Team) {
        guard bot.flinchTimer <= 0 else { return }
        bot.flinchTimer = GameConfig.hitFlinchCooldown
        spawnHitSplash(
            at: position + SIMD3<Float>(0, GameConfig.characterHeight * 0.55, 0),
            team: attacker
        )
        AudioService.shared.playHit(volume: spatialVolume(0.8, at: position))
        bot.animator.playOnce(bot.hitAnim, restoreAfter: .milliseconds(450))

        guard let visual = bot.container.findEntity(named: "generated_model_runtime") else { return }
        let baseTransform = visual.transform
        var squash = baseTransform
        squash.scale = baseTransform.scale * SIMD3<Float>(1.14, 0.82, 1.14)
        visual.move(to: squash, relativeTo: visual.parent, duration: 0.07, timingFunction: .easeOut)
        Task { [weak visual] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let visual else { return }
            visual.move(to: baseTransform, relativeTo: visual.parent, duration: 0.12, timingFunction: .easeOut)
        }
    }

    /// Impact burst on a hit character: expanding ink splash plus a soft
    /// puff of paint mist that drifts up — reads clearly from any distance.
    func spawnHitSplash(at pos: SIMD3<Float>, team: Team) {
        guard let worldRoot, let material = projectileMaterials[team] else { return }
        // The splash + hit-marker flash are the core gameplay readout —
        // "did I just land a hit" — so they ALWAYS spawn, uncapped. Only the
        // purely decorative mist puff below is subject to the transient-VFX
        // budget; losing a few frames of budget is worth it for feedback the
        // player actually needs to see.
        liveTransientVFX += 1
        let vfx = qualitySettings.vfx
        let splash = ModelEntity(mesh: hitSplashMesh, materials: [material])
        splash.position = pos
        worldRoot.addChild(splash)
        var target = splash.transform
        target.scale = [4.4, 4.4, 4.4]
        splash.move(to: target, relativeTo: splash.parent, duration: 0.18, timingFunction: .easeOut)

        // The drifting mist puff is the least essential layer — skipped on
        // Performance/Lite, and gated by the transient-VFX budget so it never
        // competes with the two feedback layers above for entity churn.
        var puff: ModelEntity?
        if vfx == .full, liveTransientVFX < qualitySettings.transientVFXBudget {
            liveTransientVFX += 1
            let puffEntity = ModelEntity(mesh: hitPuffMesh, materials: [hitPuffMaterial])
            puffEntity.position = pos + SIMD3<Float>(0, 0.18, 0)
            worldRoot.addChild(puffEntity)
            var puffTarget = puffEntity.transform
            puffTarget.scale = [2.6, 2.6, 2.6]
            puffTarget.translation.y += 0.5
            puffEntity.move(to: puffTarget, relativeTo: puffEntity.parent, duration: 0.3, timingFunction: .easeOut)
            puff = puffEntity
        }

        // Hitmarker flash à la Fortnite/Apex: a bright WHITE silhouette-sized
        // glow envelops the hit character for ~150 ms — short, punchy, and
        // readable without polluting the screen. Always shown — this is the
        // single clearest "you landed a hit" signal in the whole game.
        let flashEntity = ModelEntity(mesh: hitFlashMesh, materials: [hitFlashMaterial])
        flashEntity.position = pos
        flashEntity.scale = [1.15, GameConfig.characterHeight / (GameConfig.characterHitRadius * 1.6), 1.15]
        worldRoot.addChild(flashEntity)
        var flashTarget = flashEntity.transform
        flashTarget.scale *= 1.15
        flashEntity.move(to: flashTarget, relativeTo: flashEntity.parent, duration: 0.15, timingFunction: .easeOut)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            flashEntity.removeFromParent()
            self?.liveTransientVFX -= 1
            try? await Task.sleep(for: .milliseconds(60))
            splash.removeFromParent()
            try? await Task.sleep(for: .milliseconds(150))
            if let puff {
                puff.removeFromParent()
                self?.liveTransientVFX -= 1
            }
        }
    }

    /// Big celebratory paint explosion at the death point, in the killing
    /// team's color — the reward moment for landing a kill, distinct from
    /// the smaller per-hit splash used while a target is still alive.
    func spawnKillExplosion(at pos: SIMD3<Float>, team: Team) {
        guard let worldRoot, let material = projectileMaterials[team] else { return }
        // Kill explosions are the reward moment — always shown, but still
        // counted against the transient-VFX budget so hit splashes yield.
        liveTransientVFX += 1
        let vfx = qualitySettings.vfx
        let surface = paintSurfaceHeight(atX: pos.x, z: pos.z)

        // Expanding ground ring of ink — always shown, the core kill readout.
        let ring = ModelEntity(mesh: killRingMesh, materials: [material])
        ring.position = [pos.x, surface + 0.05, pos.z]
        ring.scale = [1, 0.25, 1]
        worldRoot.addChild(ring)
        var ringTarget = ring.transform
        ringTarget.scale = [7.5, 0.15, 7.5]
        ring.move(to: ringTarget, relativeTo: ring.parent, duration: 0.42, timingFunction: .easeOut)

        // Vertical plume + flash pop are the extra punch layers — skipped on
        // the lightest preset (kill explosions are rarer than hits, so
        // Performance still keeps them for the celebratory feel).
        var plume: ModelEntity?
        var flash: ModelEntity?
        if vfx != .minimal {
            let plumeEntity = ModelEntity(mesh: killPlumeMesh, materials: [material])
            plumeEntity.position = [pos.x, surface + GameConfig.characterHeight * 0.4, pos.z]
            worldRoot.addChild(plumeEntity)
            var plumeTarget = plumeEntity.transform
            plumeTarget.scale = [2.6, 3.4, 2.6]
            plumeTarget.translation.y += 1.6
            plumeEntity.move(to: plumeTarget, relativeTo: plumeEntity.parent, duration: 0.36, timingFunction: .easeOut)
            plume = plumeEntity

            let flashEntity = ModelEntity(mesh: killFlashMesh, materials: [killFlashMaterial])
            flashEntity.position = [pos.x, surface + GameConfig.characterHeight * 0.5, pos.z]
            worldRoot.addChild(flashEntity)
            var flashTarget = flashEntity.transform
            flashTarget.scale *= 1.3
            flashEntity.move(to: flashTarget, relativeTo: flashEntity.parent, duration: 0.14, timingFunction: .easeOut)
            flash = flashEntity
        }

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            flash?.removeFromParent()
            try? await Task.sleep(for: .milliseconds(280))
            ring.removeFromParent()
            plume?.removeFromParent()
            self?.liveTransientVFX -= 1
        }
    }

    func respawnBot(_ bot: BotAgent) {
        bot.isDown = false
        bot.hp = GameConfig.maxHP
        bot.recentAttackers.removeAll()
        bot.container.isEnabled = true
        bot.container.position = bot.home
        bot.container.orientation = simd_quatf(
            angle: bot.team == .orange ? .pi / 2 : -.pi / 2,
            axis: [0, 1, 0]
        )
        bot.isDiving = false
        bot.applyDiveVisibility()
        newWaypoint(for: bot)
        refreshEnemyStatuses()
    }

    /// Rebuilds the published alive/dead row of the rival team — shown as
    /// head icons at the top center of the HUD.
    func refreshEnemyStatuses() {
        enemyStatuses = bots.filter { $0.team == enemyTeam }.map { bot in
            EnemyStatus(
                id: bot.statsIndex,
                name: liveStats.indices.contains(bot.statsIndex) ? liveStats[bot.statsIndex].name : "Rival",
                isAlive: !bot.isDown
            )
        }
    }

    func hitPlayer(at position: SIMD3<Float>, damage: Int = 1, by attackerIndex: Int = -1) {
        // Total immunity inside the player's own spawn bubble.
        if let pos = playerContainer?.position, isProtected(pos, team: localTeam) { return }
        playerHP = max(0, playerHP - damage)
        damagePulse &+= 1
        if attackerIndex >= 0 {
            playerRecentAttackers.insert(attackerIndex)
        }
        lastDamageTime = elapsed
        hpRegenTick = GameConfig.hpRegenInterval * perks.hpRegenMultiplier
        spawnHitSplash(
            at: position + SIMD3<Float>(0, GameConfig.characterHeight * 0.55, 0),
            team: enemyTeam
        )
        UIImpactFeedbackGenerator(style: playerHP <= 0 ? .heavy : .medium).impactOccurred()
        guard playerHP <= 0 else {
            // Surviving hit: quick flinch reaction, throttled so a continuous
            // jet doesn't lock the body into a stagger loop.
            if playerFlinchTimer <= 0, !isDiving {
                playerFlinchTimer = GameConfig.hitFlinchCooldown + 0.25
                heroAnimator?.playOnce(ModelCatalog.heroHit, restoreAfter: .milliseconds(450))
            }
            return
        }
        sprayCone?.isEnabled = false
        setDiving(false)
        cancelGrenadeAim()
        ziplineRide = nil
        isPlayerDown = true
        isFiring = false
        chargeLevel = 0
        chargeConsumed = false
        respawnTimer = GameConfig.respawnDelay * perks.respawnMultiplier
        respawnCountdown = GameConfig.respawnDelay * perks.respawnMultiplier
        let gained = grid?.paint(atX: position.x, z: position.z, radius: GameConfig.killPaintRadius, team: enemyTeam) ?? 0
        credit(paint: gained, to: attackerIndex)
        recordKill(victimIndex: 0, killerIndex: attackerIndex, attackers: playerRecentAttackers)
        // Explicit kill event — the peer credits the splat to the right
        // fighter instead of guessing from recent hits.
        if isLocalDuel {
            // Killer identity travels as a wire id — the peer's PlayerID or
            // "bot:N" for an AI bot, resolved locally on the other side.
            let killerID = attackerIndex > 0 ? netFighterRaw(forStatsIndex: attackerIndex) : nil
            localMatch.send(.kill(NetKill(victim: localMatch.localPlayerID.raw, killer: killerID)))
        }
        playerRecentAttackers.removeAll()
        spawnKillExplosion(at: position, team: enemyTeam)
        AudioService.shared.playEnemySplat()
        showBanner("Vous êtes éclaboussé !")
        if attackerIndex >= 0, attackerIndex < liveStats.count {
            showSplatEvent(headline: "ÉLIMINÉ PAR", name: liveStats[attackerIndex].name, isPlayerVictim: true)
        }
        heroActiveLoop = nil
        heroAnimator?.setLoop(nil)
        heroAnimator?.playOnce(ModelCatalog.heroSplat, restoreAfter: .milliseconds(1100))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1000))
            guard let self, self.isPlayerDown else { return }
            self.playerContainer?.isEnabled = false
        }
    }

    func respawnPlayer(_ container: Entity) {
        isPlayerDown = false
        playerHP = GameConfig.playerMaxHP
        inkExact = GameConfig.maxInk
        isAirborne = false
        verticalVelocity = 0
        ziplineRide = nil
        lastSafeGround = playerHome
        container.isEnabled = true
        container.position = playerHome
        container.orientation = simd_quatf(angle: baseFacing(for: localTeam), axis: [0, 1, 0])
        cameraYaw = -baseFacing(for: localTeam)
        cameraPitch = 0.02
        targetCameraYaw = -baseFacing(for: localTeam)
        targetCameraPitch = 0.02
        isAutoAligning = false
        // Fresh camera state so the boom doesn't sweep across the arena.
        smoothedPivot = nil
        cameraArm = GameConfig.cameraDistance
        playerRecentAttackers.removeAll()
        wasFiring = false
        chargeLevel = 0
        chargeConsumed = false
        heroSetLoop(heroStandLoop)
    }

    func heroSetLoop(_ resourceName: String?) {
        guard heroActiveLoop != resourceName else { return }
        heroActiveLoop = resourceName
        heroAnimator?.setLoop(resourceName)
    }

    /// True while the player is one skirmish away from going down.
    var isPlayerNearDeath: Bool {
        playerHP <= GameConfig.playerLowHPThreshold
    }

    /// Standing loop: weapon-ready combat stance, or an exhausted
    /// catching-breath pose when health is critically low. Falls back to the
    /// selected skin's own clips first so alt outfits animate correctly.
    var heroStandLoop: String? {
        let skin = ProfileStore.shared.selectedSkin
        if isPlayerNearDeath {
            return skin.injuredIdleAnim ?? ModelCatalog.heroInjuredIdle ?? skin.idleAnim
        }
        return ModelCatalog.heroArmedIdle ?? skin.armedIdleAnim ?? skin.idleAnim ?? ModelCatalog.heroIdle
    }

    /// Run loop: gun carried in both hands for shooter weapons, and an
    /// injured limp when health is critically low.
    var heroRunLoop: String? {
        let skin = ProfileStore.shared.selectedSkin
        if isPlayerNearDeath {
            return skin.injuredRunAnim ?? ModelCatalog.heroInjuredRun ?? skin.runAnim
        }
        return ModelCatalog.heroArmedRun ?? ModelCatalog.heroRun ?? skin.runAnim ?? skin.idleAnim
    }

    // MARK: - Coverage, camera, match end

    func updateCoverage(dt: Double, grid: PaintGrid) {
        coverageTimer -= dt
        guard coverageTimer <= 0 else { return }
        coverageTimer = 0.25
        // Painted turf % is intentionally NOT computed here anymore — it's
        // only ever derived once, from the final grid state, when the match
        // ends (see `finalizeMatch`). That keeps it a surprise at the
        // results screen and skips this division every tick.
        // Stats still publish at a calm cadence so the scoreboard and the
        // top-3 panel never re-render every frame.
        stats = liveStats
    }

    /// Total paintable tiles — the scoreboard's paint-% denominator.
    var arenaTileCount: Int {
        max(grid?.totalCount ?? 1, 1)
    }

    /// Live team kill totals for Duel Mortel — derives straight from the
    /// published `stats` array, so the HUD updates the instant a kill lands.
    var orangeKillScore: Int {
        stats.filter { $0.team == .orange }.reduce(0) { $0 + $1.kills }
    }
    var purpleKillScore: Int {
        stats.filter { $0.team == .purple }.reduce(0) { $0 + $1.kills }
    }

    // MARK: - Stats attribution

    /// Adds freshly-claimed tiles to a fighter's personal paint tally.
    func credit(paint tiles: Int, to index: Int) {
        guard tiles > 0, index >= 0, index < liveStats.count else { return }
        liveStats[index].paintTiles += tiles
    }

    /// Records a splat: death for the victim, kill for the finisher, and an
    /// assist for every other recent attacker. Publishes immediately so the
    /// top-3 panel reacts to kills without waiting for the next tick.
    func recordKill(victimIndex: Int, killerIndex: Int, attackers: Set<Int>) {
        guard victimIndex >= 0, victimIndex < liveStats.count else { return }
        liveStats[victimIndex].deaths += 1
        if killerIndex >= 0, killerIndex < liveStats.count {
            liveStats[killerIndex].kills += 1
        }
        for helper in attackers
        where helper != killerIndex && helper >= 0 && helper < liveStats.count {
            liveStats[helper].assists += 1
        }
        stats = liveStats
    }

}
