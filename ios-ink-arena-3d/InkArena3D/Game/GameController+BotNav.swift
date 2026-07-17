import Foundation
import RealityKit
import simd

/// Bot navigation: a static ground-level walkability grid built once per
/// match, A* pathfinding over it, and per-arena patrol points of interest.
/// Bots follow real routes around walls, water, ramps and platforms instead
/// of walking straight lines into geometry.
extension GameController {
    /// Ground-level walkability grid — one cell ≈ 1 m². Built from the same
    /// static geometry as the collision system (obstacles, water, ramps), so
    /// a "walkable" cell is guaranteed passable for a grounded bot.
    struct BotNavGrid {
        let cols: Int
        let rows: Int
        let cellSize: Float
        let originX: Float
        let originZ: Float
        let walkable: [Bool]

        func isWalkable(_ c: Int, _ r: Int) -> Bool {
            guard c >= 0, c < cols, r >= 0, r < rows else { return false }
            return walkable[r * cols + c]
        }

        func center(_ c: Int, _ r: Int) -> SIMD2<Float> {
            SIMD2<Float>(
                originX + (Float(c) + 0.5) * cellSize,
                originZ + (Float(r) + 0.5) * cellSize
            )
        }

        /// Cell containing the point, clamped into grid bounds, then spiraled
        /// outward until a walkable cell is found (a bot standing flush
        /// against a wall is technically inside a blocked cell).
        func nearestWalkableCell(toX x: Float, z: Float) -> (c: Int, r: Int)? {
            let cc = min(max(Int((x - originX) / cellSize), 0), cols - 1)
            let rr = min(max(Int((z - originZ) / cellSize), 0), rows - 1)
            if isWalkable(cc, rr) { return (cc, rr) }
            for radius in 1...6 {
                for dr in -radius...radius {
                    for dc in -radius...radius where max(abs(dr), abs(dc)) == radius {
                        if isWalkable(cc + dc, rr + dr) { return (cc + dc, rr + dr) }
                    }
                }
            }
            return nil
        }

        /// True when the straight segment stays on walkable cells the whole
        /// way — used to smooth A* staircases into natural diagonals.
        func lineOfSight(from a: SIMD2<Float>, to b: SIMD2<Float>) -> Bool {
            let dist = simd_distance(a, b)
            guard dist > 0.001 else { return true }
            let steps = max(1, Int(ceil(dist / (cellSize * 0.5))))
            for i in 0...steps {
                let p = a + (b - a) * (Float(i) / Float(steps))
                let c = Int((p.x - originX) / cellSize)
                let r = Int((p.y - originZ) / cellSize)
                guard isWalkable(c, r) else { return false }
            }
            return true
        }
    }

    /// Builds the walkability grid and the patrol points for the current
    /// arena. Must run AFTER `buildArena` so obstacles/water/ramps exist.
    func buildBotNavigation() {
        let cellSize: Float = 1.0
        let width = GameConfig.arenaWidth
        let depth = GameConfig.arenaDepth
        let cols = max(1, Int(ceil(width / cellSize)))
        let rows = max(1, Int(ceil(depth / cellSize)))
        let originX = -width / 2
        let originZ = -depth / 2

        var walkable = [Bool](repeating: false, count: cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let x = originX + (Float(c) + 0.5) * cellSize
                let z = originZ + (Float(r) + 0.5) * cellSize
                walkable[r * cols + c] = !isNavBlocked(x: x, z: z)
            }
        }
        botNav = BotNavGrid(
            cols: cols, rows: rows, cellSize: cellSize,
            originX: originX, originZ: originZ, walkable: walkable
        )
        buildPatrolPoints()
    }

    /// Ground-level blocker test for one nav cell center, inflated by the
    /// character radius so paths never hug geometry close enough to snag.
    private func isNavBlocked(x: Float, z: Float) -> Bool {
        // Outermost strip along the arena walls stays off-limits: the arena
        // clamp would fight any path that runs along the very edge.
        if abs(x) > GameConfig.arenaWidth / 2 - 1.0 { return true }
        if abs(z) > GameConfig.arenaDepth / 2 - 1.0 { return true }

        let inflate: Float = 0.75
        for obstacle in obstacles {
            // Dynamic shield walls are temporary — handled by live steering.
            if obstacle.passThroughTeam != nil { continue }
            if obstacle.topY <= GameConfig.stepUpHeight { continue }
            if obstacle.baseY >= 1.5 { continue }
            if abs(x - obstacle.center.x) < obstacle.halfX + inflate,
               abs(z - obstacle.center.z) < obstacle.halfZ + inflate {
                return true
            }
        }
        for water in waterZones {
            if abs(x - water.center.x) < water.halfX + 0.8,
               abs(z - water.center.y) < water.halfZ + 0.8 {
                return true
            }
        }
        // The raised half of a ramp deck cannot be stepped onto from the
        // ground — routing across it from the side pins bots against the
        // wedge, so only the low (walk-on) end stays walkable.
        for ramp in ramps {
            if let height = rampHeight(ramp, x: x, z: z), height > GameConfig.stepUpHeight {
                return true
            }
        }
        return false
    }

    /// Farthest-point sampling of open, high-clearance spots: the arena's
    /// natural "lanes and plazas". Bots roam between these instead of purely
    /// random coordinates, which reads as deliberate patrol routes.
    private func buildPatrolPoints() {
        guard let nav = botNav else { return }
        var candidates: [SIMD2<Float>] = []
        for r in 0..<nav.rows {
            for c in 0..<nav.cols where nav.isWalkable(c, r) {
                var clear = true
                outer: for dr in -1...1 {
                    for dc in -1...1 where !nav.isWalkable(c + dc, r + dr) {
                        clear = false
                        break outer
                    }
                }
                if clear { candidates.append(nav.center(c, r)) }
            }
        }
        guard !candidates.isEmpty else {
            botPatrolPoints = []
            return
        }

        // Seed at the most central open spot, then greedily add the candidate
        // farthest from everything already picked — spreads 8 points evenly.
        var seed = candidates[0]
        var bestCentral = Float.greatestFiniteMagnitude
        for candidate in candidates {
            let d = simd_length(candidate)
            if d < bestCentral {
                bestCentral = d
                seed = candidate
            }
        }
        var chosen: [SIMD2<Float>] = [seed]
        while chosen.count < 8 {
            var best: SIMD2<Float>?
            var bestScore: Float = -1
            for candidate in candidates {
                var minDist = Float.greatestFiniteMagnitude
                for picked in chosen {
                    minDist = min(minDist, simd_distance(candidate, picked))
                }
                if minDist > bestScore {
                    bestScore = minDist
                    best = candidate
                }
            }
            guard let next = best, bestScore > 4 else { break }
            chosen.append(next)
        }
        botPatrolPoints = chosen.map { SIMD3<Float>($0.x, 0, $0.y) }
    }

    /// Computes an A* route to `destination` and installs it on the bot.
    /// The bot's waypoint snaps to the path's reachable end so "arrived"
    /// checks always terminate.
    func assignPath(for bot: BotAgent, to destination: SIMD3<Float>) {
        let path = findBotPath(from: bot.container.position, to: destination)
        bot.path = path
        bot.pathIndex = 0
        bot.waypoint = path.last ?? destination
    }

    /// A* over the nav grid (8-connected, no corner cutting), smoothed with
    /// line-of-sight so bots cut natural diagonals instead of grid staircases.
    /// Falls back to a straight line when no grid or no route exists —
    /// live steering + stuck recovery still keep the bot moving.
    ///
    /// PERFORMANCE: the `gScore`/`cameFrom` scratch buffers are reused across
    /// calls (sized once, or resized only when the grid itself changes) and a
    /// per-call "generation" stamp marks which entries are valid for THIS
    /// search — an O(1) reset instead of re-zeroing up to `cols * rows` cells
    /// (up to ~3168 on the biggest map) on every waypoint assignment.
    func findBotPath(from start: SIMD3<Float>, to goal: SIMD3<Float>) -> [SIMD3<Float>] {
        guard let nav = botNav,
              let startCell = nav.nearestWalkableCell(toX: start.x, z: start.z),
              let goalCell = nav.nearestWalkableCell(toX: goal.x, z: goal.z) else {
            return [goal]
        }
        if startCell == goalCell { return [goal] }

        let cols = nav.cols
        let total = cols * nav.rows
        let startIndex = startCell.r * cols + startCell.c
        let goalIndex = goalCell.r * cols + goalCell.c

        func heuristic(_ index: Int) -> Float {
            let dc = Float(abs(index % cols - goalCell.c))
            let dr = Float(abs(index / cols - goalCell.r))
            return (dc + dr) + (1.41421356 - 2) * min(dc, dr)
        }

        let neighborOffsets: [(dc: Int, dr: Int, cost: Float)] = [
            (1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
            (1, 1, 1.41421356), (1, -1, 1.41421356),
            (-1, 1, 1.41421356), (-1, -1, 1.41421356),
        ]

        if pathfindGScore.count != total {
            pathfindGScore = [Float](repeating: .greatestFiniteMagnitude, count: total)
            pathfindCameFrom = [Int](repeating: -1, count: total)
            pathfindVisitGen = [Int32](repeating: 0, count: total)
            pathfindGeneration = 0
        }
        pathfindGeneration &+= 1
        let generation = pathfindGeneration

        func gScore(_ index: Int) -> Float {
            pathfindVisitGen[index] == generation ? pathfindGScore[index] : .greatestFiniteMagnitude
        }
        func setGScore(_ index: Int, _ value: Float) {
            pathfindGScore[index] = value
            pathfindVisitGen[index] = generation
        }

        setGScore(startIndex, 0)
        // CRITICAL: `pathfindCameFrom` persists across searches, so the start
        // cell may still hold a parent link from a PREVIOUS search. Without
        // resetting it, path reconstruction walks past the start into stale
        // chains that can loop forever (unbounded memory growth → crash).
        pathfindCameFrom[startIndex] = -1
        var open: [(f: Float, index: Int)] = [(heuristic(startIndex), startIndex)]
        var closed = Set<Int>()

        var found = false
        var iterations = 0
        while !open.isEmpty, iterations < 6000 {
            iterations += 1
            var bestI = 0
            for i in 1..<open.count where open[i].f < open[bestI].f { bestI = i }
            let current = open.remove(at: bestI)
            let index = current.index
            if index == goalIndex {
                found = true
                break
            }
            if closed.contains(index) { continue }
            closed.insert(index)

            let c = index % cols
            let r = index / cols
            for offset in neighborOffsets {
                let nc = c + offset.dc
                let nr = r + offset.dr
                guard nav.isWalkable(nc, nr) else { continue }
                // No corner cutting: a diagonal needs both orthogonals free.
                if offset.dc != 0, offset.dr != 0 {
                    guard nav.isWalkable(c + offset.dc, r), nav.isWalkable(c, r + offset.dr) else { continue }
                }
                let nIndex = nr * cols + nc
                if closed.contains(nIndex) { continue }
                let tentative = gScore(index) + offset.cost
                if tentative < gScore(nIndex) {
                    setGScore(nIndex, tentative)
                    pathfindCameFrom[nIndex] = index
                    open.append((tentative + heuristic(nIndex), nIndex))
                }
            }
        }
        guard found else { return [goal] }

        var cells: [Int] = []
        var cursor = goalIndex
        // Belt and braces: only follow parent links written by THIS search
        // (generation-stamped) and hard-bound the walk to the grid size, so a
        // corrupt chain can never loop indefinitely.
        while cursor != -1, cells.count <= total {
            cells.append(cursor)
            if cursor == startIndex { break }
            guard pathfindVisitGen[cursor] == generation else { return [goal] }
            cursor = pathfindCameFrom[cursor]
        }
        cells.reverse()

        var points: [SIMD2<Float>] = cells.map { nav.center($0 % cols, $0 / cols) }
        points[0] = SIMD2<Float>(start.x, start.z)
        let goal2 = SIMD2<Float>(goal.x, goal.z)
        if let last = points.last, nav.lineOfSight(from: last, to: goal2) {
            points.append(goal2)
        }
        let smoothed = smoothNavPath(points, nav: nav)
        return smoothed.map { SIMD3<Float>($0.x, 0, $0.y) }
    }

    /// Greedy string-pulling: from each anchor, jump straight to the farthest
    /// path point still in line of sight.
    private func smoothNavPath(_ points: [SIMD2<Float>], nav: BotNavGrid) -> [SIMD2<Float>] {
        guard points.count > 2 else { return points }
        var result: [SIMD2<Float>] = []
        var anchorIndex = 0
        while anchorIndex < points.count - 1 {
            var farthest = anchorIndex + 1
            var j = points.count - 1
            while j > anchorIndex + 1 {
                if nav.lineOfSight(from: points[anchorIndex], to: points[j]) {
                    farthest = j
                    break
                }
                j -= 1
            }
            result.append(points[farthest])
            anchorIndex = farthest
        }
        return result
    }
}
