import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

/// Arena & decor construction: floor, walls, platforms, ramps, water,
/// ziplines and set dressing. Verbatim from `GameController`.
extension GameController {
    func buildArena(_ root: Entity) {
        let halfW = GameConfig.arenaWidth / 2
        let halfD = GameConfig.arenaDepth / 2

        // Map ground: worn asphalt at the docks, mossy stone slabs at the
        // temple, waxed factory concrete at the dairy.
        let floorFallback = floorFallbackColor
        let floorMaterial = mats?.pbr(
            floorTextureName,
            roughness: 0.8,
            scale: floorTextureScale,
            fallback: floorFallback
        ) ?? SimpleMaterial(color: floorFallback, roughness: 0.75, isMetallic: false)
        let floor = ModelEntity(
            mesh: .generateBox(size: [GameConfig.arenaWidth, 0.2, GameConfig.arenaDepth]),
            materials: [floorMaterial]
        )
        floor.position = [0, -0.1, 0]
        root.addChild(floor)

        // Tinted apron around the arena — no dark void. Sunset warmth at the
        // docks, deep jungle green at the temple, wheat gold at the dairy.
        let apronTint = apronTintColor
        let apronFallback = apronFallbackColor
        let apronMaterial = mats?.pbr(
            floorTextureName,
            tint: apronTint,
            roughness: 0.9,
            scale: [22, 22],
            fallback: apronFallback
        ) ?? SimpleMaterial(color: apronFallback, roughness: 0.9, isMetallic: false)
        let apron = ModelEntity(mesh: .generateBox(size: [170, 0.2, 170]), materials: [apronMaterial])
        apron.position = [0, -0.22, 0]
        root.addChild(apron)

        // Spawn pads under each base.
        let mainPad = ModelEntity(
            mesh: .generateCylinder(height: 0.05, radius: 1.7),
            materials: [UnlitMaterial(color: localTeam.uiColor.withAlphaComponent(0.9))]
        )
        mainPad.position = [playerHome.x, 0.055, playerHome.z]
        root.addChild(mainPad)
        if isLocalDuel {
            let remotePad = ModelEntity(
                mesh: .generateCylinder(height: 0.05, radius: 1.7),
                materials: [UnlitMaterial(color: enemyTeam.uiColor.withAlphaComponent(0.9))]
            )
            remotePad.position = [remoteHome.x, 0.055, remoteHome.z]
            root.addChild(remotePad)
        } else {
            for home in allyHomes {
                let pad = ModelEntity(
                    mesh: .generateCylinder(height: 0.05, radius: 1.3),
                    materials: [UnlitMaterial(color: Team.orange.uiColor.withAlphaComponent(0.9))]
                )
                pad.position = [home.x, 0.055, home.z]
                root.addChild(pad)
            }
            for home in enemyHomes {
                let pad = ModelEntity(
                    mesh: .generateCylinder(height: 0.05, radius: 1.3),
                    materials: [UnlitMaterial(color: Team.purple.uiColor.withAlphaComponent(0.9))]
                )
                pad.position = [home.x, 0.055, home.z]
                root.addChild(pad)
            }
        }

        // Perimeter walls — graffiti concrete at the docks, mossy carved
        // stone at the temple.
        let wallFallback = wallFallbackColor
        let wallMaterial = mats?.pbr(
            perimeterTextureName,
            roughness: 0.65,
            scale: [7, 1],
            fallback: wallFallback
        ) ?? SimpleMaterial(color: wallFallback, roughness: 0.5, isMetallic: false)
        let wallHeight: Float = 1.6
        let thickness: Float = 0.4

        let horizontalWallSize: SIMD3<Float> = [GameConfig.arenaWidth + 0.8, wallHeight, thickness]
        let verticalWallSize: SIMD3<Float> = [thickness, wallHeight, GameConfig.arenaDepth + 0.8]

        let north = ModelEntity(mesh: .generateBox(size: horizontalWallSize), materials: [wallMaterial])
        north.position = [0, wallHeight / 2, -halfD - thickness / 2]
        root.addChild(north)

        let south = ModelEntity(mesh: .generateBox(size: horizontalWallSize), materials: [wallMaterial])
        south.position = [0, wallHeight / 2, halfD + thickness / 2]
        root.addChild(south)

        let east = ModelEntity(mesh: .generateBox(size: verticalWallSize), materials: [wallMaterial])
        east.position = [halfW + thickness / 2, wallHeight / 2, 0]
        root.addChild(east)

        let west = ModelEntity(mesh: .generateBox(size: verticalWallSize), materials: [wallMaterial])
        west.position = [-halfW - thickness / 2, wallHeight / 2, 0]
        root.addChild(west)

        switch GameConfig.currentMap {
        case .nexusDocks: buildNexusDocksLayout(root)
        case .templeLost: buildTempleLostLayout(root)
        }
    }

    func buildNexusDocksLayout(_ root: Entity) {
        // ===== NEXUS DOCKS =====
        let concrete = UIColor(red: 0.5, green: 0.53, blue: 0.6, alpha: 1)
        let darkMetal = UIColor(red: 0.24, green: 0.26, blue: 0.33, alpha: 1)
        let cyanNeon = UIColor(red: 0.2, green: 0.95, blue: 0.9, alpha: 1)
        let violetNeon = UIColor(red: 0.72, green: 0.4, blue: 1, alpha: 1)
        let amberNeon = UIColor(red: 1, green: 0.72, blue: 0.2, alpha: 1)
        let limeNeon = UIColor(red: 0.66, green: 0.9, blue: 0.25, alpha: 1)
        let containerTeal = UIColor(red: 0.1, green: 0.5, blue: 0.52, alpha: 1)
        let containerViolet = UIColor(red: 0.38, green: 0.28, blue: 0.62, alpha: 1)
        let shedWall = UIColor(red: 0.35, green: 0.33, blue: 0.42, alpha: 1)

        // (1) Central platform +1.5 m — main combat zone, 4 ramp entries.
        addPlatform(root, center: [0, 0], width: 10, depth: 7, height: 1.5, color: concrete, trim: cyanNeon)
        addRamp(root, low: [-9, 0, 0], high: [-5, 1.5, 0], width: 3.2, color: concrete)
        addRamp(root, low: [9, 0, 0], high: [5, 1.5, 0], width: 3.2, color: concrete)
        addRamp(root, low: [0, 0, -7.5], high: [0, 1.5, -3.5], width: 2.6, color: concrete)
        addRamp(root, low: [0, 0, 7.5], high: [0, 1.5, 3.5], width: 2.6, color: concrete)

        // North control lane: two +2.5 m decks flanking the +5 m tower (2).
        addPlatform(root, center: [-11, -13.5], width: 14, depth: 4, height: 2.5, color: darkMetal, trim: cyanNeon)
        addPlatform(root, center: [11, -13.5], width: 14, depth: 4, height: 2.5, color: darkMetal, trim: violetNeon)
        addPlatform(root, center: [0, -14], width: 5, depth: 5, height: 5, color: darkMetal, trim: amberNeon)
        addRamp(root, low: [-22.5, 0, -13.5], high: [-18, 2.5, -13.5], width: 3, color: darkMetal)
        addRamp(root, low: [22.5, 0, -13.5], high: [18, 2.5, -13.5], width: 3, color: darkMetal)
        addRamp(root, low: [-7, 2.5, -14], high: [-2.5, 5, -14], width: 2.4, color: darkMetal)
        addRamp(root, low: [7, 2.5, -14], high: [2.5, 5, -14], width: 2.4, color: darkMetal)

        // (3) South-west defense tower +4 m — overlooks the central lane.
        addTower(root, center: [-9, 8], footprint: 4.5, height: 4, step: 2, approach: [1, 0], color: darkMetal, trim: limeNeon)
        // (4) North-east tower +4 m — controls the east side and its zipline.
        addTower(root, center: [18, -8], footprint: 4.5, height: 4, step: 2, approach: [0, -1], color: darkMetal, trim: violetNeon)
        // (5) South-east observation tower +3 m — quick access from the east spawn.
        addTower(root, center: [10, 5], footprint: 4, height: 3, step: 1.5, approach: [-1, 0], color: darkMetal, trim: amberNeon)

        // Ziplines linking the high points — board by jumping at an endpoint.
        addZipline(root, from: [0, 7.4, -14], to: [10, 5.4, 5])
        addZipline(root, from: [-9, 6.4, 8], to: [18, 6.4, -8])

        // Water pools — impassable, falling in sends you back to dry ground.
        addWaterPool(root, center: [-22, 12], halfX: 2.5, halfZ: 3)
        addWaterPool(root, center: [-5, 15.2], halfX: 4, halfZ: 2.2)
        addWaterPool(root, center: [22, 12], halfX: 3, halfZ: 2.5)
        addWaterPool(root, center: [25, -16.3], halfX: 2.5, halfZ: 1.5)
        addWaterPool(root, center: [-15, -4], halfX: 2.5, halfZ: 2)

        // Paintable climb walls — they break the spawn sightlines AND, once
        // covered in your ink, become climbable up to their walkable top.
        addClimbWall(root, center: [-12, 0], size: [0.6, 3, 7], neon: violetNeon)
        addClimbWall(root, center: [13, -2], size: [0.6, 3, 7], neon: violetNeon)
        // Extra paint-to-climb shortcuts toward the north control lane.
        addClimbWall(root, center: [-11, -10.9], size: [6, 2.5, 0.6], neon: cyanNeon)
        addClimbWall(root, center: [11, -10.9], size: [6, 2.5, 0.6], neon: amberNeon)

        // Dock sheds you can fight inside.
        addCabin(root, center: [-17, 13], doorSide: 1, wallColor: shedWall, roofColor: cyanNeon)
        addCabin(root, center: [16, 12.5], doorSide: -1, wallColor: shedWall, roofColor: violetNeon)

        // Cargo containers & crates — mid-height cover along the lanes.
        addContainer(root, center: [0, 11.5], size: [3.2, 1.7, 1.5], color: containerTeal, neon: cyanNeon)
        addContainer(root, center: [9, 14.5], size: [2.8, 1.6, 1.4], color: containerViolet, neon: violetNeon)
        addContainer(root, center: [-16, 2.5], size: [1.5, 1.6, 3], color: containerViolet, neon: amberNeon)
        addContainer(root, center: [8, -9], size: [2.8, 1.6, 1.4], color: containerTeal, neon: limeNeon)
        addObstacleBox(root, center: [-7, 0, -8], size: [1.4, 1.4, 1.4], color: amberNeon)
        addObstacleBox(root, center: [7, 0, 8], size: [1.4, 1.4, 1.4], color: limeNeon)
        addObstacleBox(root, center: [-4, 0, -10.4], size: [1.6, 1.5, 1.6], color: containerTeal)

        addPaintCan(root, at: [-20, 0, -8], color: cyanNeon)
        addPaintCan(root, at: [20, 0, 8], color: amberNeon)

        // Decorative layer — skipped by the Performance/Lite graphics presets.
        guard qualitySettings.decorEnabled else { return }
        addNeoTree(root, at: [-24, -10], foliage: violetNeon)
        addNeoTree(root, at: [24, 16], foliage: limeNeon)
        addNeoTree(root, at: [21, -11], foliage: cyanNeon)
        addNeoTree(root, at: [2, 17], foliage: amberNeon)
        addHoloPanel(root, at: [0, 6.6, -11.3], width: 3.6, height: 1.6, yaw: 0, color: cyanNeon)
        addHoloPanel(root, at: [-6.6, 4.6, 8], width: 2.4, height: 1.3, yaw: -.pi / 2, color: limeNeon)
        addHoloPanel(root, at: [15.6, 4.4, -8], width: 2.4, height: 1.3, yaw: .pi / 2, color: violetNeon)
    }

    /// ===== TEMPLE LOST ===== 72×44 m jungle-temple arena: a stepped
    /// central pyramid, two water canals crossed by plank bridges, mossy
    /// watchtowers, ziplines between the high points and glowing crystals.
    func buildTempleLostLayout(_ root: Entity) {
        let stone = UIColor(red: 0.52, green: 0.56, blue: 0.46, alpha: 1)
        let darkStone = UIColor(red: 0.36, green: 0.4, blue: 0.32, alpha: 1)
        let goldGlow = UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 1)
        let cyanCrystal = UIColor(red: 0.25, green: 0.95, blue: 0.85, alpha: 1)
        let violetCrystal = UIColor(red: 0.72, green: 0.4, blue: 1, alpha: 1)
        let jungleGreen = UIColor(red: 0.35, green: 0.85, blue: 0.4, alpha: 1)
        let limeGreen = UIColor(red: 0.66, green: 0.92, blue: 0.28, alpha: 1)
        let shrineWall = UIColor(red: 0.42, green: 0.46, blue: 0.36, alpha: 1)

        // (1) Central stepped pyramid — base deck +2 m, upper shrine +4.5 m.
        addPlatform(root, center: [0, 0], width: 14, depth: 10, height: 2, color: stone, trim: goldGlow)
        // Shrine depth 4.6 (not 5): the north/south ramps hit full height
        // BEFORE the platform's collision edge, so walking up is continuous
        // — no jump-only lip at the summit for players or bots.
        addPlatform(root, center: [0, 0], width: 7, depth: 4.6, height: 4.5, color: darkStone, trim: cyanCrystal)
        // Ground → base deck (east/west grand stairs).
        addRamp(root, low: [-12, 0, 0], high: [-7, 2, 0], width: 4, color: stone)
        addRamp(root, low: [12, 0, 0], high: [7, 2, 0], width: 4, color: stone)
        // Base deck → shrine top (north/south).
        addRamp(root, low: [0, 2, -4.8], high: [0, 4.5, -2.4], width: 2.6, color: darkStone)
        addRamp(root, low: [0, 2, 4.8], high: [0, 4.5, 2.4], width: 2.6, color: darkStone)

        // (2) Water canals crossing the field — slow, risky shortcuts.
        addWaterPool(root, center: [0, -13], halfX: 10, halfZ: 1.8)
        addWaterPool(root, center: [0, 13], halfX: 10, halfZ: 1.8)
        addWaterPool(root, center: [-28, -15], halfX: 3.2, halfZ: 3)
        addWaterPool(root, center: [28, 15], halfX: 3.2, halfZ: 3)

        // (3) Plank bridges over the canals — dry crossings under fire.
        addPlatform(root, center: [-7, -13], width: 3, depth: 5.4, height: 0.7, color: darkStone, trim: goldGlow)
        addRamp(root, low: [-7, 0, -17.4], high: [-7, 0.7, -15.7], width: 2.6, color: stone)
        addRamp(root, low: [-7, 0, -8.6], high: [-7, 0.7, -10.3], width: 2.6, color: stone)
        addPlatform(root, center: [7, 13], width: 3, depth: 5.4, height: 0.7, color: darkStone, trim: goldGlow)
        addRamp(root, low: [7, 0, 17.4], high: [7, 0.7, 15.7], width: 2.6, color: stone)
        addRamp(root, low: [7, 0, 8.6], high: [7, 0.7, 10.3], width: 2.6, color: stone)

        // (4) Watchtowers — mirrored vantage points over the canals.
        addTower(root, center: [-18, 10], footprint: 4.5, height: 4.5, step: 2.2, approach: [1, 0], color: darkStone, trim: cyanCrystal)
        addTower(root, center: [18, -10], footprint: 4.5, height: 4.5, step: 2.2, approach: [-1, 0], color: darkStone, trim: violetCrystal)
        // (5) Low observation altar north.
        addTower(root, center: [0, -18.2], footprint: 4, height: 3, step: 1.5, approach: [0, 1], color: stone, trim: goldGlow)

        // Ziplines linking the high points — board by jumping at an endpoint.
        addZipline(root, from: [0, 6.9, 0], to: [-18, 6.9, 10])
        addZipline(root, from: [18, 6.9, -10], to: [0, 5.4, -18.2])

        // Paintable climb walls — break the spawn sightlines and open
        // paint-to-climb routes toward the pyramid.
        addClimbWall(root, center: [-13, -5], size: [0.6, 3, 7], neon: cyanCrystal)
        addClimbWall(root, center: [13, 5], size: [0.6, 3, 7], neon: violetCrystal)
        addClimbWall(root, center: [-7, 8.4], size: [6, 2.5, 0.6], neon: goldGlow)
        addClimbWall(root, center: [7, -8.4], size: [6, 2.5, 0.6], neon: limeGreen)

        // Ruined shrine huts you can fight inside.
        addCabin(root, center: [-26, 13], doorSide: 1, wallColor: shrineWall, roofColor: goldGlow)
        addCabin(root, center: [26, -13], doorSide: -1, wallColor: shrineWall, roofColor: cyanCrystal)

        // Fallen stone blocks — mid-height cover along the lanes.
        addObstacleBox(root, center: [-10, 0, 15], size: [3, 1.7, 1.5], color: stone)
        addObstacleBox(root, center: [10, 0, -15], size: [3, 1.7, 1.5], color: stone)
        addObstacleBox(root, center: [-22, 0, -6], size: [1.6, 1.5, 3], color: darkStone)
        addObstacleBox(root, center: [22, 0, 6], size: [1.6, 1.5, 3], color: darkStone)
        addObstacleBox(root, center: [-14, 0, 17], size: [1.4, 1.4, 1.4], color: stone)
        addObstacleBox(root, center: [14, 0, -17], size: [1.4, 1.4, 1.4], color: stone)
        addObstacleBox(root, center: [26, 0, 0], size: [1.6, 1.5, 1.6], color: darkStone)
        addObstacleBox(root, center: [-26, 0, 0], size: [1.6, 1.5, 1.6], color: darkStone)

        addPaintCan(root, at: [-30, 0, -10], color: cyanCrystal)
        addPaintCan(root, at: [30, 0, 10], color: goldGlow)

        // Decorative layer — skipped by the Performance/Lite graphics presets.
        guard qualitySettings.decorEnabled else { return }
        addNeoTree(root, at: [-30, 18], foliage: jungleGreen)
        addNeoTree(root, at: [30, -18], foliage: limeGreen)
        addNeoTree(root, at: [-20, -19], foliage: limeGreen)
        addNeoTree(root, at: [20, 19], foliage: jungleGreen)
        addNeoTree(root, at: [-4, 19.5], foliage: jungleGreen)
        addNeoTree(root, at: [4, -19.5], foliage: limeGreen)
        addHoloPanel(root, at: [0, 6.2, -2.7], width: 3.2, height: 1.4, yaw: 0, color: goldGlow)
        addHoloPanel(root, at: [-15.8, 5, 10], width: 2.4, height: 1.3, yaw: -.pi / 2, color: cyanCrystal)
        addHoloPanel(root, at: [15.8, 5, -10], width: 2.4, height: 1.3, yaw: .pi / 2, color: violetCrystal)
    }

    /// Dockside tower: a high walkable top reached by a mid-height step deck
    /// and two gantry ramps, laid along `approach` (unit XZ direction of
    /// travel toward the tower).
    func addTower(
        _ root: Entity,
        center: SIMD2<Float>,
        footprint: Float,
        height: Float,
        step: Float,
        approach: SIMD2<Float>,
        color: UIColor,
        trim: UIColor
    ) {
        let deckLength: Float = 5
        let deckWidth: Float = 3.4
        let alongX = abs(approach.x) > abs(approach.y)
        addPlatform(root, center: center, width: footprint, depth: footprint, height: height, color: color, trim: trim)

        let stepCenter = center - approach * (footprint / 2 + deckLength / 2)
        addPlatform(
            root,
            center: stepCenter,
            width: alongX ? deckLength : deckWidth,
            depth: alongX ? deckWidth : deckLength,
            height: step,
            color: color,
            trim: trim
        )

        // Ground → step deck.
        let deckNearEdge = stepCenter - approach * (deckLength / 2)
        let ramp1Low = deckNearEdge - approach * (step * 2)
        addRamp(
            root,
            low: [ramp1Low.x, 0, ramp1Low.y],
            high: [deckNearEdge.x, step, deckNearEdge.y],
            width: 2.6,
            color: color
        )

        // Step deck → tower top, running over the deck like a dock gantry.
        let ramp2Low = stepCenter - approach * (deckLength / 2 - 0.5)
        let ramp2High = center - approach * (footprint / 2 - 0.9)
        addRamp(
            root,
            low: [ramp2Low.x, step, ramp2Low.y],
            high: [ramp2High.x, height, ramp2High.y],
            width: 2.2,
            color: color
        )
    }

    /// Turquoise dock pool — impassable and unpaintable.
    func addWaterPool(_ root: Entity, center: SIMD2<Float>, halfX: Float, halfZ: Float) {
        waterZones.append(WaterZone(center: center, halfX: halfX, halfZ: halfZ))

        var waterMaterial = UnlitMaterial(color: waterColor)
        waterMaterial.blending = .transparent(opacity: 0.8)
        let water = ModelEntity(
            mesh: .generateBox(size: [halfX * 2, 0.06, halfZ * 2], cornerRadius: 0.03),
            materials: [waterMaterial]
        )
        water.position = [center.x, 0.032, center.y]
        root.addChild(water)

        // Dark rim so the pool reads as a drop in the dock floor.
        let rimMaterial = SimpleMaterial(
            color: UIColor(red: 0.1, green: 0.12, blue: 0.2, alpha: 1),
            roughness: 0.6,
            isMetallic: false
        )
        let rimHeight: Float = 0.16
        let rimThickness: Float = 0.22
        let rims: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([halfX * 2 + rimThickness * 2, rimHeight, rimThickness], [0, 0, halfZ + rimThickness / 2]),
            ([halfX * 2 + rimThickness * 2, rimHeight, rimThickness], [0, 0, -(halfZ + rimThickness / 2)]),
            ([rimThickness, rimHeight, halfZ * 2], [halfX + rimThickness / 2, 0, 0]),
            ([rimThickness, rimHeight, halfZ * 2], [-(halfX + rimThickness / 2), 0, 0]),
        ]
        for (size, offset) in rims {
            let rim = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.04), materials: [rimMaterial])
            rim.position = SIMD3<Float>(center.x, rimHeight / 2, center.y) + offset
            root.addChild(rim)
        }
    }

    /// Bidirectional overhead cable — board by jumping at a tower endpoint.
    func addZipline(_ root: Entity, from start: SIMD3<Float>, to end: SIMD3<Float>) {
        ziplines.append(Zipline(start: start, end: end))

        let cableColor = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        let span = simd_distance(start, end)
        let cable = ModelEntity(
            mesh: .generateBox(size: [span, 0.07, 0.07]),
            materials: [UnlitMaterial(color: cableColor)]
        )
        cable.position = (start + end) / 2
        cable.orientation = simd_quatf(from: [1, 0, 0], to: simd_normalize(end - start))
        root.addChild(cable)

        for endpoint in [start, end] {
            let post = ModelEntity(
                mesh: .generateCylinder(height: 2.8, radius: 0.09),
                materials: [SimpleMaterial(color: UIColor(white: 0.25, alpha: 1), roughness: 0.4, isMetallic: true)]
            )
            post.position = [endpoint.x, endpoint.y - 1.3, endpoint.z]
            root.addChild(post)
            let pulley = ModelEntity(mesh: .generateSphere(radius: 0.16), materials: [UnlitMaterial(color: cableColor)])
            pulley.position = endpoint
            root.addChild(pulley)
        }
    }

    /// Paintable wall with a glowing top edge. Bright "paint me" panels so
    /// team splats read clearly; the top is walkable but ONLY reachable by
    /// covering the wall in your ink and sliding up it (wall-climb).
    ///
    /// Visibility is boosted deliberately: no team paint is applied here (a
    /// wall reads the same before either side paints it), so it needs strong
    /// neutral contrast on its own -- a darker tinted body, full-height
    /// glowing corner posts (visible from any angle, not just from above),
    /// and a glowing footprint ring on the ground so players can spot
    /// exactly where it's planted while running around it.
    func addClimbWall(_ root: Entity, center: SIMD2<Float>, size: SIMD3<Float>, neon: UIColor) {
        let material = mats?.pbr(
            platformTextureName,
            tint: UIColor(white: 0.62, alpha: 1),
            roughness: 0.55,
            scale: [2, 1.4],
            fallback: UIColor(red: 0.58, green: 0.56, blue: 0.62, alpha: 1)
        ) ?? SimpleMaterial(color: UIColor(red: 0.58, green: 0.56, blue: 0.62, alpha: 1), roughness: 0.5, isMetallic: false)
        let wall = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.05), materials: [material])
        wall.position = [center.x, size.y / 2, center.y]
        root.addChild(wall)
        obstacles.append(Obstacle(
            center: [center.x, 0, center.y],
            halfX: size.x / 2,
            halfZ: size.z / 2,
            baseY: 0,
            topY: size.y,
            isWalkable: true
        ))

        let edge = ModelEntity(
            mesh: .generateBox(size: [size.x + 0.08, 0.22, size.z + 0.08]),
            materials: [UnlitMaterial(color: neon)]
        )
        edge.position = [center.x, size.y - 0.11, center.y]
        root.addChild(edge)

        // Full-height glowing corner posts -- the top-edge glow alone is
        // only visible from a distance/above; these read from any angle up
        // close, including while standing right next to the wall.
        let postThickness: Float = 0.09
        let halfX = size.x / 2
        let halfZ = size.z / 2
        let cornerOffsets: [SIMD2<Float>] = [
            [-halfX + postThickness / 2, -halfZ + postThickness / 2],
            [halfX - postThickness / 2, -halfZ + postThickness / 2],
            [-halfX + postThickness / 2, halfZ - postThickness / 2],
            [halfX - postThickness / 2, halfZ - postThickness / 2],
        ]
        for offset in cornerOffsets {
            let post = ModelEntity(
                mesh: .generateBox(size: [postThickness, size.y + 0.04, postThickness]),
                materials: [UnlitMaterial(color: neon)]
            )
            post.position = [center.x + offset.x, size.y / 2, center.y + offset.y]
            root.addChild(post)
        }

        // Glowing footprint ring on the ground so the wall's exact
        // placement reads clearly at a glance, even from far away or from
        // above (top-down minimap-style readability).
        let ring = ModelEntity(
            mesh: .generateBox(size: [size.x + 0.5, 0.03, size.z + 0.5], cornerRadius: 0.08),
            materials: [UnlitMaterial(color: neon.withAlphaComponent(0.85))]
        )
        ring.position = [center.x, 0.02, center.y]
        root.addChild(ring)

        registerClimbSurface(center: center, halfX: size.x / 2, halfZ: size.z / 2, topY: size.y)
    }

    /// Registers a paintable + climbable surface for a mid-height structure.
    /// Too-low ledges (walk-up) and full towers above 5.5 m are skipped.
    func registerClimbSurface(center: SIMD2<Float>, halfX: Float, halfZ: Float, topY: Float) {
        guard topY >= 1.2, topY <= 5.5 else { return }
        climbWalls.append(ClimbWall(center: center, halfX: halfX, halfZ: halfZ, topY: topY))
    }

    /// Futuristic cargo container with a neon stripe — mid-height cover.
    func addContainer(_ root: Entity, center: SIMD2<Float>, size: SIMD3<Float>, color: UIColor, neon: UIColor) {
        addObstacleBox(root, center: [center.x, 0, center.y], size: size, color: color)
        let alongX = size.x >= size.z
        let stripe = ModelEntity(
            mesh: .generateBox(size: [
                alongX ? size.x * 0.85 : size.x + 0.06,
                0.14,
                alongX ? size.z + 0.06 : size.z * 0.85,
            ]),
            materials: [UnlitMaterial(color: neon)]
        )
        stripe.position = [center.x, size.y * 0.72, center.y]
        root.addChild(stripe)
    }

    /// Futuristic tree: dark trunk plus glowing geometric foliage blocks.
    func addNeoTree(_ root: Entity, at position: SIMD2<Float>, foliage: UIColor) {
        let trunk = ModelEntity(
            mesh: .generateCylinder(height: 2.2, radius: 0.18),
            materials: [SimpleMaterial(color: UIColor(red: 0.16, green: 0.14, blue: 0.2, alpha: 1), roughness: 0.7, isMetallic: false)]
        )
        trunk.position = [position.x, 1.1, position.y]
        root.addChild(trunk)
        obstacles.append(Obstacle(
            center: [position.x, 0, position.y],
            halfX: 0.35,
            halfZ: 0.35,
            baseY: 0,
            topY: 2.2,
            isWalkable: false
        ))

        var glowMaterial = UnlitMaterial(color: foliage)
        glowMaterial.blending = .transparent(opacity: 0.92)
        let leaves: [(SIMD3<Float>, Float)] = [
            ([0, 2.6, 0], 1.1),
            ([0.55, 2.25, 0.3], 0.65),
            ([-0.45, 2.4, -0.4], 0.55),
        ]
        for (offset, scale) in leaves {
            let leaf = ModelEntity(
                mesh: .generateBox(size: [scale, scale * 0.8, scale], cornerRadius: scale * 0.2),
                materials: [glowMaterial]
            )
            leaf.position = SIMD3<Float>(position.x, 0, position.y) + offset
            leaf.orientation = simd_quatf(angle: 0.5, axis: simd_normalize(SIMD3<Float>(0.3, 1, 0.2)))
            root.addChild(leaf)
        }
    }

    /// Holographic billboard — pure decor, no collision.
    func addHoloPanel(_ root: Entity, at position: SIMD3<Float>, width: Float, height: Float, yaw: Float, color: UIColor) {
        let frame = ModelEntity(
            mesh: .generateBox(size: [width + 0.2, height + 0.2, 0.1], cornerRadius: 0.05),
            materials: [SimpleMaterial(color: UIColor(white: 0.12, alpha: 1), roughness: 0.4, isMetallic: true)]
        )
        var screenMaterial = UnlitMaterial(color: color)
        screenMaterial.blending = .transparent(opacity: 0.75)
        let screen = ModelEntity(mesh: .generateBox(size: [width, height, 0.04]), materials: [screenMaterial])
        screen.position = [0, 0, 0.05]
        frame.addChild(screen)
        frame.position = position
        frame.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.addChild(frame)
    }

    func addObstacleBox(_ root: Entity, center: SIMD3<Float>, size: SIMD3<Float>, color: UIColor) {
        // Painted container metal at the docks, carved mossy stone at the temple.
        let material = mats?.pbr(
            blockTextureName,
            roughness: 0.55,
            scale: [max(1, (size.x / 3).rounded()), 1],
            fallback: color
        ) ?? SimpleMaterial(color: color, roughness: 0.5, isMetallic: false)
        let entity = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0.06),
            materials: [material]
        )
        entity.position = [center.x, size.y / 2, center.z]
        root.addChild(entity)
        obstacles.append(Obstacle(
            center: [center.x, 0, center.z],
            halfX: size.x / 2,
            halfZ: size.z / 2,
            baseY: 0,
            topY: size.y,
            isWalkable: true
        ))
        registerClimbSurface(center: [center.x, center.z], halfX: size.x / 2, halfZ: size.z / 2, topY: size.y)
    }

    /// Walkable elevated deck with a glowing trim band.
    func addPlatform(
        _ root: Entity,
        center: SIMD2<Float>,
        width: Float,
        depth: Float,
        height: Float,
        color: UIColor,
        trim: UIColor
    ) {
        // Docks: industrial concrete with neon seams. Temple: ancient walls
        // veined with glowing tech lines.
        let material = mats?.pbr(
            platformTextureName,
            roughness: 0.6,
            scale: [max(1, (width / 4).rounded()), max(1, (height / 3).rounded())],
            fallback: color
        ) ?? SimpleMaterial(color: color, roughness: 0.55, isMetallic: false)
        let entity = ModelEntity(
            mesh: .generateBox(size: [width, height, depth], cornerRadius: 0.05),
            materials: [material]
        )
        entity.position = [center.x, height / 2, center.y]
        root.addChild(entity)

        let strip = ModelEntity(
            mesh: .generateBox(size: [width + 0.06, 0.12, depth + 0.06]),
            materials: [UnlitMaterial(color: trim)]
        )
        strip.position = [center.x, height - 0.28, center.y]
        root.addChild(strip)

        obstacles.append(Obstacle(
            center: [center.x, 0, center.y],
            halfX: width / 2,
            halfZ: depth / 2,
            baseY: 0,
            topY: height,
            isWalkable: true
        ))
        registerClimbSurface(center: center, halfX: width / 2, halfZ: depth / 2, topY: height)
    }

    /// Axis-aligned ramp from `low` edge center up to `high` edge center.
    func addRamp(
        _ root: Entity,
        low: SIMD3<Float>,
        high: SIMD3<Float>,
        width: Float,
        color: UIColor
    ) {
        let dx = high.x - low.x
        let dz = high.z - low.z
        let length = sqrt(dx * dx + dz * dz)
        guard length > 0.01 else { return }
        let axis = SIMD2<Float>(dx / length, dz / length)
        let rise = high.y - low.y
        let slopeLength = sqrt(length * length + rise * rise)

        // Docks: perforated metal gangway. Temple: weathered wooden planks.
        let material = mats?.pbr(
            rampTextureName,
            roughness: 0.5,
            scale: [max(1, (slopeLength / 2.4).rounded()), 1],
            fallback: color
        ) ?? SimpleMaterial(color: color, roughness: 0.6, isMetallic: false)
        let entity = ModelEntity(
            mesh: .generateBox(size: [slopeLength, 0.22, width]),
            materials: [material]
        )
        let yaw = atan2(-dz, dx)
        let pitch = atan2(rise, length)
        entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [0, 0, 1])
        entity.position = [(low.x + high.x) / 2, (low.y + high.y) / 2 - 0.06, (low.z + high.z) / 2]
        root.addChild(entity)

        ramps.append(Ramp(
            center: SIMD2<Float>((low.x + high.x) / 2, (low.z + high.z) / 2),
            axis: axis,
            halfLength: length / 2,
            halfWidth: width / 2,
            lowY: low.y,
            highY: high.y
        ))
    }

    /// Small hut with an open doorway — walls block movement and shots,
    /// the roof sits above head height so characters can fight inside.
    func addCabin(
        _ root: Entity,
        center: SIMD2<Float>,
        doorSide: Float,
        wallColor: UIColor,
        roofColor: UIColor
    ) {
        let width: Float = 5
        let depth: Float = 4.4
        let height: Float = 2.2
        let thickness: Float = 0.25
        let doorWidth: Float = 1.7
        let wallMaterial = mats?.pbr(
            perimeterTextureName,
            roughness: 0.65,
            scale: [1.4, 1],
            fallback: wallColor
        ) ?? SimpleMaterial(color: wallColor, roughness: 0.65, isMetallic: false)

        func wall(size: SIMD3<Float>, at position: SIMD3<Float>) {
            let entity = ModelEntity(mesh: .generateBox(size: size), materials: [wallMaterial])
            entity.position = position
            root.addChild(entity)
            obstacles.append(Obstacle(
                center: [position.x, 0, position.z],
                halfX: size.x / 2,
                halfZ: size.z / 2,
                baseY: 0,
                topY: height,
                isWalkable: false
            ))
        }

        // Back wall (opposite the door).
        wall(size: [thickness, height, depth], at: [center.x - doorSide * (width / 2), height / 2, center.y])
        // Door wall: two segments leaving a centered opening.
        let segment = (depth - doorWidth) / 2
        let doorX = center.x + doorSide * (width / 2)
        wall(size: [thickness, height, segment], at: [doorX, height / 2, center.y - (doorWidth / 2 + segment / 2)])
        wall(size: [thickness, height, segment], at: [doorX, height / 2, center.y + (doorWidth / 2 + segment / 2)])
        // Side walls.
        wall(size: [width, height, thickness], at: [center.x, height / 2, center.y - depth / 2])
        wall(size: [width, height, thickness], at: [center.x, height / 2, center.y + depth / 2])

        // Roof slab with an overhang; above head height, so the inside is playable.
        let roof = ModelEntity(
            mesh: .generateBox(size: [width + 0.6, 0.22, depth + 0.6], cornerRadius: 0.05),
            materials: [SimpleMaterial(color: roofColor, roughness: 0.5, isMetallic: false)]
        )
        roof.position = [center.x, height + 0.11, center.y]
        root.addChild(roof)
        obstacles.append(Obstacle(
            center: [center.x, 0, center.y],
            halfX: (width + 0.6) / 2,
            halfZ: (depth + 0.6) / 2,
            baseY: height,
            topY: height + 0.22,
            isWalkable: false
        ))

        // Window glow strips on both side walls.
        let windowMaterial = UnlitMaterial(color: UIColor(white: 0.95, alpha: 0.9))
        for zOffset: Float in [-(depth / 2 + 0.04), depth / 2 + 0.04] {
            let strip = ModelEntity(mesh: .generateBox(size: [width * 0.5, 0.5, 0.06]), materials: [windowMaterial])
            strip.position = [center.x, 1.45, center.y + zOffset]
            root.addChild(strip)
        }
    }

    func addPaintCan(_ root: Entity, at position: SIMD3<Float>, color: UIColor) {
        let can = ModelEntity(
            mesh: .generateCylinder(height: 1.0, radius: 0.45),
            materials: [SimpleMaterial(color: color, roughness: 0.35, isMetallic: false)]
        )
        can.position = [position.x, 0.5, position.z]
        root.addChild(can)

        let lid = ModelEntity(
            mesh: .generateCylinder(height: 0.08, radius: 0.47),
            materials: [SimpleMaterial(color: .white, roughness: 0.3, isMetallic: false)]
        )
        lid.position = [position.x, 1.02, position.z]
        root.addChild(lid)

        obstacles.append(Obstacle(
            center: [position.x, 0, position.z],
            halfX: 0.5,
            halfZ: 0.5,
            baseY: 0,
            topY: 1.1,
            isWalkable: false
        ))
    }

    /// Colorful low-poly city blocks surrounding the arena, Splatoon-plaza style.
    func buildCityBackdrop(_ root: Entity) {
        switch GameConfig.currentMap {
        case .templeLost:
            buildJungleBackdrop(root)
            return
        case .nexusDocks:
            break
        }
        let palette: [UIColor] = [
            UIColor(red: 0.12, green: 0.72, blue: 0.7, alpha: 1),
            UIColor(red: 0.95, green: 0.35, blue: 0.62, alpha: 1),
            UIColor(red: 0.66, green: 0.86, blue: 0.2, alpha: 1),
            UIColor(red: 0.25, green: 0.45, blue: 0.95, alpha: 1),
            UIColor(red: 0.98, green: 0.8, blue: 0.25, alpha: 1),
            UIColor(red: 0.35, green: 0.3, blue: 0.55, alpha: 1),
        ]
        let neons: [UIColor] = [
            UIColor(red: 1, green: 0.55, blue: 0.1, alpha: 1),
            UIColor(red: 0.7, green: 0.35, blue: 1, alpha: 1),
            UIColor(red: 0.2, green: 0.95, blue: 0.85, alpha: 1),
        ]

        let northSouthXs: [Float] = [-24, -16, -8, 0, 8, 16, 24]
        for (index, x) in northSouthXs.enumerated() {
            let height = Float(4 + (index * 7) % 6)
            addBuilding(root, x: x, z: -25.5, width: 5.2, depth: 3.8, height: height,
                        color: palette[index % palette.count], neon: neons[index % neons.count])
            addBuilding(root, x: -x, z: 25.5, width: 5.2, depth: 3.8, height: Float(4 + ((index + 3) * 5) % 6),
                        color: palette[(index + 2) % palette.count], neon: neons[(index + 1) % neons.count])
        }

        let eastWestZs: [Float] = [-11, 0, 11]
        for (index, z) in eastWestZs.enumerated() {
            addBuilding(root, x: -34, z: z, width: 3.8, depth: 5.2, height: Float(5 + (index * 3) % 5),
                        color: palette[(index + 4) % palette.count], neon: neons[index % neons.count])
            addBuilding(root, x: 34, z: z, width: 3.8, depth: 5.2, height: Float(4 + (index * 4) % 6),
                        color: palette[(index + 1) % palette.count], neon: neons[(index + 2) % neons.count])
        }

        addBillboard(root)
        addCrane(root)
        buildOutskirts(root)
    }

    /// Temple Lost off-map world: ruined jungle skyline cutouts, giant
    /// overgrown pyramids, colossal ancient heads, a canopy of huge trees
    /// and floating crystals. Pure backdrop, zero collision.
    func buildJungleBackdrop(_ root: Entity) {
        let mossStone = UIColor(red: 0.38, green: 0.5, blue: 0.36, alpha: 1)
        let deepGreen = UIColor(red: 0.16, green: 0.45, blue: 0.28, alpha: 1)
        let canopyGreen = UIColor(red: 0.3, green: 0.75, blue: 0.38, alpha: 1)
        let goldGlow = UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 1)
        let cyanCrystal = UIColor(red: 0.25, green: 0.95, blue: 0.85, alpha: 1)
        let violetCrystal = UIColor(red: 0.72, green: 0.4, blue: 1, alpha: 1)

        // Jungle-ruins skyline cutouts north and south.
        if let skyline = mats?.unlit(skylineTextureName, cutout: true) {
            let north = ModelEntity(mesh: .generatePlane(width: 170, height: 46), materials: [skyline])
            north.position = [0, 20, -68]
            root.addChild(north)
            let south = ModelEntity(mesh: .generatePlane(width: 170, height: 46), materials: [skyline])
            south.position = [0, 20, 68]
            south.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            root.addChild(south)
        }

        // Giant overgrown step pyramids flanking the arena.
        addRuinPyramid(root, at: [-58, -30], baseSize: 30, tiers: 4, color: mossStone, glow: goldGlow)
        addRuinPyramid(root, at: [56, 34], baseSize: 34, tiers: 5, color: deepGreen, glow: cyanCrystal)
        addRuinPyramid(root, at: [62, -26], baseSize: 24, tiers: 3, color: mossStone, glow: violetCrystal)

        // Colossal ancient guardian heads watching the arena east and west.
        addGuardianHead(root, at: [-52, 12], height: 14, color: mossStone, eyes: cyanCrystal)
        addGuardianHead(root, at: [50, -8], height: 16, color: deepGreen, eyes: goldGlow)

        // Canopy ring — huge jungle trees around the perimeter.
        let treeSpots: [(SIMD2<Float>, Float)] = [
            ([-44, -18], 16), ([-40, 24], 19), ([44, 20], 17), ([40, -24], 20),
            ([-20, -40], 18), ([16, -42], 15), ([-14, 40], 17), ([22, 42], 19),
        ]
        for (spot, height) in treeSpots {
            addGiantTree(root, at: spot, height: height, foliage: canopyGreen)
        }

        // Skipped by the Performance/Lite graphics presets.
        guard qualitySettings.decorEnabled else { return }

        // Floating crystals drifting above the ruins.
        let crystalSpots: [(SIMD3<Float>, Float, UIColor)] = [
            ([-30, 22, -34], 2.6, cyanCrystal),
            ([28, 26, 30], 3.2, violetCrystal),
            ([0, 30, -50], 4, goldGlow),
            ([46, 20, 2], 2.4, cyanCrystal),
        ]
        for (position, size, color) in crystalSpots {
            let crystal = ModelEntity(
                mesh: .generateBox(size: [size, size * 1.7, size], cornerRadius: size * 0.18),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.92))]
            )
            crystal.position = position
            crystal.orientation = simd_quatf(angle: .pi / 4, axis: simd_normalize(SIMD3<Float>(0.4, 1, 0.3)))
            root.addChild(crystal)
        }

        // Distant emerald mountains in silhouette.
        let mountainSpots: [(SIMD2<Float>, Float, Float, UIColor)] = [
            ([-95, -70], 36, 46, deepGreen),
            ([-70, 95], 42, 56, mossStone),
            ([80, -90], 38, 50, deepGreen),
            ([100, 55], 34, 44, mossStone),
        ]
        for (spot, height, radius, color) in mountainSpots {
            let mountain = ModelEntity(
                mesh: .generateCone(height: height, radius: radius),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.92))]
            )
            mountain.position = [spot.x, height / 2 - 2, spot.y]
            root.addChild(mountain)
        }
    }

    /// Stepped moss-covered pyramid silhouette with a glowing shrine on top.
    func addRuinPyramid(_ root: Entity, at spot: SIMD2<Float>, baseSize: Float, tiers: Int, color: UIColor, glow: UIColor) {
        let tierHeight = baseSize * 0.16
        for tier in 0..<tiers {
            let size = baseSize * (1 - Float(tier) * 0.22)
            let block = ModelEntity(
                mesh: .generateBox(size: [size, tierHeight, size], cornerRadius: 0.4),
                materials: [SimpleMaterial(color: color, roughness: 0.85, isMetallic: false)]
            )
            block.position = [spot.x, tierHeight * (Float(tier) + 0.5), spot.y]
            root.addChild(block)
        }
        let shrine = ModelEntity(
            mesh: .generateBox(size: [baseSize * 0.14, baseSize * 0.2, baseSize * 0.14], cornerRadius: 0.3),
            materials: [UnlitMaterial(color: glow)]
        )
        shrine.position = [spot.x, tierHeight * Float(tiers) + baseSize * 0.1, spot.y]
        root.addChild(shrine)
    }

    /// Colossal weathered stone head with glowing eyes — pure backdrop.
    func addGuardianHead(_ root: Entity, at spot: SIMD2<Float>, height: Float, color: UIColor, eyes: UIColor) {
        let material = SimpleMaterial(color: color, roughness: 0.9, isMetallic: false)
        let head = ModelEntity(
            mesh: .generateBox(size: [height * 0.72, height, height * 0.66], cornerRadius: height * 0.14),
            materials: [material]
        )
        head.position = [spot.x, height / 2, spot.y]
        // Face the arena center.
        head.orientation = simd_quatf(angle: atan2(-spot.x, -spot.y), axis: [0, 1, 0])
        root.addChild(head)

        let nose = ModelEntity(
            mesh: .generateBox(size: [height * 0.14, height * 0.34, height * 0.16], cornerRadius: 0.2),
            materials: [material]
        )
        nose.position = [0, -height * 0.08, height * 0.38]
        head.addChild(nose)

        for xOffset: Float in [-height * 0.18, height * 0.18] {
            let eye = ModelEntity(
                mesh: .generateSphere(radius: height * 0.07),
                materials: [UnlitMaterial(color: eyes)]
            )
            eye.position = [xOffset, height * 0.16, height * 0.33]
            head.addChild(eye)
        }
    }

    /// Huge jungle tree — thick trunk and stacked canopy blobs.
    func addGiantTree(_ root: Entity, at spot: SIMD2<Float>, height: Float, foliage: UIColor) {
        let trunk = ModelEntity(
            mesh: .generateCylinder(height: height, radius: height * 0.06),
            materials: [SimpleMaterial(color: UIColor(red: 0.32, green: 0.24, blue: 0.16, alpha: 1), roughness: 0.85, isMetallic: false)]
        )
        trunk.position = [spot.x, height / 2, spot.y]
        root.addChild(trunk)

        let blobs: [(SIMD3<Float>, Float)] = [
            ([0, height, 0], height * 0.42),
            ([height * 0.24, height * 0.9, height * 0.14], height * 0.28),
            ([-height * 0.2, height * 0.94, -height * 0.16], height * 0.26),
        ]
        for (offset, radius) in blobs {
            let blob = ModelEntity(
                mesh: .generateSphere(radius: radius),
                materials: [SimpleMaterial(color: foliage, roughness: 0.9, isMetallic: false)]
            )
            blob.position = SIMD3<Float>(spot.x, 0, spot.y) + offset
            root.addChild(blob)
        }
    }

    /// Far decor ring around the map — the "paint factory at sunset" world:
    /// giant paint pots north, a huge gantry crane east, a factory skyline
    /// south, glowing billboards west, and stylized mountains + blimps far
    /// away. Pure backdrop, zero collision.
    func buildOutskirts(_ root: Entity) {
        let magenta = UIColor(red: 1, green: 0.3, blue: 0.62, alpha: 1)
        let turquoise = UIColor(red: 0.18, green: 0.83, blue: 0.77, alpha: 1)
        let sunOrange = UIColor(red: 1, green: 0.48, blue: 0.24, alpha: 1)
        let neonViolet = UIColor(red: 0.61, green: 0.3, blue: 1, alpha: 1)

        // (Nord) Deux pots de peinture géants derrière le spawn nord.
        addGiantPaintPot(root, at: [-15, -46], radius: 5.5, height: 22, color: magenta)
        addGiantPaintPot(root, at: [14, -48], radius: 6, height: 24, color: turquoise)

        // (Sud) Skyline d'usines colorées + cheminées fumantes (cutout).
        if let skyline = mats?.unlit(ArenaMaterials.skylineName, cutout: true) {
            let plane = ModelEntity(mesh: .generatePlane(width: 150, height: 42), materials: [skyline])
            plane.position = [0, 18, 60]
            plane.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            root.addChild(plane)
        }

        // (Ouest) Panneaux publicitaires lumineux sur pylônes.
        if let ad = mats?.unlit(ArenaMaterials.billboardName) {
            for (z, y, tilt) in [(Float(-13), Float(9), Float(0.06)), (Float(14), Float(11), Float(-0.05))] {
                let pole = ModelEntity(
                    mesh: .generateCylinder(height: y, radius: 0.5),
                    materials: [SimpleMaterial(color: UIColor(white: 0.35, alpha: 1), roughness: 0.5, isMetallic: true)]
                )
                pole.position = [-50, y / 2, z]
                root.addChild(pole)

                let frame = ModelEntity(
                    mesh: .generateBox(size: [14.6, 9.4, 0.5], cornerRadius: 0.15),
                    materials: [UnlitMaterial(color: neonViolet)]
                )
                frame.position = [-50, y, z]
                frame.orientation = simd_quatf(angle: .pi / 2 + tilt, axis: [0, 1, 0])
                root.addChild(frame)

                let screen = ModelEntity(mesh: .generatePlane(width: 14, height: 8.8), materials: [ad])
                screen.position = [-49.6, y, z]
                screen.orientation = simd_quatf(angle: .pi / 2 + tilt, axis: [0, 1, 0])
                root.addChild(screen)
            }
        }

        // Très loin — skipped by the Performance/Lite graphics presets.
        guard qualitySettings.decorEnabled else { return }

        // Montagnes stylisées en silhouette.
        let mountainSpots: [(SIMD2<Float>, Float, Float, UIColor)] = [
            ([-95, -70], 34, 42, neonViolet.withAlphaComponent(1)),
            ([-60, -100], 40, 55, magenta),
            ([70, -95], 36, 48, neonViolet),
            ([105, -40], 30, 40, sunOrange),
            ([95, 70], 38, 50, magenta),
            ([-90, 80], 32, 44, sunOrange),
        ]
        for (spot, height, radius, color) in mountainSpots {
            let mountain = ModelEntity(
                mesh: .generateCone(height: height, radius: radius),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.9))]
            )
            mountain.position = [spot.x, height / 2 - 2, spot.y]
            root.addChild(mountain)
        }

        // Dirigeables flottants.
        for (pos, color) in [(SIMD3<Float>(-35, 34, -70), magenta), (SIMD3<Float>(50, 40, 55), turquoise)] {
            let hull = ModelEntity(mesh: .generateSphere(radius: 4), materials: [UnlitMaterial(color: color)])
            hull.scale = [2.4, 1, 1]
            hull.position = pos
            root.addChild(hull)
            let cabin = ModelEntity(
                mesh: .generateBox(size: [3.4, 1.1, 1.4], cornerRadius: 0.3),
                materials: [UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))]
            )
            cabin.position = pos + SIMD3<Float>(0, -4.4, 0)
            root.addChild(cabin)
        }
    }

    /// 20+ m tall paint pot with a white lid and a glossy drip running down
    /// the side — the signature off-map landmark of the paint factory.
    func addGiantPaintPot(_ root: Entity, at spot: SIMD2<Float>, radius: Float, height: Float, color: UIColor) {
        let bodyMaterial = mats?.pbr(
            ArenaMaterials.containerName,
            tint: color,
            roughness: 0.45,
            scale: [3, 2],
            fallback: color
        ) ?? SimpleMaterial(color: color, roughness: 0.4, isMetallic: false)
        let body = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [bodyMaterial])
        body.position = [spot.x, height / 2, spot.y]
        root.addChild(body)

        let lid = ModelEntity(
            mesh: .generateCylinder(height: height * 0.045, radius: radius * 1.06),
            materials: [SimpleMaterial(color: UIColor(white: 0.95, alpha: 1), roughness: 0.3, isMetallic: false)]
        )
        lid.position = [spot.x, height + height * 0.02, spot.y]
        root.addChild(lid)

        // Paint drip spilling over the rim.
        let drip = ModelEntity(mesh: .generateSphere(radius: radius * 0.32), materials: [UnlitMaterial(color: color)])
        drip.scale = [1, 2.6, 0.55]
        drip.position = [spot.x + radius * 0.82, height - radius * 0.4, spot.y]
        root.addChild(drip)
    }

    /// (Est) Grue de chantier stylisée géante dominant le côté est — backdrop.
    func addCrane(_ root: Entity) {
        let metal = SimpleMaterial(color: UIColor(red: 1, green: 0.78, blue: 0.16, alpha: 1), roughness: 0.45, isMetallic: true)
        let mast = ModelEntity(mesh: .generateBox(size: [2.2, 30, 2.2]), materials: [metal])
        mast.position = [48, 15, -8]
        root.addChild(mast)
        let jib = ModelEntity(mesh: .generateBox(size: [1.8, 1.6, 34]), materials: [metal])
        jib.position = [48, 28.5, 6]
        root.addChild(jib)
        let counterweight = ModelEntity(
            mesh: .generateBox(size: [3, 3, 4], cornerRadius: 0.2),
            materials: [SimpleMaterial(color: UIColor(red: 0.61, green: 0.3, blue: 1, alpha: 1), roughness: 0.5, isMetallic: false)]
        )
        counterweight.position = [48, 27, -10]
        root.addChild(counterweight)
        let cable = ModelEntity(
            mesh: .generateBox(size: [0.16, 8, 0.16]),
            materials: [SimpleMaterial(color: UIColor(white: 0.2, alpha: 1), roughness: 0.5, isMetallic: false)]
        )
        cable.position = [48, 23.5, 18]
        root.addChild(cable)
        // The crane carries a hanging paint can, not a container.
        let can = ModelEntity(
            mesh: .generateCylinder(height: 4.4, radius: 2.2),
            materials: [SimpleMaterial(color: UIColor(red: 1, green: 0.83, blue: 0.16, alpha: 1), roughness: 0.35, isMetallic: false)]
        )
        can.position = [48, 17.5, 18]
        root.addChild(can)
        let canLid = ModelEntity(
            mesh: .generateCylinder(height: 0.3, radius: 2.3),
            materials: [SimpleMaterial(color: UIColor(white: 0.95, alpha: 1), roughness: 0.3, isMetallic: false)]
        )
        canLid.position = [48, 19.85, 18]
        root.addChild(canLid)
    }

    func addBuilding(
        _ root: Entity,
        x: Float,
        z: Float,
        width: Float,
        depth: Float,
        height: Float,
        color: UIColor,
        neon: UIColor
    ) {
        let building = ModelEntity(
            mesh: .generateBox(size: [width, height, depth]),
            materials: [SimpleMaterial(color: color, roughness: 0.7, isMetallic: false)]
        )
        building.position = [x, height / 2, z]
        root.addChild(building)

        // Neon strip on the side facing the arena.
        let strip = ModelEntity(
            mesh: .generateBox(size: [width * 0.65, 0.32, 0.08]),
            materials: [UnlitMaterial(color: neon)]
        )
        if abs(z) > abs(x) {
            let offset: Float = z > 0 ? -(depth / 2 + 0.05) : (depth / 2 + 0.05)
            strip.position = [x, height * 0.72, z + offset]
        } else {
            let offset: Float = x > 0 ? -(width / 2 + 0.05) : (width / 2 + 0.05)
            strip.position = [x + offset, height * 0.72, z]
            strip.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        }
        root.addChild(strip)

        // Window bands — skipped by the Performance/Lite graphics presets.
        guard qualitySettings.decorEnabled else { return }
        let windowMaterial = UnlitMaterial(color: UIColor(white: 0.95, alpha: 0.85))
        let bandCount = max(1, Int(height / 2.2))
        for band in 0..<bandCount {
            let y = 1.4 + Float(band) * 2.2
            guard y < height - 0.8 else { break }
            let windows = ModelEntity(
                mesh: .generateBox(size: [width * 0.8, 0.34, depth * 0.8 + 0.04]),
                materials: [windowMaterial]
            )
            windows.position = [x, y, z]
            root.addChild(windows)
        }
    }

    func addBillboard(_ root: Entity) {
        let pole = ModelEntity(
            mesh: .generateCylinder(height: 5.0, radius: 0.18),
            materials: [SimpleMaterial(color: UIColor(white: 0.3, alpha: 1), roughness: 0.5, isMetallic: false)]
        )
        pole.position = [0, 2.5, -21.4]
        root.addChild(pole)

        let panel = ModelEntity(
            mesh: .generateBox(size: [6.4, 2.6, 0.22], cornerRadius: 0.08),
            materials: [SimpleMaterial(color: UIColor(white: 0.1, alpha: 1), roughness: 0.4, isMetallic: false)]
        )
        panel.position = [0, 5.4, -21.4]
        root.addChild(panel)

        if let ad = mats?.unlit(ArenaMaterials.billboardName) {
            let screen = ModelEntity(mesh: .generatePlane(width: 6.0, height: 2.3), materials: [ad])
            screen.position = [0, 5.4, -21.26]
            root.addChild(screen)
        } else {
            let orangeBar = ModelEntity(
                mesh: .generateBox(size: [2.8, 2.1, 0.06]),
                materials: [UnlitMaterial(color: Team.orange.uiColor)]
            )
            orangeBar.position = [-1.6, 5.4, -21.26]
            root.addChild(orangeBar)

            let purpleBar = ModelEntity(
                mesh: .generateBox(size: [2.8, 2.1, 0.06]),
                materials: [UnlitMaterial(color: Team.purple.uiColor)]
            )
            purpleBar.position = [1.6, 5.4, -21.26]
            root.addChild(purpleBar)
        }
    }

}
