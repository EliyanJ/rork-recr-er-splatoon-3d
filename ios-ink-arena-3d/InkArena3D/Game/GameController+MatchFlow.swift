import Foundation
import RealityKit
import UIKit
import simd

/// Spawn zones, protection, camera rig, aim-lock, banners and match-end
/// flow. Verbatim from `GameController` — no behaviour change.
extension GameController {
    /// Translucent team-colored bubbles marking the protected spawn areas.
    func buildSpawnZones(_ root: Entity) {
        let halfW = GameConfig.arenaWidth / 2
        spawnZoneCenters[.orange] = [-(halfW - 2.2), 0, 0]
        spawnZoneCenters[.purple] = [halfW - 2.2, 0, 0]

        for team in [Team.orange, Team.purple] {
            guard let center = spawnZoneCenters[team] else { continue }
            // Field bubble — bumped up from a barely-there 0.11 so the
            // protected zone actually reads as "claimed territory" instead
            // of a faint tint.
            var bubbleMaterial = UnlitMaterial(color: team.uiColor)
            bubbleMaterial.blending = .transparent(opacity: 0.2)
            let bubble = ModelEntity(
                mesh: .generateSphere(radius: GameConfig.spawnZoneRadius),
                materials: [bubbleMaterial]
            )
            bubble.position = [center.x, 0.05, center.z]
            root.addChild(bubble)

            var discMaterial = UnlitMaterial(color: team.uiColor)
            discMaterial.blending = .transparent(opacity: 0.26)
            let disc = ModelEntity(
                mesh: .generateCylinder(height: 0.03, radius: GameConfig.spawnZoneRadius),
                materials: [discMaterial]
            )
            disc.position = [center.x, 0.05, center.z]
            root.addChild(disc)

            // Bright boundary ring right at the edge of the bubble — a sharp,
            // saturated contour so the border is unmistakable from any angle
            // (ground-level readability was the main complaint, not the fill).
            var ringMaterial = UnlitMaterial(color: team.uiColor)
            ringMaterial.blending = .transparent(opacity: 0.6)
            let ring = ModelEntity(
                mesh: .generateCylinder(height: 0.06, radius: GameConfig.spawnZoneRadius + 0.05),
                materials: [ringMaterial]
            )
            ring.position = [center.x, 0.07, center.z]
            ring.scale = [1, 1, 1]
            root.addChild(ring)
            // Hollow out the ring's center visually by masking it with a
            // slightly-smaller, near-opaque disc of the SAME material as the
            // ground disc above — leaves only a thin bright band showing.
            var ringMaskMaterial = UnlitMaterial(color: team.uiColor)
            ringMaskMaterial.blending = .transparent(opacity: 0.26)
            let ringMask = ModelEntity(
                mesh: .generateCylinder(height: 0.08, radius: GameConfig.spawnZoneRadius - 0.18),
                materials: [ringMaskMaterial]
            )
            ringMask.position = [center.x, 0.08, center.z]
            root.addChild(ringMask)

            // Waist-high force-field wall so the zone reads clearly from the
            // player's own eye level too, not just from above.
            var wallMaterial = UnlitMaterial(color: team.uiColor)
            wallMaterial.blending = .transparent(opacity: 0.16)
            let wall = ModelEntity(
                mesh: .generateCylinder(height: 2.2, radius: GameConfig.spawnZoneRadius),
                materials: [wallMaterial]
            )
            wall.position = [center.x, 1.1, center.z]
            root.addChild(wall)
        }
    }

    /// True when `position` is inside `team`'s protected spawn bubble.
    func isProtected(_ position: SIMD3<Float>, team: Team) -> Bool {
        guard let center = spawnZoneCenters[team] else { return false }
        return simd_length(SIMD2<Float>(position.x - center.x, position.z - center.z))
            < GameConfig.spawnZoneRadius
    }

    /// Pushes a character of `team` out of the OPPOSING spawn bubble — the
    /// zone is a soft wall enemies physically cannot enter.
    func pushOutOfEnemyZone(_ position: SIMD3<Float>, team: Team) -> SIMD3<Float> {
        guard let center = spawnZoneCenters[team.opponent] else { return position }
        let offset = SIMD2<Float>(position.x - center.x, position.z - center.z)
        let distance = simd_length(offset)
        guard distance < GameConfig.spawnZoneRadius else { return position }
        let direction = distance > 0.001
            ? offset / distance
            : SIMD2<Float>(team == .orange ? -1 : 1, 0)
        let radius = GameConfig.spawnZoneRadius + GameConfig.spawnZoneMargin
        var pos = position
        pos.x = center.x + direction.x * radius
        pos.z = center.z + direction.y * radius
        return clampToArena(pos)
    }

    /// Immersive camera. Third person: close over-the-shoulder framing just
    /// above/behind the head, weapon and part of the body in view. First
    /// person: the camera sits at the character's eyes — true POV.
    func updateCamera(dt: Float, target: SIMD3<Float>, camera: PerspectiveCamera) {
        let look = aimVector()

        // Long-Shot optical zoom: the field of view narrows progressively
        // while the charge fills, then eases back after the shot.
        let zoomTarget: Float
        if weapon == .charger, isFiring, !isDiving, !isPlayerDown, !isMatchOver {
            let t = 0.35 + 0.65 * chargeLevel
            zoomTarget = GameConfig.cameraFieldOfView
                - (GameConfig.cameraFieldOfView - GameConfig.chargerZoomFieldOfView) * t
        } else {
            zoomTarget = GameConfig.cameraFieldOfView
        }
        currentFieldOfView += (zoomTarget - currentFieldOfView) * (1 - exp(-dt * 8))
        camera.camera.fieldOfViewInDegrees = currentFieldOfView

        if cameraMode == .firstPerson {
            let eye = target
                + SIMD3<Float>(0, GameConfig.firstPersonEyeHeight, 0)
                + forwardVector() * 0.22
            camera.position = eye
            camera.look(at: eye + look, from: eye, relativeTo: nil)
            aimRayOrigin = eye
            aimRayDirection = look
            aimRaySkip = 0.45
            return
        }

        let right = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))
        let pivotTarget = target
            + SIMD3<Float>(0, GameConfig.characterHeight * 1.0, 0)
            + right * GameConfig.cameraShoulderOffset

        // Follow smoothing applies to the PIVOT only: rotation then places
        // the camera exactly on its orbit every frame, so turning left or
        // right is perfectly even. The previous version smoothed the camera
        // POSITION while the look target stayed exact — the two fought each
        // other during rotation and produced the visible judder.
        var pivot = smoothedPivot ?? pivotTarget
        pivot += (pivotTarget - pivot) * (1 - exp(-dt * 16))
        smoothedPivot = pivot

        var desired = pivot - look * GameConfig.cameraDistance
        desired.y += GameConfig.cameraHeightOffset

        // Obstacle avoidance as a smoothed boom length: the arm shortens
        // quickly when something blocks the view and relaxes back slowly —
        // no more popping between discrete sampling steps while orbiting
        // close to walls and crates.
        let clearFraction = cameraClearFraction(from: pivot, to: desired)
        let armTarget = GameConfig.cameraDistance * clearFraction
        let armBlend = 1 - exp(-dt * (armTarget < cameraArm ? 30 : 5))
        cameraArm += (armTarget - cameraArm) * armBlend
        let armFraction = cameraArm / GameConfig.cameraDistance

        var camPos = pivot - look * cameraArm
        camPos.y += GameConfig.cameraHeightOffset * armFraction
        camPos.y = max(camPos.y, target.y + GameConfig.cameraMinHeight)
        camera.position = camPos
        camera.look(at: pivot + look * 24, from: camPos, relativeTo: nil)

        // Exact screen-center ray for aim convergence: from the camera
        // through its look target, skipping past the player's body.
        aimRayOrigin = camPos
        aimRayDirection = simd_normalize(pivot + look * 24 - camPos)
        aimRaySkip = cameraArm + 0.7
    }

    /// World-space point the center of the screen is looking at — the first
    /// thing the camera ray hits (enemy, obstacle, ground or arena wall).
    /// The march starts past the player so nothing behind the muzzle counts.
    func aimTargetPoint() -> SIMD3<Float> {
        let origin = aimRayOrigin
        let dir = aimRayDirection
        let step: Float = 0.22
        let maxDistance: Float = 70
        let halfW = GameConfig.arenaWidth / 2
        let halfD = GameConfig.arenaDepth / 2
        var distance = aimRaySkip
        while distance < maxDistance {
            let point = origin + dir * distance
            if abs(point.x) > halfW - 0.15 || abs(point.z) > halfD - 0.15 {
                return point
            }
            for bot in bots where !bot.isDown && bot.team == enemyTeam {
                let botPos = bot.container.position
                let dx = point.x - botPos.x
                let dz = point.z - botPos.z
                if dx * dx + dz * dz < 0.36,
                   point.y > botPos.y - 0.1,
                   point.y < botPos.y + GameConfig.characterHeight + 0.25 {
                    return point
                }
            }
            if point.y <= paintSurfaceHeight(atX: point.x, z: point.z) + 0.04 || obstacleHit(point) {
                return point
            }
            distance += step
        }
        return origin + dir * maxDistance
    }

    /// Blends a raw muzzle position toward eye height so the visible paint
    /// stream appears to leave from roughly where the fixed center reticle
    /// is aiming, instead of visibly below it (the animated hand sits much
    /// lower on the skeleton). Pure visual trick — no animation resync per
    /// weapon: the real flight direction still converges on the exact spot
    /// the reticle covers via `convergedAimDirection`.
    func visualFireOrigin(rawMuzzle: SIMD3<Float>, container: Entity) -> SIMD3<Float> {
        let eyeY = container.position.y + GameConfig.firstPersonEyeHeight
        var origin = rawMuzzle
        origin.y += (eyeY - rawMuzzle.y) * GameConfig.jetOriginEyeBlend
        return origin
    }

    /// Standard third-person aim convergence: the projectile leaves the
    /// muzzle but flies toward whatever the fixed center reticle covers.
    /// Without this, shots from the offset muzzle clip cover that the
    /// camera can clearly see over.
    func convergedAimDirection(from origin: SIMD3<Float>) -> SIMD3<Float> {
        let target = aimTargetPoint()
        let delta = target - origin
        // Target basically on top of the muzzle (wall in the face) — fall
        // back to the raw camera direction instead of a degenerate vector.
        guard simd_length(delta) > 1.0 else { return aimVector() }
        return simd_normalize(delta)
    }

    /// Simulates one jet droplet with the exact same ballistics as the real
    /// projectiles (speed, lift, gravity, obstacles, platforms) and returns
    /// the point where it lands.
    func predictedJetImpact(container: Entity) -> SIMD3<Float> {
        let rawPos = muzzleEntity?.position(relativeTo: nil)
            ?? (container.position + aimVector() * 0.5 + SIMD3<Float>(0, GameConfig.weaponSocketPosition.y, 0))
        var pos = visualFireOrigin(rawMuzzle: rawPos, container: container)
        let dir = convergedAimDirection(from: pos)
        // The charger reticle tracks the current charge's ballistics so the
        // aim point slides further out as the gauge fills.
        let speed: Float
        let gravity: Float
        if weapon == .charger {
            let charge = max(chargeLevel, GameConfig.chargerMinCharge)
            speed = GameConfig.chargerMinSpeed
                + (GameConfig.chargerMaxSpeed - GameConfig.chargerMinSpeed) * charge
            gravity = GameConfig.chargerShotGravity
        } else {
            speed = weapon.projectileSpeed
            gravity = weapon.projectileGravity
        }
        var velocity = dir * speed + SIMD3<Float>(0, 0.6, 0)
        let step: Float = 1.0 / 60.0
        let halfW = GameConfig.arenaWidth / 2
        let halfD = GameConfig.arenaDepth / 2
        for _ in 0..<180 {
            velocity.y -= gravity * step
            let next = pos + velocity * step
            if abs(next.x) > halfW - 0.15 || abs(next.z) > halfD - 0.15 {
                return pos
            }
            if next.y <= paintSurfaceHeight(atX: next.x, z: next.z) + 0.06 || obstacleHit(next) {
                return next
            }
            pos = next
        }
        return pos
    }

    /// Reticle lock state: the reticle itself is pinned to the screen
    /// center (firing converges onto it), so this only checks whether the
    /// predicted impact sits on a live enemy to shrink/recolor the HUD.
    func updateAimLock(container: Entity) {
        guard !isPlayerDown, !isDiving, !isMatchOver else {
            if isAimOnTarget { isAimOnTarget = false }
            return
        }
        // 30 Hz is plenty — halves the ballistic prediction cost so the
        // frame budget stays stable.
        crosshairFrameToggle.toggle()
        guard crosshairFrameToggle else { return }
        let world = predictedJetImpact(container: container)

        var locked = false
        for bot in bots where !bot.isDown && bot.team == enemyTeam {
            let botPos = bot.container.position
            let horizontal = simd_length(SIMD2<Float>(world.x - botPos.x, world.z - botPos.z))
            if horizontal < GameConfig.aimLockRadius,
               world.y > botPos.y - 0.4,
               world.y < botPos.y + GameConfig.characterHeight + 0.6 {
                locked = true
                break
            }
        }
        if isAimOnTarget != locked { isAimOnTarget = locked }
    }

    /// Fraction (0...1) of the camera boom that stays clear of obstacles.
    /// A fine second pass refines the hit so the value moves continuously
    /// while the camera orbits — no discrete jumps, no popping.
    func cameraClearFraction(from pivot: SIMD3<Float>, to desired: SIMD3<Float>) -> Float {
        let coarseSteps = 12
        var blockedAt: Float = -1
        for i in 1...coarseSteps {
            let t = Float(i) / Float(coarseSteps)
            if cameraBlocked(simd_mix(pivot, desired, SIMD3<Float>(repeating: t))) {
                blockedAt = t
                break
            }
        }
        guard blockedAt > 0 else { return 1 }
        let low = blockedAt - 1 / Float(coarseSteps)
        var clear = low
        let fineSteps = 6
        for i in 1...fineSteps {
            let t = low + (blockedAt - low) * Float(i) / Float(fineSteps)
            if cameraBlocked(simd_mix(pivot, desired, SIMD3<Float>(repeating: t))) { break }
            clear = t
        }
        return max(clear - 0.03, 0.14)
    }

    func cameraBlocked(_ point: SIMD3<Float>) -> Bool {
        for obstacle in obstacles {
            if point.y > obstacle.baseY - 0.15,
               point.y < obstacle.topY + 0.15,
               abs(point.x - obstacle.center.x) < obstacle.halfX + 0.22,
               abs(point.z - obstacle.center.z) < obstacle.halfZ + 0.22 {
                return true
            }
        }
        return false
    }

    /// Displays the stylized splat callout for two seconds.
    func showSplatEvent(headline: String, name: String, isPlayerVictim: Bool) {
        splatEvent = SplatEvent(headline: headline, name: name, isPlayerVictim: isPlayerVictim)
        splatEventTask?.cancel()
        splatEventTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2200))
            guard !Task.isCancelled else { return }
            self?.splatEvent = nil
        }
    }

    func showBanner(_ text: String) {
        banner = text
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    /// Player-initiated exit from a still-live match (Settings → "Quitter
    /// la partie", confirmed). Distinct from `endMatch()`: there is no
    /// winner to compute and no results sequence — the caller (`onQuit`)
    /// takes the player straight back to the Hub. In a local duel the peer
    /// is notified explicitly so their device runs its own normal `.leave`
    /// handling (see `handleNetMessage`) instead of waiting on a silent drop.
    func leaveMatch() {
        guard !isMatchOver else { return }
        beginMatchOver()
        if isLocalDuel {
            localMatch.send(.leave)
        }
        onQuit?()
    }

    func endMatch() {
        guard !isMatchOver else { return }
        beginMatchOver()

        if isLocalDuel && !localMatch.isHost {
            // Guest: the host owns the authoritative score. Wait for it so
            // both devices display the exact same numbers, with a local
            // fallback if the message never arrives (e.g. host dropped).
            awaitingHostResult = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.awaitingHostResult, !self.hasPublishedResult else { return }
                // Best available fallback: the last authoritative coverage
                // broadcast (≤ 0.5 s old), else the local grid counters.
                self.finalizeMatch(
                    orange: self.hostCoverage?.orange ?? self.grid?.orangeCount ?? 0,
                    purple: self.hostCoverage?.purple ?? self.grid?.purpleCount ?? 0,
                    total: self.hostCoverage?.total ?? self.grid?.totalCount ?? 1
                )
            }
            return
        }

        let orange = grid?.orangeCount ?? 0
        let purple = grid?.purpleCount ?? 0
        let total = grid?.totalCount ?? 1
        // Host of a duel: broadcast the authoritative counts to the guest —
        // paint tiles AND the mode-specific team scores (kills/zone points)
        // so both devices display the exact same final result.
        if isLocalDuel && localMatch.isHost {
            let modeScores = currentModeScores
            localMatch.send(.result(
                orange: orange, purple: purple, total: total,
                modeOrange: modeScores?.orange, modePurple: modeScores?.purple
            ))
        }
        finalizeMatch(orange: orange, purple: purple, total: total)
    }

    /// Freezes gameplay input/state the instant the match ends — shared by
    /// the timer, the host/guest paths, and the disconnect path.
    func beginMatchOver() {
        isMatchOver = true
        isFiring = false
        joystick = .zero
        diveStick = .zero
        stats = liveStats
        cancelGrenadeAim()
        setDiving(false)
    }

    /// Live mode-specific team totals — kills for Duel Mortel, zone points
    /// for Contrôle de Zones, nil for Guerre de Peinture. Broadcast by the
    /// duel host so both devices show identical objective scores.
    var currentModeScores: (orange: Int, purple: Int)? {
        switch matchMode {
        case .turfWar:
            return nil
        case .deathmatch:
            let oKills = liveStats.filter { $0.team == .orange }.reduce(0) { $0 + $1.kills }
            let pKills = liveStats.filter { $0.team == .purple }.reduce(0) { $0 + $1.kills }
            return (oKills, pKills)
        case .zoneControl:
            return (zoneScoreOrange, zoneScorePurple)
        }
    }

    /// Builds the one-and-only end-of-match result from final tile counts,
    /// plays the win/idle stance, and hands the summary to the results
    /// screen. `orange`/`purple` are the SHARED world-frame team counts
    /// (identical on both devices) — the local player's own share is picked
    /// via `localTeam`, so the guest never needs to swap anything.
    /// `modeScores` are the HOST's authoritative mode totals when received
    /// over the wire — they override the local tallies so both devices agree
    /// on the winner and the displayed score.
    func finalizeMatch(
        orange: Int,
        purple: Int,
        total rawTotal: Int,
        modeScores: (orange: Int, purple: Int)? = nil
    ) {
        guard !hasPublishedResult else { return }
        hasPublishedResult = true
        awaitingHostResult = false

        let total = max(rawTotal, 1)
        let mine = localTeam == .orange ? orange : purple
        let theirs = localTeam == .orange ? purple : orange
        let orangeP = Int((Double(mine) / Double(total) * 100).rounded())
        let purpleP = Int((Double(theirs) / Double(total) * 100).rounded())

        let outcome: MatchOutcome
        let orangeScore: Int
        let purpleScore: Int
        switch matchMode {
        case .turfWar:
            outcome = mine > theirs ? .win : (theirs > mine ? .lose : .draw)
            orangeScore = 0
            purpleScore = 0
        case .deathmatch:
            let oKills = modeScores?.orange
                ?? liveStats.filter { $0.team == .orange }.reduce(0) { $0 + $1.kills }
            let pKills = modeScores?.purple
                ?? liveStats.filter { $0.team == .purple }.reduce(0) { $0 + $1.kills }
            let mineKills = localTeam == .orange ? oKills : pKills
            let theirsKills = localTeam == .orange ? pKills : oKills
            outcome = mineKills > theirsKills ? .win : (theirsKills > mineKills ? .lose : .draw)
            orangeScore = oKills
            purpleScore = pKills
        case .zoneControl:
            let oZone = modeScores?.orange ?? zoneScoreOrange
            let pZone = modeScores?.purple ?? zoneScorePurple
            let mineScore = localTeam == .orange ? oZone : pZone
            let theirsScore = localTeam == .orange ? pZone : oZone
            outcome = mineScore > theirsScore ? .win : (theirsScore > mineScore ? .lose : .draw)
            orangeScore = oZone
            purpleScore = pZone
        }

        AudioService.shared.stopMusic()
        if outcome == .win {
            AudioService.shared.playVictory()
            heroSetLoop(ModelCatalog.heroVictory ?? ModelCatalog.heroIdle)
        } else {
            heroSetLoop(ModelCatalog.heroIdle)
        }
        for bot in bots where !bot.isDown {
            bot.setLoop(bot.idleAnim)
        }

        let result = MatchResult(
            outcome: outcome,
            localTeam: localTeam,
            mode: matchMode,
            orangePercent: orangeP,
            purplePercent: purpleP,
            paintedTiles: mine,
            standings: liveStats.sorted { ($0.kills, $0.paintTiles) > ($1.kills, $1.paintTiles) },
            orangeScore: orangeScore,
            purpleScore: purpleScore
        )
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            self?.onMatchEnd?(result)
        }
    }
}
