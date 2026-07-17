import Foundation
import RealityKit
import UIKit
import simd

/// Contrôle de Zones: builds the neutral capture points and drives their
/// per-frame occupancy, scoring and live visuals. Only active when
/// `matchMode == .zoneControl` — every other mode leaves `captureZoneVisuals`
/// empty so the per-frame update is a no-op.
extension GameController {
    /// Builds the map's capture zones, each drawn as a bright circle
    /// outlined on the ground with a rising light-filament ring and a real
    /// point light. Ground anchors are nudged to the nearest clear spot and
    /// ALWAYS produce a zone — the mode can never silently start without
    /// its capture points.
    func buildCaptureZones(_ root: Entity) {
        guard matchMode == .zoneControl else { return }
        let layouts = pickCaptureZoneLayouts()
        zoneControllers = Array(repeating: nil, count: layouts.count)
        for layout in layouts {
            captureZoneVisuals.append(
                makeCaptureZoneVisual(root, center: layout.center, radius: layout.radius)
            )
        }
        NSLog("[ZoneControl] built \(layouts.count) capture zones at \(layouts.map(\.center))")
    }

    /// Per-map zone layout.
    ///
    /// • Nexus Docks — two zones flanking the CENTRAL platform on the
    ///   lateral axis (north/south), equidistant from BOTH camps: seen from
    ///   either spawn they sit left and right of the middle, so neither team
    ///   can camp "its" zone — every capture is a mid-field fight; each
    ///   anchor is nudged to the nearest obstacle-free spot.
    /// • Temple Lost — THREE zones: the shrine top of the central pyramid
    ///   (+4.5 m, fixed, where the ziplines converge) plus two neutral ground
    ///   zones on opposite diagonals (south-east and north-west), so the
    ///   fight spreads across the whole map instead of everyone funnelling
    ///   up the same summit.
    private func pickCaptureZoneLayouts() -> [(center: SIMD3<Float>, radius: Float)] {
        switch GameConfig.currentMap {
        case .templeLost:
            // Climbing routes to the summit for the bots — the ground nav
            // grid can't see the pyramid, so these chains walk them up the
            // real geometry: grand stair (west/east), across the base deck,
            // then the north/south shrine ramp. Node heights match the
            // terrain so a bot already partway up resumes mid-route.
            zoneClimbRoutes = [
                [
                    SIMD3<Float>(-13.5, 0, 0),
                    SIMD3<Float>(-9.5, 1, 0),
                    SIMD3<Float>(-5, 2, 0),
                    SIMD3<Float>(0, 2, -4.3),
                    SIMD3<Float>(0, 4.5, -2.2),
                ],
                [
                    SIMD3<Float>(13.5, 0, 0),
                    SIMD3<Float>(9.5, 1, 0),
                    SIMD3<Float>(5, 2, 0),
                    SIMD3<Float>(0, 2, 4.3),
                    SIMD3<Float>(0, 4.5, 2.2),
                ],
            ]
            var layouts: [(center: SIMD3<Float>, radius: Float)] = [(SIMD3<Float>(0, 4.5, 0), 2.4)]
            // Ground zones on opposite diagonals, past the canals, equidistant
            // from both camps — nudged to the nearest obstacle-free spot.
            for anchor in [SIMD2<Float>(16, 12), SIMD2<Float>(-16, -12)] {
                let spot = bestZoneSpot(near: anchor)
                layouts.append((SIMD3<Float>(spot.x, 0, spot.y), GameConfig.zoneControlRadius))
            }
            return layouts
        case .nexusDocks:
            zoneClimbRoutes = []
            let offset = GameConfig.arenaDepth * 0.27
            let anchors = [SIMD2<Float>(0, -offset), SIMD2<Float>(0, offset)]
            return anchors.map { anchor in
                let spot = bestZoneSpot(near: anchor)
                return (SIMD3<Float>(spot.x, 0, spot.y), GameConfig.zoneControlRadius)
            }
        }
    }

    /// Whether a fighter standing at `pos` is inside `zone`'s scoring
    /// footprint: within the horizontal circle AND at the zone's floor level
    /// — the vertical band keeps ground fighters underneath the Temple Lost
    /// pyramid (or snipers perched above a ground zone) from counting.
    func captureZoneContains(_ pos: SIMD3<Float>, zone: CaptureZoneVisual) -> Bool {
        let dy = pos.y - zone.center.y
        guard dy > -1.0, dy < 1.8 else { return false }
        return simd_length(SIMD2<Float>(pos.x - zone.center.x, pos.z - zone.center.z)) < zone.radius
    }

    /// Nearest valid zone center around `anchor`: scans a local grid and
    /// returns the closest spot with full clearance, then the closest spot
    /// with relaxed clearance, and finally the anchor itself — placement is
    /// guaranteed, never empty.
    private func bestZoneSpot(near anchor: SIMD2<Float>) -> SIMD2<Float> {
        let radius = GameConfig.zoneControlRadius
        let searchRadius: Float = 9
        var best: (point: SIMD2<Float>, distance: Float)?
        var relaxedBest: (point: SIMD2<Float>, distance: Float)?

        var dx: Float = -searchRadius
        while dx <= searchRadius {
            var dz: Float = -searchRadius
            while dz <= searchRadius {
                let point = anchor + SIMD2<Float>(dx, dz)
                let distance = simd_length(SIMD2<Float>(dx, dz))
                if captureZoneClearance(at: point, radius: radius) != nil {
                    if best == nil || distance < best!.distance {
                        best = (point, distance)
                    }
                } else if best == nil, captureZoneClearance(at: point, radius: 1.0) != nil {
                    if relaxedBest == nil || distance < relaxedBest!.distance {
                        relaxedBest = (point, distance)
                    }
                }
                dz += 1
            }
            dx += 1
        }
        return best?.point ?? relaxedBest?.point ?? anchor
    }

    /// Clear horizontal distance from `point` to the nearest wall, obstacle,
    /// water pool or spawn bubble edge — nil when a zone of `radius` simply
    /// doesn't fit there at all.
    private func captureZoneClearance(at point: SIMD2<Float>, radius: Float) -> Float? {
        let halfW = GameConfig.arenaWidth / 2
        let halfD = GameConfig.arenaDepth / 2
        var best = min(halfW - abs(point.x), halfD - abs(point.y))
        guard best > radius else { return nil }

        for obstacle in obstacles {
            let dx = max(abs(point.x - obstacle.center.x) - obstacle.halfX, 0)
            let dz = max(abs(point.y - obstacle.center.z) - obstacle.halfZ, 0)
            let dist = sqrt(dx * dx + dz * dz)
            guard dist >= radius + 0.6 else { return nil }
            best = min(best, dist)
        }
        for ramp in ramps {
            let dx = max(abs(point.x - ramp.center.x) - ramp.halfWidth, 0)
            let dz = max(abs(point.y - ramp.center.y) - ramp.halfLength, 0)
            let dist = sqrt(dx * dx + dz * dz)
            guard dist >= radius + 0.6 else { return nil }
            best = min(best, dist)
        }
        for water in waterZones {
            let dx = max(abs(point.x - water.center.x) - water.halfX, 0)
            let dz = max(abs(point.y - water.center.y) - water.halfZ, 0)
            let dist = sqrt(dx * dx + dz * dz)
            guard dist >= radius + 0.6 else { return nil }
            best = min(best, dist)
        }
        for center in spawnZoneCenters.values {
            let dist = simd_distance(point, SIMD2<Float>(center.x, center.z)) - GameConfig.spawnZoneRadius
            guard dist >= radius + 1.5 else { return nil }
            best = min(best, dist)
        }
        return best
    }

    /// Flat annulus (ring) mesh lying in the XZ plane — the crisp painted
    /// circle outline on the ground. Both windings are emitted so the ring
    /// is visible regardless of face culling / camera side.
    private func makeRingMesh(inner: Float, outer: Float, segments: Int = 64) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity((segments + 1) * 2)
        for index in 0...segments {
            let angle = Float(index) / Float(segments) * 2 * .pi
            positions.append([cos(angle) * inner, 0, sin(angle) * inner])
            positions.append([cos(angle) * outer, 0, sin(angle) * outer])
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(segments * 12)
        for index in 0..<segments {
            let base = UInt32(index * 2)
            indices += [base, base + 1, base + 2, base + 1, base + 3, base + 2]
            indices += [base + 2, base + 1, base, base + 2, base + 3, base + 1]
        }
        var descriptor = MeshDescriptor(name: "captureZoneRing")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer([SIMD3<Float>](repeating: [0, 1, 0], count: positions.count))
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// One zone's visual kit: translucent fill disc, crisp circle outline,
    /// soft glow halo, rising light filaments on a slow carousel, and a real
    /// point light bathing the spot — all starting neutral white until a
    /// team steps in.
    private func makeCaptureZoneVisual(_ root: Entity, center: SIMD3<Float>, radius: Float) -> CaptureZoneVisual {
        let neutral = UIColor(white: 0.92, alpha: 1)

        // Translucent fill so the whole scoring footprint reads on the ground.
        var discMaterial = UnlitMaterial(color: neutral)
        discMaterial.blending = .transparent(opacity: 0.16)
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: radius - 0.22),
            materials: [discMaterial]
        )
        disc.position = [center.x, center.y + 0.05, center.z]
        root.addChild(disc)

        // Crisp circle outline — the painted ring on the floor.
        var ringMaterial = UnlitMaterial(color: neutral)
        ringMaterial.blending = .transparent(opacity: 0.95)
        let ringMesh = makeRingMesh(inner: radius - 0.16, outer: radius + 0.16)
            ?? MeshResource.generateCylinder(height: 0.02, radius: radius)
        let ring = ModelEntity(mesh: ringMesh, materials: [ringMaterial])
        ring.position = [center.x, center.y + 0.08, center.z]
        root.addChild(ring)

        // Wide soft halo hugging the outline — the "light around" the circle.
        var glowMaterial = UnlitMaterial(color: neutral)
        glowMaterial.blending = .transparent(opacity: 0.2)
        let glowMesh = makeRingMesh(inner: radius - 0.05, outer: radius + 0.8)
            ?? MeshResource.generateCylinder(height: 0.015, radius: radius + 0.8)
        let glow = ModelEntity(mesh: glowMesh, materials: [glowMaterial])
        glow.position = [center.x, center.y + 0.065, center.z]
        root.addChild(glow)

        // Real point light so the zone visibly tints the ground and anyone
        // standing inside — recolored live with the controlling team.
        let light = PointLight()
        light.light.color = neutral
        light.light.intensity = 9000
        light.light.attenuationRadius = radius * 2.4
        light.position = [center.x, center.y + 1.8, center.z]
        root.addChild(light)

        // Rising light filaments ringing the edge, parented to a spinner so
        // the whole crown slowly rotates — alive instead of frozen.
        let spinner = Entity()
        spinner.position = [center.x, center.y, center.z]
        root.addChild(spinner)
        let filamentCount = 16
        var filaments: [ModelEntity] = []
        for index in 0..<filamentCount {
            let angle = Float(index) / Float(filamentCount) * 2 * .pi
            var filamentMaterial = UnlitMaterial(color: neutral)
            filamentMaterial.blending = .transparent(opacity: 0.75)
            let height: Float = index.isMultiple(of: 2) ? 1.7 : 1.05
            let filament = ModelEntity(
                mesh: .generateCylinder(height: height, radius: 0.028),
                materials: [filamentMaterial]
            )
            filament.position = [cos(angle) * radius, height / 2, sin(angle) * radius]
            spinner.addChild(filament)
            filaments.append(filament)
        }

        return CaptureZoneVisual(
            center: center,
            radius: radius,
            disc: disc,
            ring: ring,
            glow: glow,
            light: light,
            spinner: spinner,
            filaments: filaments
        )
    }

    /// Per-frame occupancy scan, scoring accumulation and win check — a
    /// no-op unless the match is actually in `.zoneControl`.
    ///
    /// Occupancy counts every LIVING fighter standing inside the circle,
    /// including divers in sponge form — swimming across your zone still
    /// holds it, so the score keeps flowing during normal ink movement.
    func updateCaptureZones(dt: Float) {
        guard matchMode == .zoneControl, !isMatchOver, !captureZoneVisuals.isEmpty else { return }
        // Local duel: the HOST is the single scoring authority. The guest
        // still scans occupancy for the zone visuals/indicators, but its
        // score mirrors the host's `coverage` broadcasts and the early-win
        // check runs on the host only — no drifting double bookkeeping.
        let isScoringAuthority = !isLocalDuel || localMatch.isHost
        let spin = simd_quatf(angle: Float(elapsed.truncatingRemainder(dividingBy: 2 * .pi * 10)) * 0.45, axis: [0, 1, 0])

        for (index, zone) in captureZoneVisuals.enumerated() {
            zone.spinner.orientation = spin

            var orangeCount = 0
            var purpleCount = 0

            if !isPlayerDown, let pos = playerContainer?.position,
               captureZoneContains(pos, zone: zone) {
                if localTeam == .orange { orangeCount += 1 } else { purpleCount += 1 }
            }
            for bot in bots where !bot.isDown {
                guard captureZoneContains(bot.container.position, zone: zone) else { continue }
                if bot.team == .orange { orangeCount += 1 } else { purpleCount += 1 }
            }

            // Visual state machine: tracked on the visual itself so EVERY
            // transition repaints — including contested → empty, which both
            // map to a nil controller.
            let state: Int
            if orangeCount > 0 && purpleCount > 0 {
                state = 3
            } else if orangeCount > 0 {
                state = 1
            } else if purpleCount > 0 {
                state = 2
            } else {
                state = 0
            }
            let controller: Team? = state == 1 ? .orange : (state == 2 ? .purple : nil)
            if index < zoneControllers.count, zoneControllers[index] != controller {
                zoneControllers[index] = controller
            }
            if zone.appliedState != state {
                zone.appliedState = state
                recolorZoneVisual(zone, state: state)
            }

            if isScoringAuthority {
                if orangeCount > 0 && purpleCount == 0 {
                    let rate = orangeCount >= GameConfig.zoneControlMaxScoringPlayers
                        ? GameConfig.zoneControlMaxRatePerSecond
                        : GameConfig.zoneControlSoloRatePerSecond
                    zoneScoreExactOrange += rate * Double(dt)
                } else if purpleCount > 0 && orangeCount == 0 {
                    let rate = purpleCount >= GameConfig.zoneControlMaxScoringPlayers
                        ? GameConfig.zoneControlMaxRatePerSecond
                        : GameConfig.zoneControlSoloRatePerSecond
                    zoneScoreExactPurple += rate * Double(dt)
                }
            }
        }

        guard isScoringAuthority else { return }
        let roundedOrange = Int(zoneScoreExactOrange.rounded(.down))
        if roundedOrange != zoneScoreOrange { zoneScoreOrange = roundedOrange }
        let roundedPurple = Int(zoneScoreExactPurple.rounded(.down))
        if roundedPurple != zoneScorePurple { zoneScorePurple = roundedPurple }

        if zoneScoreExactOrange >= GameConfig.zoneControlTargetScore
            || zoneScoreExactPurple >= GameConfig.zoneControlTargetScore {
            endMatch()
        }
    }

    /// Retints the whole visual kit of one zone — disc, outline, halo,
    /// filaments AND the point light — to the occupying team's color:
    /// orange/purple when held, golden while contested, white when empty.
    private func recolorZoneVisual(_ zone: CaptureZoneVisual, state: Int) {
        let color: UIColor
        switch state {
        case 1: color = Team.orange.uiColor
        case 2: color = Team.purple.uiColor
        case 3: color = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        default: color = UIColor(white: 0.92, alpha: 1)
        }
        let held = state == 1 || state == 2

        var discMaterial = UnlitMaterial(color: color)
        discMaterial.blending = .transparent(opacity: held ? 0.28 : 0.16)
        zone.disc.model?.materials = [discMaterial]

        var ringMaterial = UnlitMaterial(color: color)
        ringMaterial.blending = .transparent(opacity: 0.95)
        zone.ring.model?.materials = [ringMaterial]

        var glowMaterial = UnlitMaterial(color: color)
        glowMaterial.blending = .transparent(opacity: held ? 0.3 : 0.2)
        zone.glow.model?.materials = [glowMaterial]

        var filamentMaterial = UnlitMaterial(color: color)
        filamentMaterial.blending = .transparent(opacity: 0.8)
        for filament in zone.filaments {
            filament.model?.materials = [filamentMaterial]
        }

        zone.light.light.color = color
        zone.light.light.intensity = state == 0 ? 9000 : 16000
    }
}
