import Foundation
import simd

/// Uniform 2D broadphase grid over the arena's XZ plane. Every obstacle / ramp
/// index is inserted into ALL cells its (margin-expanded) footprint overlaps,
/// so a point query only needs to test the single cell containing that point —
/// turning the old O(n) linear scans into near-O(1) lookups.
///
/// The stored values are indices into `GameController.obstacles` / `.ramps`.
/// Because indices shift on any removal, the grid is always rebuilt wholesale
/// (`rebuildSpatialIndex()`) after a mutation — never patched incrementally.
@MainActor
struct ObstacleGrid {
    let cellSize: Float
    let cols: Int
    let rows: Int
    /// World-space min corner of cell (0, 0).
    let originX: Float
    let originZ: Float
    /// One bucket of obstacle indices per cell (`row * cols + col`).
    private var cells: [[Int32]]
    /// Same layout, for ramp indices.
    private var rampCells: [[Int32]]

    init(cellSize: Float, minX: Float, minZ: Float, cols: Int, rows: Int) {
        self.cellSize = cellSize
        self.originX = minX
        self.originZ = minZ
        self.cols = cols
        self.rows = rows
        self.cells = Array(repeating: [], count: cols * rows)
        self.rampCells = Array(repeating: [], count: cols * rows)
    }

    /// Flat cell index containing a world point, or nil when outside the grid.
    private func cellIndex(x: Float, z: Float) -> Int? {
        let fx = (x - originX) / cellSize
        let fz = (z - originZ) / cellSize
        guard fx >= 0, fz >= 0 else { return nil }
        let cx = Int(fx)
        let cz = Int(fz)
        guard cx < cols, cz < rows else { return nil }
        return cz * cols + cx
    }

    /// Obstacle indices whose footprint may cover the point (single-cell
    /// lookup), or nil when the point lies outside the grid.
    func obstacleCandidates(x: Float, z: Float) -> [Int32]? {
        guard let idx = cellIndex(x: x, z: z) else { return nil }
        return cells[idx]
    }

    /// Ramp indices whose footprint may cover the point, or nil when outside.
    func rampCandidates(x: Float, z: Float) -> [Int32]? {
        guard let idx = cellIndex(x: x, z: z) else { return nil }
        return rampCells[idx]
    }

    /// Inserts `index` into every cell overlapping the axis-aligned box
    /// [minX, maxX] × [minZ, maxZ]. Over-inclusion is always safe: the caller
    /// still runs its own precise per-obstacle test, so extra candidates only
    /// fail that test — they never change behaviour.
    mutating func insert(
        index: Int32, minX: Float, maxX: Float, minZ: Float, maxZ: Float, isRamp: Bool
    ) {
        let c0 = max(0, Int((minX - originX) / cellSize))
        let c1 = min(cols - 1, Int((maxX - originX) / cellSize))
        let r0 = max(0, Int((minZ - originZ) / cellSize))
        let r1 = min(rows - 1, Int((maxZ - originZ) / cellSize))
        guard c0 <= c1, r0 <= r1 else { return }
        for r in r0...r1 {
            let base = r * cols
            for c in c0...c1 {
                if isRamp { rampCells[base + c].append(index) } else { cells[base + c].append(index) }
            }
        }
    }
}

extension GameController {
    /// Rebuilds the spatial broadphase from scratch. Called once at the end of
    /// setup and after every runtime mutation of `obstacles` (gadget shield
    /// wall place / expire). In TRAINING the arena mutates obstacle positions
    /// every frame, so the grid is disabled and the collision queries fall
    /// back to their legacy linear scans (the training arena is tiny).
    func rebuildSpatialIndex() {
        guard !isTraining else {
            obstacleGrid = nil
            return
        }
        let cellSize: Float = 4.0
        // Generous insertion margin: must exceed the largest query epsilon
        // (walkableHeight uses +0.2). Over-inclusion is free correctness-wise.
        let margin: Float = 0.5
        let halfW = GameConfig.arenaWidth / 2 + 2
        let halfD = GameConfig.arenaDepth / 2 + 2
        let cols = max(1, Int(ceil((halfW * 2) / cellSize)))
        let rows = max(1, Int(ceil((halfD * 2) / cellSize)))
        var grid = ObstacleGrid(cellSize: cellSize, minX: -halfW, minZ: -halfD, cols: cols, rows: rows)

        for i in obstacles.indices {
            let o = obstacles[i]
            grid.insert(
                index: Int32(i),
                minX: o.center.x - o.halfX - margin,
                maxX: o.center.x + o.halfX + margin,
                minZ: o.center.z - o.halfZ - margin,
                maxZ: o.center.z + o.halfZ + margin,
                isRamp: false
            )
        }
        for i in ramps.indices {
            let r = ramps[i]
            // Exact world AABB of the rotated ramp rectangle, plus margin.
            let ex = abs(r.axis.x) * r.halfLength + abs(r.axis.y) * r.halfWidth + margin
            let ez = abs(r.axis.y) * r.halfLength + abs(r.axis.x) * r.halfWidth + margin
            grid.insert(
                index: Int32(i),
                minX: r.center.x - ex,
                maxX: r.center.x + ex,
                minZ: r.center.y - ez,
                maxZ: r.center.y + ez,
                isRamp: true
            )
        }
        obstacleGrid = grid
    }
}
