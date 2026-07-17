import Foundation
import RealityKit
import UIKit
import simd

/// ENTRAÎNEMENT sandbox: a small dedicated range, entirely separate from the
/// three real combat maps (Nexus Docks / Temple Lost / SplashCheese, which
/// this file never touches). No bots, no timer, weapon switch always
/// available from the HUD — just mannequins, moving targets and paintable
/// walls to test coverage.
extension GameController {
    /// Simple two-tone sky, independent of `GameConfig.currentMap` so the
    /// range never inherits a combat map's art direction.
    func addTrainingSkyDome(_ root: Entity) {
        let material = UnlitMaterial(color: UIColor(red: 0.62, green: 0.72, blue: 0.86, alpha: 1))
        let dome = ModelEntity(mesh: .generateSphere(radius: 150), materials: [material])
        dome.scale = [-1, 1, 1]
        root.addChild(dome)
    }

    /// Flat neutral range: perimeter walls, a couple of paintable test
    /// walls, static mannequins at varying distances and a small weapon
    /// rack prop (purely decorative — the real switcher lives in the HUD).
    func buildTrainingArena(_ root: Entity) {
        let half = GameConfig.trainingArenaSize / 2
        let concrete = UIColor(red: 0.58, green: 0.6, blue: 0.64, alpha: 1)
        let lane = UIColor(red: 0.5, green: 0.53, blue: 0.58, alpha: 1)
        let neon = UIColor(red: 0.25, green: 0.9, blue: 0.75, alpha: 1)

        let floorMaterial = SimpleMaterial(color: concrete, roughness: 0.85, isMetallic: false)
        let floor = ModelEntity(
            mesh: .generateBox(size: [GameConfig.trainingArenaSize, 0.2, GameConfig.trainingArenaSize]),
            materials: [floorMaterial]
        )
        floor.position = [0, -0.1, 0]
        root.addChild(floor)

        let apron = ModelEntity(
            mesh: .generateBox(size: [170, 0.2, 170]),
            materials: [SimpleMaterial(color: lane, roughness: 0.9, isMetallic: false)]
        )
        apron.position = [0, -0.22, 0]
        root.addChild(apron)

        // Perimeter walls.
        let wallHeight: Float = 1.6
        let thickness: Float = 0.4
        let wallMaterial = SimpleMaterial(color: lane, roughness: 0.6, isMetallic: false)
        let horizontalWallSize: SIMD3<Float> = [GameConfig.trainingArenaSize + 0.8, wallHeight, thickness]
        let verticalWallSize: SIMD3<Float> = [thickness, wallHeight, GameConfig.trainingArenaSize + 0.8]
        for (offset, size) in [
            (SIMD3<Float>(0, wallHeight / 2, -half - thickness / 2), horizontalWallSize),
            (SIMD3<Float>(0, wallHeight / 2, half + thickness / 2), horizontalWallSize),
            (SIMD3<Float>(half + thickness / 2, wallHeight / 2, 0), verticalWallSize),
            (SIMD3<Float>(-half - thickness / 2, wallHeight / 2, 0), verticalWallSize),
        ] {
            let wall = ModelEntity(mesh: .generateBox(size: size), materials: [wallMaterial])
            wall.position = offset
            root.addChild(wall)
        }

        // Spawn pad, matching the combat maps' visual language.
        let pad = ModelEntity(
            mesh: .generateCylinder(height: 0.05, radius: 1.7),
            materials: [UnlitMaterial(color: localTeam.uiColor.withAlphaComponent(0.9))]
        )
        pad.position = [playerHome.x, 0.055, playerHome.z]
        root.addChild(pad)

        // Two dedicated paintable test walls — reuses the standard
        // paint-to-climb wall so coverage testing feels identical to a
        // real match.
        addClimbWall(root, center: [-half + 3, -half * 0.35], size: [0.6, 2.6, 8], neon: neon)
        addClimbWall(root, center: [half - 3, half * 0.35], size: [0.6, 2.6, 8], neon: neon)
        // Low cover blocks to break sightlines, just like a real arena.
        addObstacleBox(root, center: [-4, 0, 6], size: [1.6, 1.4, 1.6], color: lane)
        addObstacleBox(root, center: [4, 0, -6], size: [1.6, 1.4, 1.6], color: lane)
    }

    /// Static mannequins at varying distances + a couple of side-to-side
    /// moving targets. Registered as normal obstacles so shots actually
    /// splat paint on impact — no HP/kill tracking needed for a sandbox.
    func buildTrainingTargets(_ root: Entity) {
        let skin = UIColor(red: 0.85, green: 0.68, blue: 0.55, alpha: 1)
        let vest = UIColor(red: 0.9, green: 0.35, blue: 0.2, alpha: 1)
        let mannequinSize: SIMD3<Float> = [0.62, GameConfig.characterHeight * 0.82, 0.4]

        func addMannequin(at position: SIMD3<Float>) {
            let body = ModelEntity(
                mesh: .generateBox(size: mannequinSize, cornerRadius: 0.1),
                materials: [SimpleMaterial(color: skin, roughness: 0.7, isMetallic: false)]
            )
            body.position = [position.x, mannequinSize.y / 2, position.z]
            root.addChild(body)
            let stripe = ModelEntity(
                mesh: .generateBox(size: [mannequinSize.x + 0.02, mannequinSize.y * 0.4, mannequinSize.z + 0.02]),
                materials: [UnlitMaterial(color: vest)]
            )
            stripe.position = [position.x, mannequinSize.y * 0.62, position.z]
            root.addChild(stripe)
            obstacles.append(Obstacle(
                center: [position.x, 0, position.z],
                halfX: mannequinSize.x / 2,
                halfZ: mannequinSize.z / 2,
                baseY: 0,
                topY: mannequinSize.y,
                isWalkable: false
            ))
        }

        // Fixed mannequins at short / mid / long range.
        addMannequin(at: [playerHome.x + 6, 0, 3])
        addMannequin(at: [playerHome.x + 6, 0, -3])
        addMannequin(at: [playerHome.x + 12, 0, 0])
        addMannequin(at: [playerHome.x + 16, 0, 5])

        // Two moving targets — simple horizontal back-and-forth.
        func addMovingTarget(at position: SIMD3<Float>, axis: SIMD3<Float>, amplitude: Float, speed: Float, phase: Float) {
            let target = ModelEntity(
                mesh: .generateBox(size: mannequinSize, cornerRadius: 0.1),
                materials: [SimpleMaterial(color: skin, roughness: 0.7, isMetallic: false)]
            )
            target.position = [position.x, mannequinSize.y / 2, position.z]
            root.addChild(target)
            let stripe = ModelEntity(
                mesh: .generateBox(size: [mannequinSize.x + 0.02, 0.16, mannequinSize.z + 0.02]),
                materials: [UnlitMaterial(color: UIColor(red: 0.25, green: 0.9, blue: 0.75, alpha: 1))]
            )
            stripe.position = [0, mannequinSize.y * 0.5, 0]
            target.addChild(stripe)

            let obstacleIndex = obstacles.count
            obstacles.append(Obstacle(
                center: [position.x, 0, position.z],
                halfX: mannequinSize.x / 2,
                halfZ: mannequinSize.z / 2,
                baseY: 0,
                topY: mannequinSize.y,
                isWalkable: false
            ))
            trainingTargets.append(TrainingTarget(
                entity: target,
                obstacleIndex: obstacleIndex,
                baseCenter: position,
                axis: axis,
                amplitude: amplitude,
                speed: speed,
                phase: phase
            ))
        }

        addMovingTarget(
            at: [playerHome.x + 9, 0, -8],
            axis: [0, 0, 1], amplitude: 4, speed: 0.6, phase: 0
        )
        addMovingTarget(
            at: [playerHome.x + 14, 0, 8],
            axis: [0, 0, 1], amplitude: 3.5, speed: 0.8, phase: 1.6
        )
    }

    /// Slides the moving targets back and forth every frame, keeping the
    /// underlying obstacle in sync so shots still land accurately.
    func updateTrainingTargets(dt: Float) {
        guard !trainingTargets.isEmpty else { return }
        for target in trainingTargets {
            let t = Float(elapsed) * target.speed + target.phase
            let offset = target.axis * (sin(t) * target.amplitude)
            let newPosition = target.baseCenter + offset
            target.entity.position = [newPosition.x, target.entity.position.y, newPosition.z]
            guard target.obstacleIndex < obstacles.count else { continue }
            var obstacle = obstacles[target.obstacleIndex]
            obstacle = Obstacle(
                center: [newPosition.x, 0, newPosition.z],
                halfX: obstacle.halfX,
                halfZ: obstacle.halfZ,
                baseY: obstacle.baseY,
                topY: obstacle.topY,
                isWalkable: obstacle.isWalkable,
                passThroughTeam: obstacle.passThroughTeam,
                decalCount: obstacle.decalCount
            )
            obstacles[target.obstacleIndex] = obstacle
        }
    }
}
