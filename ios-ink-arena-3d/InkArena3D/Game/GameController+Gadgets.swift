import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

/// Instant gadgets (paint bomb, ink wall) and the shield-wall mesh
/// cache accessors. Verbatim from `GameController` — no behaviour change.
extension GameController {
    /// Instant (non-aimed) gadget activation — spends ink, starts the
    /// shared gadget cooldown, then performs the equipped effect.
    func performInstantGadget() {
        guard playerContainer != nil else { return }
        inkExact -= gadget.inkCost
        grenadeCooldown = gadget.cooldown
        grenadeCooldownExact = gadget.cooldown
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch gadget {
        case .paintBomb:
            break
        case .inkWall:
            spawnInkWall()
        }
    }

    /// Raises a temporary axis-aligned ink wall in front of the player —
    /// blocks shots and paths, then dissolves after a few seconds. In a local
    /// duel the pose is streamed to the peer so it rebuilds its own instance.
    func spawnInkWall() {
        guard let container = playerContainer else { return }
        let origin = container.position
        let forward = forwardVector()
        // Obstacles are axis-aligned boxes: snap the wall to the dominant axis.
        let alongX = abs(forward.x) >= abs(forward.z)
        let dir: SIMD3<Float> = alongX
            ? [forward.x >= 0 ? 1 : -1, 0, 0]
            : [0, 0, forward.z >= 0 ? 1 : -1]
        let baseY = walkableHeight(atX: origin.x, z: origin.z, currentY: origin.y)
        // Placed slightly in FRONT of the player, never on their own position.
        var center = clampToArena(origin + dir * GameConfig.inkWallDistance)
        center.y = baseY + GameConfig.inkWallHeight / 2

        let halfX = alongX ? GameConfig.inkWallThickness / 2 : GameConfig.inkWallWidth / 2
        let halfZ = alongX ? GameConfig.inkWallWidth / 2 : GameConfig.inkWallThickness / 2

        // The wall belongs to the local player's team — full pane for its
        // owner side, see + shoot through.
        buildInkWall(center: center, halfX: halfX, halfZ: halfZ, baseY: baseY, team: localTeam)
        AudioService.shared.playSplat(volume: 0.6)

        if isLocalDuel {
            localMatch.send(.wall(NetWall(
                cx: center.x, cy: center.y, cz: center.z,
                halfX: halfX, halfZ: halfZ, baseY: baseY
            )))
        }
    }

    /// Rebuilds a shield wall the peer just raised, at the exact same world
    /// position (shared frame). It is always an ENEMY wall here → rendered as
    /// a light filament that blocks the local player's shots and movement.
    func spawnRemoteInkWall(_ w: NetWall) {
        let center = SIMD3<Float>(w.cx, w.cy, w.cz)
        buildInkWall(center: center, halfX: w.halfX, halfZ: w.halfZ, baseY: w.baseY, team: enemyTeam)
        AudioService.shared.playSplat(volume: spatialVolume(0.45, at: center))
    }

    /// Shared shield-wall constructor. `team` is the wall's OWNING team in this
    /// device's frame: an allied wall shows a bright translucent pane you can
    /// see and shoot through; an enemy wall shows only a glowing edge filament
    /// and blocks your shots/movement. Registered as an obstacle whose owner
    /// team passes freely through it, then dissolved after `inkWallDuration`.
    func buildInkWall(center: SIMD3<Float>, halfX: Float, halfZ: Float, baseY: Float, team: Team) {
        guard let worldRoot else { return }
        let isAlly = team == localTeam
        let width = halfX * 2
        let depth = halfZ * 2
        let height = GameConfig.inkWallHeight
        // The shield is thin along X when its X footprint is the smaller one.
        let alongX = halfX < halfZ

        let holder = Entity()
        holder.name = "ink_wall"
        holder.position = center

        if isAlly {
            // Owner-side look: a clearly visible team-tinted pane you can see
            // (and shoot) straight through — an advanced cover, not a blindfold.
            // Mesh + material are cached once and reused on every cast.
            let pane = ModelEntity(
                mesh: cachedInkWallPaneMesh(alongX: alongX, width: width, height: height, depth: depth),
                materials: [cachedInkWallPaneMaterial(color: team.uiColor)]
            )
            holder.addChild(pane)
        } else {
            // Enemy view: only a glowing wireframe silhouette (filament) — no
            // clear pane to peek through; the collider below still blocks them.
            addFilamentFrame(to: holder, alongX: alongX, width: width, height: height, depth: depth, color: team.uiColor)
        }
        worldRoot.addChild(holder)

        obstacles.append(Obstacle(
            center: center,
            halfX: halfX,
            halfZ: halfZ,
            baseY: baseY,
            topY: baseY + height,
            isWalkable: false,
            // Solid to everyone except the owning team, which walks and shoots
            // straight through its own shield.
            passThroughTeam: team
        ))
        // Runtime obstacle mutation — refresh the collision broadphase.
        rebuildSpatialIndex()

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(GameConfig.inkWallDuration))
            guard let self else { return }
            holder.removeFromParent()
            if let index = self.obstacles.lastIndex(where: {
                $0.center == center && $0.halfX == halfX && $0.halfZ == halfZ
            }) {
                self.obstacles.remove(at: index)
                // Removal shifts every later index — rebuild the grid wholesale.
                self.rebuildSpatialIndex()
            }
        }
    }

    /// Builds a glowing edge-frame silhouette (the enemy "filament" look of a
    /// shield wall) from thin emissive bars along the box's 12 edges. Bar
    /// meshes + material are cached per orientation and reused on every cast.
    func addFilamentFrame(to holder: Entity, alongX: Bool, width: Float, height: Float, depth: Float, color: UIColor) {
        let t: Float = 0.055
        let mat = cachedInkWallFilamentMaterial(color: color)
        let hw = width / 2
        let hh = height / 2
        let hd = depth / 2
        let verticalBar = cachedInkWallVerticalBar(t: t, height: height)
        let barX = cachedInkWallBarAlongX(alongX: alongX, width: width, t: t)
        let barZ = cachedInkWallBarAlongZ(alongX: alongX, depth: depth, t: t)
        // 4 vertical corner bars.
        for x in [hw, -hw] {
            for z in [hd, -hd] {
                let bar = ModelEntity(mesh: verticalBar, materials: [mat])
                bar.position = [x, 0, z]
                holder.addChild(bar)
            }
        }
        // Top and bottom rectangles (bars along X and along Z).
        for y in [hh, -hh] {
            for z in [hd, -hd] {
                let bar = ModelEntity(mesh: barX, materials: [mat])
                bar.position = [0, y, z]
                holder.addChild(bar)
            }
            for x in [hw, -hw] {
                let bar = ModelEntity(mesh: barZ, materials: [mat])
                bar.position = [x, y, 0]
                holder.addChild(bar)
            }
        }
    }


    func cachedInkWallPaneMesh(alongX: Bool, width: Float, height: Float, depth: Float) -> MeshResource {
        if let mesh = inkWallPaneMesh[alongX] { return mesh }
        let mesh = MeshResource.generateBox(width: width, height: height, depth: depth, cornerRadius: 0.08)
        inkWallPaneMesh[alongX] = mesh
        return mesh
    }

    func cachedInkWallPaneMaterial(color: UIColor) -> PhysicallyBasedMaterial {
        if let material = inkWallPaneMaterial { return material }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.withAlphaComponent(0.62))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.62))
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = 0.9
        material.roughness = .init(floatLiteral: 0.35)
        inkWallPaneMaterial = material
        return material
    }

    func cachedInkWallFilamentMaterial(color: UIColor) -> PhysicallyBasedMaterial {
        if let material = inkWallFilamentMaterial { return material }
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: color.withAlphaComponent(0.9))
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        mat.emissiveColor = .init(color: color)
        mat.emissiveIntensity = 1.5
        inkWallFilamentMaterial = mat
        return mat
    }

    func cachedInkWallVerticalBar(t: Float, height: Float) -> MeshResource {
        if let mesh = inkWallVerticalBar { return mesh }
        let mesh = MeshResource.generateBox(width: t, height: height, depth: t)
        inkWallVerticalBar = mesh
        return mesh
    }

    func cachedInkWallBarAlongX(alongX: Bool, width: Float, t: Float) -> MeshResource {
        if let mesh = inkWallBarAlongX[alongX] { return mesh }
        let mesh = MeshResource.generateBox(width: width, height: t, depth: t)
        inkWallBarAlongX[alongX] = mesh
        return mesh
    }

    func cachedInkWallBarAlongZ(alongX: Bool, depth: Float, t: Float) -> MeshResource {
        if let mesh = inkWallBarAlongZ[alongX] { return mesh }
        let mesh = MeshResource.generateBox(width: t, height: t, depth: depth)
        inkWallBarAlongZ[alongX] = mesh
        return mesh
    }

    /// Lobs the paint grenade along the aimed arc with the over-shoulder
    /// throw animation — the grenade stays glued to the hand during the
    /// wind-up, then leaves the hand at the top of the swing.
    func throwGrenadeAimed() {
        guard let container = playerContainer else { return }
        inkExact -= GameConfig.grenadeInkCost
        grenadeCooldown = GameConfig.grenadeCooldownDuration

        let dir = aimVector()
        grenadeCooldownExact = GameConfig.grenadeCooldownDuration
        container.orientation = yawQuat(for: forwardVector())
        heroAnimator?.playOnce(ModelCatalog.heroThrow, restoreAfter: .milliseconds(750))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Release the grenade at the top of the throw animation, from the
        // exact spot where the animated hand is at that moment.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard let self, !self.isMatchOver else { return }
            self.removeHandGrenade()
            self.launchGrenade(direction: dir)
        }
    }

    /// World-space point the grenade leaves from — the animated hand when
    /// a skeleton is trackable, otherwise a chest-height fallback.
    func grenadeLaunchOrigin(direction: SIMD3<Float>) -> SIMD3<Float> {
        guard let container = playerContainer else { return .zero }
        if let hand = heroHandTracker.handPosition(in: container) {
            return container.convert(position: hand, to: nil) + direction * 0.3
        }
        return container.position
            + direction * 0.8
            + SIMD3<Float>(0, GameConfig.characterHeight * 0.8, 0)
    }

    func launchGrenade(direction: SIMD3<Float>) {
        guard let worldRoot else { return }
        let entity = makeGrenadeEntity()
        entity.position = grenadeLaunchOrigin(direction: direction)
        worldRoot.addChild(entity)
        let velocity = direction * GameConfig.grenadeSpeed + SIMD3<Float>(0, 5.2, 0)
        projectiles.append(Projectile(
            entity: entity,
            velocity: velocity,
            team: localTeam,
            kind: .grenade,
            gravity: 9.5,
            damage: GameConfig.grenadePlayerDamage,
            paintRadius: GameConfig.grenadePaintRadius,
            ownerIndex: 0,
            detonateAt: elapsed + GameConfig.grenadeFuse
        ))
        sendFire(kind: .grenade, origin: entity.position, direction: direction)
        AudioService.shared.playSplat(volume: 0.5)
    }

    /// Attaches the grenade visual to the animated hand while aiming.
    func attachHandGrenade() {
        removeHandGrenade()
        guard let container = playerContainer else { return }
        let grenade = makeGrenadeEntity()
        grenade.name = "hand_grenade"
        // Keep the runtime name unique so animation players and the hand
        // tracker never latch onto the carried prop.
        grenade.findEntity(named: "generated_model_runtime")?.name = "hand_grenade_runtime"
        container.addChild(grenade)
        handGrenade = grenade
        applyBodyVisibility()
        updateHandGrenadePosition()
    }

    func removeHandGrenade() {
        guard handGrenade != nil else { return }
        handGrenade?.removeFromParent()
        handGrenade = nil
        applyBodyVisibility()
    }

    /// Glues the carried grenade to the hand joint so the hand visibly
    /// guides it through the aim pose and the throw swing.
    func updateHandGrenadePosition() {
        guard let grenade = handGrenade, let container = playerContainer else { return }
        grenade.position = heroHandTracker.handPosition(in: container)
            .map { $0 + SIMD3<Float>(0.02, 0.08, 0.1) }
            ?? GameConfig.weaponSocketPosition
    }

    /// Simulates the grenade flight with the exact launch ballistics
    /// (speed, lift, gravity, walls, obstacles, platforms) and returns the
    /// full path — used for the aim preview and the plant/throw decision.
    func simulatedGrenadePath() -> [SIMD3<Float>] {
        let dir = aimVector()
        var pos = grenadeLaunchOrigin(direction: dir)
        var velocity = dir * GameConfig.grenadeSpeed + SIMD3<Float>(0, 5.2, 0)
        var points: [SIMD3<Float>] = [pos]
        let step: Float = 1.0 / 60.0
        let halfW = GameConfig.arenaWidth / 2
        let halfD = GameConfig.arenaDepth / 2
        for _ in 0..<240 {
            velocity.y -= 9.5 * step
            let next = pos + velocity * step
            if abs(next.x) > halfW - 0.15 || abs(next.z) > halfD - 0.15 {
                points.append(clampToArena(next))
                return points
            }
            if next.y <= paintSurfaceHeight(atX: next.x, z: next.z) + 0.06 || obstacleHit(next) {
                points.append(next)
                return points
            }
            pos = next
            points.append(pos)
        }
        return points
    }

    /// Dotted preview arc + translucent landing disc, pooled once at setup.
    func buildGrenadeAimVisuals(_ root: Entity) {
        let aimRoot = Entity()
        aimRoot.name = "grenade_aim"
        aimRoot.isEnabled = false
        root.addChild(aimRoot)
        grenadeAimRoot = aimRoot

        let dotMaterial = UnlitMaterial(color: localTeam.uiColor)
        for _ in 0..<GameConfig.grenadeArcDotCount {
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.07), materials: [dotMaterial])
            aimRoot.addChild(dot)
            grenadeArcDots.append(dot)
        }

        var discMaterial = UnlitMaterial(color: localTeam.uiColor)
        discMaterial.blending = .transparent(opacity: 0.32)
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: GameConfig.grenadePaintRadius),
            materials: [discMaterial]
        )
        aimRoot.addChild(disc)
        grenadeLandingDisc = disc
    }

    /// Per-frame grenade aiming: keeps the grenade in the hand and lays the
    /// dotted arc + pulsing landing disc along the live predicted flight.
    func updateGrenadeAim() {
        if handGrenade != nil {
            updateHandGrenadePosition()
        }
        guard isAimingGrenade, let container = playerContainer else { return }
        if isPlayerDown || isMatchOver {
            cancelGrenadeAim()
            return
        }
        let path = simulatedGrenadePath()
        guard let landing = path.last else { return }

        let count = grenadeArcDots.count
        for (index, dot) in grenadeArcDots.enumerated() {
            let t = Float(index + 1) / Float(count + 1)
            let pathIndex = min(path.count - 1, Int(t * Float(path.count - 1)))
            dot.position = path[pathIndex]
            dot.scale = SIMD3<Float>(repeating: 1.15 - 0.45 * t)
        }

        if let disc = grenadeLandingDisc {
            let surface = paintSurfaceHeight(atX: landing.x, z: landing.z)
            disc.position = [landing.x, surface + 0.06, landing.z]
            let horizontal = simd_length(SIMD2<Float>(
                landing.x - container.position.x,
                landing.z - container.position.z
            ))
            let isPlant = horizontal < GameConfig.grenadePlantDistance
            let pulse = 1 + 0.07 * sinf(Float(elapsed) * 8)
            let footprint: Float = isPlant ? 0.45 : 1
            disc.scale = [footprint * pulse, 1, footprint * pulse]
        }
    }

    /// Plants the grenade at the character's feet as a proximity-free timed
    /// trap — crouching plant animation, blinking fuse, big splash.
    func plantGrenade() {
        guard !isPlayerDown, !isMatchOver, grenadeCooldown <= 0,
              inkExact >= GameConfig.grenadeInkCost,
              let container = playerContainer, let worldRoot else { return }
        if isDiving { setDiving(false) }

        inkExact -= GameConfig.grenadeInkCost
        grenadeCooldown = GameConfig.grenadeCooldownDuration

        heroAnimator?.playOnce(ModelCatalog.heroPlant, restoreAfter: .milliseconds(900))
        grenadeCooldownExact = GameConfig.grenadeCooldownDuration

        let forward = forwardVector()
        let bomb = makeGrenadeEntity()
        var pos = container.position + forward * 1.1
        pos = clampToArena(pos)
        pos.y = paintSurfaceHeight(atX: pos.x, z: pos.z) + GameConfig.grenadeVisualSize / 2
        bomb.position = pos
        worldRoot.addChild(bomb)
        plantedBombs.append(PlantedBomb(
            entity: bomb,
            detonateAt: elapsed + GameConfig.plantedGrenadeFuse,
            team: localTeam
        ))
        AudioService.shared.playSplat(volume: 0.4)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Blinking fuse pulse + detonation of planted grenades.
    func updatePlantedBombs(grid: PaintGrid) {
        guard !plantedBombs.isEmpty else { return }
        var remaining: [PlantedBomb] = []
        for bomb in plantedBombs {
            if elapsed >= bomb.detonateAt {
                explodeGrenade(at: bomb.entity.position, team: bomb.team, grid: grid, ownerIndex: 0)
                bomb.entity.removeFromParent()
            } else {
                let timeLeft = Float(bomb.detonateAt - elapsed)
                let rate: Float = timeLeft < 0.8 ? 22 : 9
                let pulse = 1 + 0.14 * abs(sinf(Float(elapsed) * rate))
                bomb.entity.scale = SIMD3<Float>(repeating: pulse)
                remaining.append(bomb)
            }
        }
        plantedBombs = remaining
    }

}
