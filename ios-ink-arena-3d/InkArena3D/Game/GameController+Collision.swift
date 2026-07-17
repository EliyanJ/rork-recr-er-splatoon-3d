import Foundation
import RealityKit
import UIKit
import simd

/// Movement collision, ground/wall heights, ramps, water, ziplines and
/// wall-climb resolution. Verbatim from `GameController` — no behaviour change.
extension GameController {
    /// Slides the player up a nearby climb wall covered in their ink.
    /// Returns true while actively climbing — the caller then skips gravity
    /// and ground settling. Reaching the top mantles onto the walkable roof.
    func wallClimb(_ pos: inout SIMD3<Float>, currentY: Float, moveDir: SIMD3<Float>, dt: Float) -> Bool {
        // Climbing is now EXCLUSIVE to the sponge form: only while diving can
        // the character scale a painted wall.
        guard moveDir != .zero, ziplineRide == nil, isDiving else { return false }
        let move2 = SIMD2<Float>(moveDir.x, moveDir.z)
        for wall in climbWalls {
            guard currentY < wall.topY - 0.05 else { continue }
            let dx = pos.x - wall.center.x
            let dz = pos.z - wall.center.y
            guard abs(dx) <= wall.halfX + GameConfig.wallClimbReach,
                  abs(dz) <= wall.halfZ + GameConfig.wallClimbReach else { continue }
            // Nearest face normal: the axis sticking out the furthest.
            let excessX = abs(dx) - wall.halfX
            let excessZ = abs(dz) - wall.halfZ
            let normal: SIMD2<Float> = excessX > excessZ
                ? [dx >= 0 ? 1 : -1, 0]
                : [0, dz >= 0 ? 1 : -1]
            // Must lean toward the wall face — very forgiving so barely
            // brushing into a wall in sponge form is enough to grab it.
            // EXCEPTION: once already climbing and within a short stretch of
            // the top, keep going even if the push dot momentarily dips (a
            // thumbstick blip right before mantling). Otherwise the climb
            // drops for one frame, gravity nudges the body down, and the wall
            // re-grabs the very next frame — visible as the character
            // vibrating right at the top of certain walls.
            let nearTop = wall.topY - currentY <= GameConfig.wallClimbTopCommitDistance
            guard simd_dot(move2, -normal) > GameConfig.wallClimbPushThreshold || (isClimbing && nearTop) else { continue }

            // Climbing is purely geometric: every wall / base crate is
            // climbable while in sponge form, regardless of paint (walls are
            // no longer paintable at all). Climb speed is constant.
            let climbSpeed = GameConfig.wallClimbSpeed

            let newY = min(wall.topY, currentY + climbSpeed * dt)
            if newY >= wall.topY - 0.02 {
                // Mantle: step onto the wall's walkable top.
                pos.x = min(max(pos.x, wall.center.x - wall.halfX + 0.3), wall.center.x + wall.halfX - 0.3)
                pos.z = min(max(pos.z, wall.center.y - wall.halfZ + 0.3), wall.center.y + wall.halfZ - 0.3)
                pos.y = wall.topY
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                // Pin to the wall face while sliding up.
                let face: Float = 0.72
                if normal.x != 0 {
                    pos.x = wall.center.x + normal.x * (wall.halfX + face)
                    pos.z = min(max(pos.z, wall.center.y - wall.halfZ), wall.center.y + wall.halfZ)
                } else {
                    pos.z = wall.center.y + normal.y * (wall.halfZ + face)
                    pos.x = min(max(pos.x, wall.center.x - wall.halfX), wall.center.x + wall.halfX)
                }
                pos.y = newY
            }
            return true
        }
        return false
    }

    /// Swept blocker test for a moving projectile: samples the segment
    /// travelled this frame every ~12 cm so fast drops can never tunnel
    /// through thin walls between two frames. Returns the first contact
    /// point along the path plus which obstacle was struck, or nil when the
    /// whole segment is clear.
    func sweepObstacleHit(
        from start: SIMD3<Float>, to end: SIMD3<Float>, projectileTeam: Team? = nil
    ) -> (point: SIMD3<Float>, obstacleIndex: Int)? {
        let delta = end - start
        let distance = simd_length(delta)
        guard distance > 0.0001 else {
            if let index = obstacleIndexHit(end, projectileTeam: projectileTeam) { return (end, index) }
            return nil
        }
        let steps = max(1, Int(ceil(distance / 0.12)))
        for i in 1...steps {
            let p = start + delta * (Float(i) / Float(steps))
            if let index = obstacleIndexHit(p, projectileTeam: projectileTeam) { return (p, index) }
        }
        return nil
    }

    /// Blocker test for a point. `projectileTeam` lets a team's own shield
    /// wall be shot straight through while still stopping enemy fire.
    func obstacleHit(_ position: SIMD3<Float>, projectileTeam: Team? = nil) -> Bool {
        obstacleIndexHit(position, projectileTeam: projectileTeam) != nil
    }

    /// Same test as `obstacleHit`, but also returns which obstacle matched so
    /// callers can paint/clamp against that specific surface's own bounds.
    /// Uses the spatial broadphase (single-cell lookup) in a normal match and
    /// falls back to the full linear scan in training or for out-of-grid
    /// points — the precise per-obstacle test is identical either way.
    func obstacleIndexHit(_ position: SIMD3<Float>, projectileTeam: Team? = nil) -> Int? {
        if isTraining { return legacyObstacleIndexHit(position, projectileTeam: projectileTeam) }
        guard let candidates = obstacleGrid?.obstacleCandidates(x: position.x, z: position.z) else {
            return legacyObstacleIndexHit(position, projectileTeam: projectileTeam)
        }
        for i in candidates {
            let index = Int(i)
            let obstacle = obstacles[index]
            if let pass = obstacle.passThroughTeam, pass == projectileTeam { continue }
            if abs(position.x - obstacle.center.x) < obstacle.halfX + 0.1,
               abs(position.z - obstacle.center.z) < obstacle.halfZ + 0.1,
               position.y > obstacle.baseY,
               position.y < obstacle.topY {
                return index
            }
        }
        return nil
    }

    /// Legacy full linear scan over every obstacle — identical test, used as
    /// the safe fallback when the spatial grid is unavailable (training,
    /// out-of-grid points).
    private func legacyObstacleIndexHit(_ position: SIMD3<Float>, projectileTeam: Team? = nil) -> Int? {
        for index in obstacles.indices {
            let obstacle = obstacles[index]
            if let pass = obstacle.passThroughTeam, pass == projectileTeam { continue }
            if abs(position.x - obstacle.center.x) < obstacle.halfX + 0.1,
               abs(position.z - obstacle.center.z) < obstacle.halfZ + 0.1,
               position.y > obstacle.baseY,
               position.y < obstacle.topY {
                return index
            }
        }
        return nil
    }

    func clampToArena(_ position: SIMD3<Float>) -> SIMD3<Float> {
        var pos = position
        let halfW = GameConfig.arenaWidth / 2 - 0.75
        let halfD = GameConfig.arenaDepth / 2 - 0.75
        pos.x = min(max(pos.x, -halfW), halfW)
        pos.z = min(max(pos.z, -halfD), halfD)
        return pos
    }

    /// True when (x, z) lies inside any water pool.
    func isInWater(x: Float, z: Float) -> Bool {
        for zone in waterZones
        where abs(x - zone.center.x) < zone.halfX && abs(z - zone.center.y) < zone.halfZ {
            return true
        }
        return false
    }

    /// Pushes a grounded character out of water pools — water is impassable
    /// on foot; only a jump can cross (and dunks send you back to dry land).
    func resolveWater(_ position: SIMD3<Float>, currentY: Float) -> SIMD3<Float> {
        guard currentY < 0.45 else { return position }
        var pos = position
        let radius: Float = 0.55
        for zone in waterZones {
            let dx = pos.x - zone.center.x
            let dz = pos.z - zone.center.y
            let penX = zone.halfX + radius - abs(dx)
            let penZ = zone.halfZ + radius - abs(dz)
            if penX > 0, penZ > 0 {
                if penX < penZ {
                    pos.x = zone.center.x + (dx < 0 ? -(zone.halfX + radius) : (zone.halfX + radius))
                } else {
                    pos.z = zone.center.y + (dz < 0 ? -(zone.halfZ + radius) : (zone.halfZ + radius))
                }
            }
        }
        return pos
    }

    /// Pushes a character out of blockers, ignoring ledges it can step onto
    /// and anything above head height (cabin roofs).
    func resolveObstacles(_ position: SIMD3<Float>, currentY: Float, team: Team? = nil) -> SIMD3<Float> {
        var pos = position
        let radius: Float = 0.7
        for obstacle in obstacles {
            // A team walks straight through its own shield wall.
            if let pass = obstacle.passThroughTeam, pass == team { continue }
            if obstacle.topY <= currentY + GameConfig.stepUpHeight { continue }
            if obstacle.baseY >= currentY + GameConfig.characterHeight * 0.9 { continue }
            let dx = pos.x - obstacle.center.x
            let dz = pos.z - obstacle.center.z
            let penX = obstacle.halfX + radius - abs(dx)
            let penZ = obstacle.halfZ + radius - abs(dz)
            if penX > 0, penZ > 0 {
                if penX < penZ {
                    pos.x = obstacle.center.x + (dx < 0 ? -(obstacle.halfX + radius) : (obstacle.halfX + radius))
                } else {
                    pos.z = obstacle.center.z + (dz < 0 ? -(obstacle.halfZ + radius) : (obstacle.halfZ + radius))
                }
            }
        }
        return pos
    }

    /// Treats every ramp as a SOLID wedge: you can stand on its sloped deck,
    /// but you can never walk underneath it or clip through its side. When a
    /// character's feet are inside a ramp footprint and the deck above them is
    /// too high to step onto, it is pushed back out along the shortest exit —
    /// closing the gap under the ramp that previously let players fall/pass
    /// through the geometry.
    func resolveRamps(_ position: SIMD3<Float>, currentY: Float) -> SIMD3<Float> {
        var pos = position
        let radius: Float = 0.5
        for ramp in ramps {
            let px = pos.x - ramp.center.x
            let pz = pos.z - ramp.center.y
            var along = px * ramp.axis.x + pz * ramp.axis.y
            var across = -px * ramp.axis.y + pz * ramp.axis.x
            guard abs(along) <= ramp.halfLength + radius,
                  abs(across) <= ramp.halfWidth + radius else { continue }
            // Deck height at the clamped footprint point.
            let t = min(max((along + ramp.halfLength) / (2 * ramp.halfLength), 0), 1)
            let deckY = ramp.lowY + t * (ramp.highY - ramp.lowY)
            // Standing on (or able to step onto) the deck: not a collision.
            guard deckY > currentY + GameConfig.stepUpHeight else { continue }
            // The head is already clear above the deck (rare high catwalk):
            // let the character walk under without snagging.
            guard deckY < currentY + GameConfig.characterHeight else { continue }
            // Push out along the shortest local axis, then rotate back to world.
            let penAlong = ramp.halfLength + radius - abs(along)
            let penAcross = ramp.halfWidth + radius - abs(across)
            if penAlong < penAcross {
                along += along >= 0 ? penAlong : -penAlong
            } else {
                across += across >= 0 ? penAcross : -penAcross
            }
            pos.x = ramp.center.x + along * ramp.axis.x - across * ramp.axis.y
            pos.z = ramp.center.y + along * ramp.axis.y + across * ramp.axis.x
        }
        return pos
    }

    /// Ramp surface height at a point, or nil when outside the ramp footprint.
    func rampHeight(_ ramp: Ramp, x: Float, z: Float) -> Float? {
        let px = x - ramp.center.x
        let pz = z - ramp.center.y
        let along = px * ramp.axis.x + pz * ramp.axis.y
        let across = -px * ramp.axis.y + pz * ramp.axis.x
        guard abs(along) <= ramp.halfLength + 0.05, abs(across) <= ramp.halfWidth else { return nil }
        let t = min(max((along + ramp.halfLength) / (2 * ramp.halfLength), 0), 1)
        return ramp.lowY + t * (ramp.highY - ramp.lowY)
    }

    /// Runs `body` for every WALKABLE obstacle that could cover (x, z): the
    /// spatial grid's single-cell candidates in a normal match, or the full
    /// `walkableObstacles` list as a safe fallback (training, no grid, or an
    /// out-of-grid point). Callers still apply their own precise test.
    private func forEachWalkableCandidate(atX x: Float, z: Float, _ body: (Obstacle) -> Void) {
        if !isTraining, let candidates = obstacleGrid?.obstacleCandidates(x: x, z: z) {
            for i in candidates {
                let obstacle = obstacles[Int(i)]
                if obstacle.isWalkable { body(obstacle) }
            }
        } else {
            for obstacle in walkableObstacles { body(obstacle) }
        }
    }

    /// Ramp equivalent of `forEachWalkableCandidate`.
    private func forEachRampCandidate(atX x: Float, z: Float, _ body: (Ramp) -> Void) {
        if !isTraining, let candidates = obstacleGrid?.rampCandidates(x: x, z: z) {
            for i in candidates { body(ramps[Int(i)]) }
        } else {
            for ramp in ramps { body(ramp) }
        }
    }

    /// Height a character standing at (x, z) can occupy, limited to ledges
    /// reachable from its current height.
    func walkableHeight(atX x: Float, z: Float, currentY: Float) -> Float {
        var best: Float = 0
        forEachWalkableCandidate(atX: x, z: z) { obstacle in
            if obstacle.topY <= currentY + GameConfig.stepUpHeight,
               abs(x - obstacle.center.x) <= obstacle.halfX + 0.2,
               abs(z - obstacle.center.z) <= obstacle.halfZ + 0.2 {
                best = max(best, obstacle.topY)
            }
        }
        forEachRampCandidate(atX: x, z: z) { ramp in
            if let height = rampHeight(ramp, x: x, z: z), height <= currentY + GameConfig.stepUpHeight {
                best = max(best, height)
            }
        }
        return best
    }

    /// Declared surface plating the point (x, z): the highest crate/platform
    /// top or ramp deck under it, expressed as a fixed plane + edge bounds so
    /// paint is plated flat/at-slope and cut flush to the real surface edges.
    /// Returns nil when the open floor is the highest surface (no clip needed).
    func paintSurface(atX x: Float, z: Float) -> SurfaceClip? {
        var best: Float = 0
        var result: SurfaceClip? = nil
        forEachWalkableCandidate(atX: x, z: z) { obstacle in
            guard abs(x - obstacle.center.x) <= obstacle.halfX,
                  abs(z - obstacle.center.z) <= obstacle.halfZ else { return }
            if obstacle.topY > best {
                best = obstacle.topY
                // Crate/platform top: a dead-flat horizontal plane, clipped to
                // its rectangular footprint — paint lands at strictly 0°.
                result = SurfaceClip(
                    center: [obstacle.center.x, obstacle.topY, obstacle.center.z],
                    normal: [0, 1, 0],
                    axisU: [1, 0, 0],
                    axisV: [0, 0, 1],
                    halfU: obstacle.halfX,
                    halfV: obstacle.halfZ
                )
            }
        }
        // Ramps are intentionally excluded: they are no longer paintable, so
        // their tiles are blocked in the grid and never get a surface clip.
        return result
    }

    /// True when a ramp deck covers (x, z). Ramps are not paintable, so their
    /// footprint tiles are blocked in the paint grid using this test.
    func isOnRamp(atX x: Float, z: Float) -> Bool {
        for ramp in ramps where rampHeight(ramp, x: x, z: z) != nil { return true }
        return false
    }

    /// Highest surface at (x, z) — floor, platform tops, or ramps. Drives
    /// projectile landing / physics (NOT paintability; ramps stay unpainted).
    func paintSurfaceHeight(atX x: Float, z: Float) -> Float {
        var best: Float = 0
        forEachWalkableCandidate(atX: x, z: z) { obstacle in
            if abs(x - obstacle.center.x) <= obstacle.halfX,
               abs(z - obstacle.center.z) <= obstacle.halfZ {
                best = max(best, obstacle.topY)
            }
        }
        forEachRampCandidate(atX: x, z: z) { ramp in
            if let height = rampHeight(ramp, x: x, z: z) {
                best = max(best, height)
            }
        }
        return best
    }

    /// Smoothly climbs or falls toward the walkable height under the character.
    func settledHeight(from currentY: Float, atX x: Float, z: Float, dt: Float) -> Float {
        let target = walkableHeight(atX: x, z: z, currentY: currentY)
        let blend = 1 - exp(-dt * 14)
        let next = currentY + (target - currentY) * blend
        return abs(next - target) < 0.02 ? target : next
    }

}
