import Foundation
import RealityKit
import UIKit
import simd

/// Ink projectiles: jet droplets, lobbed drops, grenades, splash damage,
/// bursts and land SFX. Verbatim from `GameController` — no behaviour change.
extension GameController {
    /// One glowing droplet of the continuous paint jet, stretched along its
    /// full 3D travel direction so the stream reads as one connected jet.
    /// Ballistics, damage and splat size come from the firing weapon.
    func spawnJetDrop(
        at origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        team: Team,
        weapon: WeaponType,
        dropScale: Float = 1,
        ownerIndex: Int = 0
    ) {
        spawnPaintDrop(
            at: origin,
            direction: direction,
            team: team,
            speed: weapon.projectileSpeed,
            gravity: weapon.projectileGravity,
            damage: weapon.damagePerHit,
            paintRadius: weapon.paintRadius,
            dropScale: dropScale,
            ownerIndex: ownerIndex
        )
    }

    /// Fully-parameterized paint droplet — used by the weapon jets and the
    /// charger's variable-strength sniper shot.
    func spawnPaintDrop(
        at origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        team: Team,
        speed: Float,
        gravity: Float,
        damage: Int,
        paintRadius: Float,
        dropScale: Float,
        ownerIndex: Int = 0,
        splashRange: Float = 0,
        hitRadius: Float = GameConfig.characterHitRadius
    ) {
        guard let worldRoot, let material = projectileMaterials[team] else { return }
        // Hard cap: recycling the oldest drop keeps the projectile update
        // bounded so the framerate never dips under sustained fire. The
        // Performance graphics preset halves the cap.
        if projectiles.count >= projectileCap {
            let oldest = projectiles.removeFirst()
            releaseDrop(oldest.entity)
        }
        // Acquire from the pool if available (already parented to worldRoot),
        // otherwise build once and parent permanently. Recycled entities keep
        // their parenting — never re-`addChild` them.
        let entity: ModelEntity
        if let recycled = dropPool.popLast() {
            entity = recycled
            entity.model?.materials = [material] // team may differ from last use
            entity.isEnabled = true
        } else {
            entity = ModelEntity(mesh: dropMesh, materials: [material])
            worldRoot.addChild(entity)
        }
        entity.position = origin
        entity.scale = SIMD3<Float>(0.85, 0.85, 3.6) * Float.random(in: 0.9...1.25) * dropScale
        entity.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(direction))
        let velocity = direction * speed + SIMD3<Float>(0, 0.6, 0)
        projectiles.append(Projectile(
            entity: entity,
            velocity: velocity,
            team: team,
            kind: .drop,
            gravity: gravity,
            damage: damage,
            paintRadius: paintRadius,
            ownerIndex: ownerIndex,
            splashRange: splashRange,
            hitRadius: hitRadius
        ))
    }

    /// Returns a spent `.drop` entity to the pool: disabled and kept parented
    /// to `worldRoot` so it can be re-acquired without a scene-graph mutation.
    /// Only ever called with `.drop` projectiles, which are always
    /// `ModelEntity`; a non-model entity is defensively just removed.
    private func releaseDrop(_ entity: Entity) {
        entity.isEnabled = false
        if let model = entity as? ModelEntity {
            dropPool.append(model)
        } else {
            entity.removeFromParent()
        }
    }

    func updateProjectiles(dt: Float, grid: PaintGrid) {
        guard !projectiles.isEmpty else { return }
        let halfW = GameConfig.arenaWidth / 2
        let halfD = GameConfig.arenaDepth / 2
        // In-place swap-removal instead of building a fresh `survivors` array
        // every frame — zero allocation on the hot path even under sustained
        // fire. Walk backward so removing index i never disturbs indices not
        // yet visited.
        var index = projectiles.count - 1
        while index >= 0 {
            var projectile = projectiles[index]
            let dead = stepProjectile(&projectile, dt: dt, halfW: halfW, halfD: halfD, grid: grid)
            if dead {
                // Pooled drops go back to the pool (kept parented, disabled);
                // grenades are rare clones and keep the plain remove path.
                if projectile.kind == .drop {
                    releaseDrop(projectile.entity)
                } else {
                    projectile.entity.removeFromParent()
                }
                projectiles.swapAt(index, projectiles.count - 1)
                projectiles.removeLast()
            } else {
                projectiles[index] = projectile
            }
            index -= 1
        }
    }

    /// Advances one projectile by `dt` and resolves its collisions/landing
    /// for this frame. Returns true when it should be removed.
    private func stepProjectile(_ projectile: inout Projectile, dt: Float, halfW: Float, halfD: Float, grid: PaintGrid) -> Bool {
            let prevPos = projectile.entity.position
            projectile.velocity.y -= projectile.gravity * dt
            projectile.entity.position += projectile.velocity * dt
            let pos = projectile.entity.position
            var dead = false
            let surface = paintSurfaceHeight(atX: pos.x, z: pos.z)
            // Covered interior (real tunnels / underpasses): the projectile
            // flies UNDER a walkable roof, so the local top surface sits far
            // above it. Its true landing plane is the base floor, and interior
            // floors are never paintable (the grid cell belongs to the roof).
            let isCovered = surface > pos.y + 1.2

            if projectile.kind == .grenade {
                // Direct in-flight hit: a live grenade that clips a player or
                // bot one-shots it instantly, on top of its usual area
                // detonation — a satisfying bonus reward for a precise throw.
                var directHit = false
                if projectile.team != localTeam, !isPlayerDown, !isMatchOver,
                   let playerPos = playerContainer?.position,
                   characterHit(pos, target: playerPos, radius: projectile.hitRadius) {
                    hitPlayer(at: playerPos, damage: GameConfig.playerMaxHP, by: projectile.ownerIndex)
                    directHit = true
                } else if projectile.team == localTeam {
                    for bot in bots where !bot.isDown && bot.team != projectile.team {
                        let botPos = bot.container.position
                        if characterHit(pos, target: botPos, radius: projectile.hitRadius) {
                            hitBot(bot, at: botPos, damage: GameConfig.grenadePlayerDamage, by: projectile.team, ownerIndex: projectile.ownerIndex)
                            directHit = true
                            break
                        }
                    }
                }
                // Fixed fuse: the grenade bounces off walls, ground and cover
                // and detonates after a constant delay — NEVER on impact, so
                // short and long throws behave exactly the same — UNLESS a
                // direct hit just landed, which detonates it immediately.
                if directHit || elapsed >= projectile.detonateAt {
                    explodeGrenade(at: clampToArena(pos), team: projectile.team, grid: grid, ownerIndex: projectile.ownerIndex)
                    dead = true
                } else {
                    var bouncePos = pos
                    var velocity = projectile.velocity
                    if abs(bouncePos.x) > halfW - 0.3 {
                        velocity.x = -velocity.x * 0.55
                        bouncePos.x = min(max(bouncePos.x, -(halfW - 0.3)), halfW - 0.3)
                    }
                    if abs(bouncePos.z) > halfD - 0.3 {
                        velocity.z = -velocity.z * 0.55
                        bouncePos.z = min(max(bouncePos.z, -(halfD - 0.3)), halfD - 0.3)
                    }
                    let bounceFloor: Float = isCovered ? 0 : surface
                    if bouncePos.y <= bounceFloor + 0.12, velocity.y < 0 {
                        bouncePos.y = bounceFloor + 0.12
                        velocity.y = -velocity.y * 0.45
                        velocity.x *= 0.7
                        velocity.z *= 0.7
                        if velocity.y < 0.8 { velocity.y = 0 }
                        playLandSfx(at: bouncePos)
                    } else if obstacleHit(bouncePos, projectileTeam: projectile.team) {
                        bouncePos = pos - projectile.velocity * dt
                        velocity.x = -velocity.x * 0.45
                        velocity.z = -velocity.z * 0.45
                    }
                    // Blinking fuse pulse — faster right before the blast.
                    let timeLeft = Float(projectile.detonateAt - elapsed)
                    let rate: Float = timeLeft < 0.6 ? 22 : 10
                    projectile.entity.scale = SIMD3<Float>(repeating: 1 + 0.14 * abs(sinf(Float(elapsed) * rate)))
                    projectile.velocity = velocity
                    projectile.entity.position = bouncePos
                }
            } else if abs(pos.x) > halfW - 0.15 || abs(pos.z) > halfD - 0.15 {
                dead = true
            } else if projectile.team != localTeam, !isPlayerDown, !isMatchOver,
                      let playerPos = playerContainer?.position,
                      characterHit(pos, target: playerPos, radius: projectile.hitRadius) {
                // Direct in-flight hit is checked BEFORE the ground/landing
                // tests below, so a projectile that clips a player counts
                // even while it is still descending toward the floor.
                hitPlayer(at: playerPos, damage: projectile.damage, by: projectile.ownerIndex)
                dead = true
            } else {
                for bot in bots where !bot.isDown && bot.team != projectile.team {
                    let botPos = bot.container.position
                    if characterHit(pos, target: botPos, radius: projectile.hitRadius) {
                        hitBot(bot, at: botPos, damage: projectile.damage, by: projectile.team, ownerIndex: projectile.ownerIndex)
                        dead = true
                        break
                    }
                }

                // Swept test: fast drops cover 0.25–0.5 m per frame (more on a
                // dropped frame) while climb walls are only 0.6 m thick, so
                // testing only the END position lets drops tunnel straight
                // through thin walls — the persistent "paint passes through the
                // wall" bug. Sampling the whole segment travelled this frame
                // catches the wall at the true contact point.
                if !dead, let hit = sweepObstacleHit(from: prevPos, to: pos, projectileTeam: projectile.team) {
                    // A wall/crate was struck. Vertical faces are NOT paintable
                    // anymore: paint only lands when the blob grazes the flat
                    // WALKABLE TOP of a crate/platform, which is treated exactly
                    // like the floor. A hit on a vertical face below the summit
                    // leaves no trace at all. The graze band is tight (≈ at the
                    // top) so a face hit just below is NOT stolen by this branch.
                    let contact = hit.point
                    let contactSurface = paintSurfaceHeight(atX: contact.x, z: contact.z)
                    let isTopGraze = contactSurface > 0 && contact.y >= contactSurface - 0.04
                    if isTopGraze {
                        let gained = grid.paint(atX: contact.x, z: contact.z, radius: projectile.paintRadius, team: projectile.team)
                        credit(paint: gained, to: projectile.ownerIndex)
                        netPaintSplat(x: contact.x, z: contact.z, radius: projectile.paintRadius, team: projectile.team)
                    }
                    // Splash damage is combat and stays unchanged; the paint
                    // burst is a visual trace, so it only appears on a paintable
                    // top graze (never on a bare vertical face).
                    if projectile.splashRange > 0 {
                        applySplashDamage(
                            at: contact, range: projectile.splashRange, damage: projectile.damage,
                            team: projectile.team, ownerIndex: projectile.ownerIndex
                        )
                        if isTopGraze { spawnBurst(at: contact, team: projectile.team) }
                    }
                    if isTopGraze { playLandSfx(at: contact) }
                    dead = true
                } else if !dead, pos.y <= (isCovered ? 0.06 : surface + 0.06) {
                    // Ramps are not paintable, and neither are covered interior
                    // floors (tunnels, underpasses): a blob landing there leaves
                    // no trace (no splat, no burst). Splash damage still applies
                    // so combat on ramps and inside tunnels is unaffected.
                    let onRamp = isOnRamp(atX: pos.x, z: pos.z)
                    let paintable = !onRamp && !isCovered
                    if paintable {
                        let gained = grid.paint(atX: pos.x, z: pos.z, radius: projectile.paintRadius, team: projectile.team)
                        credit(paint: gained, to: projectile.ownerIndex)
                        netPaintSplat(x: pos.x, z: pos.z, radius: projectile.paintRadius, team: projectile.team)
                    }
                    if projectile.splashRange > 0 {
                        applySplashDamage(
                            at: pos, range: projectile.splashRange, damage: projectile.damage,
                            team: projectile.team, ownerIndex: projectile.ownerIndex
                        )
                        if paintable { spawnBurst(at: pos, team: projectile.team) }
                    }
                    playLandSfx(at: pos)
                    dead = true
                }
            }

            return dead
    }

    /// Area damage of a landing bucket blob — anyone of the opposing team
    /// caught in the splash radius takes the blob's damage.
    func applySplashDamage(at pos: SIMD3<Float>, range: Float, damage: Int, team: Team, ownerIndex: Int) {
        for bot in bots where !bot.isDown && bot.team != team {
            let botPos = bot.container.position
            if simd_length(SIMD2<Float>(pos.x - botPos.x, pos.z - botPos.z)) < range {
                hitBot(bot, at: botPos, damage: damage, by: team, ownerIndex: ownerIndex)
            }
        }
        if team != localTeam, !isPlayerDown, !isMatchOver, let playerPos = playerContainer?.position,
           simd_length(SIMD2<Float>(pos.x - playerPos.x, pos.z - playerPos.z)) < range {
            // Splash resistance gear perk softens area damage, never below 1.
            hitPlayer(at: playerPos, damage: max(1, damage - perks.splashDamageReduction), by: ownerIndex)
        }
    }

    func characterHit(_ pos: SIMD3<Float>, target: SIMD3<Float>, radius: Float = GameConfig.characterHitRadius) -> Bool {
        pos.y > target.y - 0.15
            && pos.y < target.y + GameConfig.characterHeight + 0.3
            && simd_length(SIMD2<Float>(pos.x - target.x, pos.z - target.z)) < radius
    }

    func explodeGrenade(at pos: SIMD3<Float>, team: Team, grid: PaintGrid, ownerIndex: Int) {
        // A blast under a walkable roof (tunnel, underpass) never paints: the
        // grid cells there belong to the surface ABOVE, so painting would
        // splat the plateau top. Damage and VFX stay fully active.
        let isCovered = paintSurfaceHeight(atX: pos.x, z: pos.z) > pos.y + 1.2
        if !isCovered {
            let gained = grid.paint(atX: pos.x, z: pos.z, radius: GameConfig.grenadePaintRadius, team: team)
            credit(paint: gained, to: ownerIndex)
            netPaintSplat(x: pos.x, z: pos.z, radius: GameConfig.grenadePaintRadius, team: team)
        }
        spawnBurst(at: pos, team: team)
        // Spatial audio: the blast is loud up close and fades with distance.
        AudioService.shared.playEnemySplat(volume: spatialVolume(1.0, at: pos))
        if let playerPos = playerContainer?.position, simd_distance(playerPos, pos) < 12 {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }

        for bot in bots where !bot.isDown && bot.team != team {
            let botPos = bot.container.position
            if simd_length(SIMD2<Float>(pos.x - botPos.x, pos.z - botPos.z)) < GameConfig.grenadeSplatRange {
                hitBot(bot, at: botPos, damage: GameConfig.grenadePlayerDamage, by: team, ownerIndex: ownerIndex)
            }
        }
        if team != localTeam, !isPlayerDown, !isMatchOver, let playerPos = playerContainer?.position,
           simd_length(SIMD2<Float>(pos.x - playerPos.x, pos.z - playerPos.z)) < GameConfig.grenadeSplatRange {
            hitPlayer(
                at: playerPos,
                damage: max(1, GameConfig.grenadePlayerDamage - perks.splashDamageReduction),
                by: ownerIndex
            )
        }
    }

    /// Quick expanding splash flash for grenade impacts.
    func spawnBurst(at pos: SIMD3<Float>, team: Team) {
        guard let worldRoot, let material = projectileMaterials[team] else { return }
        // Same global transient-VFX budget as the hit splashes.
        guard liveTransientVFX < qualitySettings.transientVFXBudget else { return }
        liveTransientVFX += 1
        // Under a walkable roof (tunnel) the top surface is far above the
        // blast — anchor the flash to the interior floor instead.
        var surface = paintSurfaceHeight(atX: pos.x, z: pos.z)
        if surface > pos.y + 1.2 { surface = 0 }
        let burst = ModelEntity(mesh: burstMesh, materials: [material])
        burst.position = [pos.x, surface + 0.25, pos.z]
        burst.scale = [1, 0.5, 1]
        worldRoot.addChild(burst)

        var target = burst.transform
        target.scale = [5.5, 0.3, 5.5]
        burst.move(to: target, relativeTo: burst.parent, duration: 0.28, timingFunction: .easeOut)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            burst.removeFromParent()
            self?.liveTransientVFX -= 1
        }
    }

    /// Distance-attenuated splat when paint lands somewhere in the arena.
    func playLandSfx(at position: SIMD3<Float>) {
        guard elapsed - lastSplatSfx > 0.2 else { return }
        lastSplatSfx = elapsed
        AudioService.shared.playSplat(volume: spatialVolume(0.3, at: position))
    }

    /// Distance-based volume: full next to the player, silent past the
    /// falloff distance — dynamic spatial mixing for every arena sound.
    func spatialVolume(_ base: Float, at position: SIMD3<Float>) -> Float {
        guard let playerPos = playerContainer?.position else { return base }
        let falloff = max(0, 1 - simd_distance(playerPos, position) / GameConfig.audioFalloffDistance)
        return base * falloff * falloff
    }

}
