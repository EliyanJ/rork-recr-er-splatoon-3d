import RealityKit
import UIKit
import simd

/// Deterministic, seedable RNG (SplitMix64) used to build the splash mesh
/// and color variants once at startup — no per-frame or per-tile allocation.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Raw geometry of one pre-generated ink-splash variant, kept in CPU memory
/// so painted tiles can be merged (transformed + appended) into a single
/// chunk mesh at runtime — no per-tile MeshResource is ever generated.
private struct SplashGeometry {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
}

/// A flat, bounded region of a declared surface (crate top, platform, …)
/// expressed as a plane (fixed `normal`) plus an in-plane rectangle
/// (`center` + orthonormal `axisU`/`axisV`, half-extents `halfU`/`halfV`).
///
/// The surface — NOT the impact — owns the paint's orientation and its edges.
/// `clamp(_:)` projects a world vertex onto the plane, clips it to the
/// rectangle, and restores its offset along the normal, so any part of a
/// splat that would spill past the real surface edge is cut flush to it.
/// Purely geometric (no allocation), run once per tile at bake/merge time.
struct SurfaceClip {
    let center: SIMD3<Float>
    let normal: SIMD3<Float>
    let axisU: SIMD3<Float>
    let axisV: SIMD3<Float>
    let halfU: Float
    let halfV: Float

    func clamp(_ world: SIMD3<Float>) -> SIMD3<Float> {
        let d = world - center
        let w = simd_dot(d, normal)
        let onPlane = d - w * normal
        let u = min(max(simd_dot(onPlane, axisU), -halfU), halfU)
        let v = min(max(simd_dot(onPlane, axisV), -halfV), halfV)
        return center + u * axisU + v * axisV + w * normal
    }
}

/// A painted cell's baked placement: the world transform (position, tilt to
/// the surface normal, random scale/spin), which splash variant it uses, and
/// the surface it sits on (for edge clipping). Computed once when the tile is
/// first claimed and never mutated after — only the tile's OWNER changes,
/// which just moves it between team buffers.
private struct TileInstance {
    let matrix: float4x4
    let rotation: simd_quatf
    let meshPick: Int
    /// Surface plane + bounds this tile is plated onto; nil for open floor.
    let clip: SurfaceClip?
}

/// Owns the paintable floor grid: tile ownership, batched tile rendering, and
/// live coverage counters. Tiles are claimed lazily on first paint.
///
/// Only flat, horizontal surfaces are paintable: the open floor and crate /
/// platform tops. Walls and ramps are NOT paintable (ramp footprints are
/// blocked so they never take paint and never count toward coverage).
///
/// Rendering note: ownership is tracked on a coarse grid, and each claimed
/// cell is drawn using one of a handful of pre-generated irregular "ink
/// splash" meshes (star-shaped outline, not a perfect disc) plus random
/// scale/rotation — so covered ground reads as organic, Splatoon-like ink.
///
/// PERFORMANCE — batched rendering (replaces the old "1 tile = 1 ModelEntity"
/// design that produced thousands of draw calls late-game): the arena is cut
/// into fixed chunks. Each chunk keeps at most one merged ModelEntity per team,
/// whose mesh is the union of every claimed cell of that team inside the chunk.
/// Painting marks touched (chunk, team) slots dirty; `flushPaintBatches()`
/// rebuilds only those dirty slots' merged meshes, up to a per-flush budget.
/// Result: paint draw calls drop
/// from ≈(number of painted tiles) to ≈(number of non-empty chunk/team meshes),
/// a ~30–60× reduction on a fully covered map.
///
/// Note on iOS 26's `MeshInstancesComponent`: it would also batch this, but it
/// is iOS 26.0+ only. This project deploys to iOS 18 and targets iPhone 12/13
/// (which commonly run iOS 18) as the minimum spec — exactly the devices this
/// optimization is for — so the component is unavailable where it matters most.
/// Merged `MeshDescriptor` chunks give the same draw-call win on iOS 18+.
@MainActor
final class PaintGrid {
    let root = Entity()
    let cols: Int
    let rows: Int

    private var owners: [Team?]
    /// Baked placement of every claimed cell, nil until first painted.
    private var instances: [TileInstance?]
    /// Tiles that can never be painted (water pools, ramp footprints) —
    /// excluded from the coverage denominator so 100% stays reachable.
    private var blockedTiles: [Bool]
    private var blockedCount = 0
    private let splashGeometries: [SplashGeometry]
    // Flat, unlit color — matches the projectiles/VFX exactly (same
    // `UnlitMaterial` family, same raw team color) instead of the old
    // `SimpleMaterial`, which is scene-lit and got darkened/tinted by the
    // sun + fill light, so painted ground read as a muddy, mismatched shade
    // vs. the vivid ink flying through the air. Unlit is also cheaper: no
    // per-fragment lighting evaluation on the (often huge) merged paint mesh.
    private var orangeMaterial: UnlitMaterial
    private var purpleMaterial: UnlitMaterial
    private let heightAt: (Float, Float) -> Float
    /// Declared surface (fixed plane + bounds) plating the tile at (x, z), or
    /// nil for open floor. Drives the splat's fixed orientation and edge clip.
    private let surfaceAt: (Float, Float) -> SurfaceClip?

    // MARK: Chunking
    /// Width/height of a chunk in tiles, driven by the active quality preset:
    /// bigger chunks mean fewer, larger rebuilds instead of many small ones.
    private let chunkSize: Int
    private let chunkCols: Int
    private let chunkRows: Int
    /// One merged ModelEntity per (chunk, team). Index = chunk * 2 + teamSlot.
    private var chunkEntities: [ModelEntity?]
    /// Slots (chunk × team, index = chunk * 2 + teamSlot) whose merged mesh
    /// needs rebuilding on the next flush. Tracking per-team means repainting
    /// only one team's tiles never rebuilds the other team's mesh in that
    /// chunk. `dirtySlots` is the membership set (dedup); `dirtyQueue` gives a
    /// FIFO order for the per-flush rebuild budget so no slot starves.
    private var dirtySlots: Set<Int> = []
    private var dirtyQueue: [Int] = []

    private(set) var orangeCount = 0
    private(set) var purpleCount = 0
    /// Live count of merged chunk/team meshes currently in the scene — this is
    /// the real paint draw-call count with batching enabled.
    private(set) var activePaintEntities = 0

    var totalCount: Int { owners.count - blockedCount }
    /// Number of painted tiles = the paint draw-call count the OLD, unbatched
    /// design would have produced (one entity per tile). Used by the debug
    /// overlay to show the before/after gain live.
    var paintedTileCount: Int { orangeCount + purpleCount }

    init(
        heightAt: @escaping (Float, Float) -> Float,
        surfaceAt: @escaping (Float, Float) -> SurfaceClip? = { _, _ in nil },
        isBlocked: ((Float, Float) -> Bool)? = nil,
        chunkSize: Int = 8,
        simplifiedSplash: Bool = false
    ) {
        self.heightAt = heightAt
        self.surfaceAt = surfaceAt
        self.chunkSize = max(4, chunkSize)
        cols = Int(GameConfig.arenaWidth / GameConfig.tileSize)
        rows = Int(GameConfig.arenaDepth / GameConfig.tileSize)
        owners = Array(repeating: nil, count: cols * rows)
        instances = Array(repeating: nil, count: cols * rows)
        blockedTiles = Array(repeating: false, count: cols * rows)
        chunkCols = (cols + chunkSize - 1) / chunkSize
        chunkRows = (rows + chunkSize - 1) / chunkSize
        chunkEntities = Array(repeating: nil, count: chunkCols * chunkRows * 2)
        if let isBlocked {
            for index in 0..<(cols * rows) {
                let cx = (Float(index % cols) + 0.5) * GameConfig.tileSize - GameConfig.arenaWidth / 2
                let cz = (Float(index / cols) + 0.5) * GameConfig.tileSize - GameConfig.arenaDepth / 2
                if isBlocked(cx, cz) {
                    blockedTiles[index] = true
                    blockedCount += 1
                }
            }
        }
        // A handful of irregular splash shapes, generated once and reused by
        // every tile — variety without any per-tile cost. Radius pushed past
        // the tile half-size so neighbouring splats always overlap into one
        // continuous coat of ink instead of a scatter of spaced-out discs.
        // The lightest presets use a plainer, lower-point silhouette — fewer
        // triangles baked into every merged chunk mesh.
        let baseRadius = GameConfig.tileSize * 0.82
        let pointCount = simplifiedSplash ? 6 : 12
        splashGeometries = (0..<6).map {
            PaintGrid.generateSplashGeometry(seed: UInt64($0) &+ 17, baseRadius: baseRadius, height: 0.012, pointCount: pointCount)
        }
        // Single-winding triangles (half the indices of the old both-winding
        // shape) rendered with face culling disabled, so the splat still
        // reads correctly from any angle without doubling the triangle count.
        orangeMaterial = UnlitMaterial(color: Team.orange.uiColor)
        purpleMaterial = UnlitMaterial(color: Team.purple.uiColor)
        orangeMaterial.faceCulling = .none
        purpleMaterial.faceCulling = .none
    }

    /// Builds a star/splash-shaped extruded geometry: a closed ring of points
    /// whose radius wobbles (and occasionally spikes outward, like an ink arm)
    /// around `baseRadius`, capped top/bottom and skinned on the sides.
    /// Triangles use a single, correct winding order — the paint materials
    /// disable face culling, so there's no need to double every triangle to
    /// cover both winding directions (half the vertex/index count for the
    /// same visual result).
    private static func generateSplashGeometry(seed: UInt64, baseRadius: Float, height: Float, pointCount: Int) -> SplashGeometry {
        var rng = SplitMix64(seed: seed)
        var topPoints: [SIMD3<Float>] = []
        for i in 0..<pointCount {
            let angle = Float(i) / Float(pointCount) * 2 * .pi
            var r = baseRadius * Float.random(in: 0.68...1.0, using: &rng)
            if Float.random(in: 0...1, using: &rng) < 0.4 {
                r *= Float.random(in: 1.08...1.4, using: &rng)
            }
            topPoints.append(SIMD3<Float>(cos(angle) * r, height, sin(angle) * r))
        }
        let bottomPoints = topPoints.map { SIMD3<Float>($0.x, 0, $0.z) }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        func addTriangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            indices.append(contentsOf: [a, b, c])
        }

        // Top cap (fan around center).
        let centerTopIndex = UInt32(positions.count)
        positions.append([0, height, 0]); normals.append([0, 1, 0]); uvs.append([0.5, 0.5])
        let topStart = UInt32(positions.count)
        for i in 0..<pointCount {
            positions.append(topPoints[i])
            normals.append([0, 1, 0])
            let angle = Float(i) / Float(pointCount) * 2 * .pi
            uvs.append([0.5 + cos(angle) * 0.5, 0.5 + sin(angle) * 0.5])
        }
        for i in 0..<pointCount {
            let a = topStart + UInt32(i)
            let b = topStart + UInt32((i + 1) % pointCount)
            addTriangle(centerTopIndex, a, b)
        }

        // Bottom cap.
        let centerBottomIndex = UInt32(positions.count)
        positions.append([0, 0, 0]); normals.append([0, -1, 0]); uvs.append([0.5, 0.5])
        let bottomStart = UInt32(positions.count)
        for i in 0..<pointCount {
            positions.append(bottomPoints[i])
            normals.append([0, -1, 0])
            let angle = Float(i) / Float(pointCount) * 2 * .pi
            uvs.append([0.5 + cos(angle) * 0.5, 0.5 + sin(angle) * 0.5])
        }
        for i in 0..<pointCount {
            let a = bottomStart + UInt32(i)
            let b = bottomStart + UInt32((i + 1) % pointCount)
            addTriangle(centerBottomIndex, b, a)
        }

        // Side skin connecting top ring to bottom ring.
        let sideStart = UInt32(positions.count)
        for i in 0..<pointCount {
            let angle = Float(i) / Float(pointCount) * 2 * .pi
            let normal = SIMD3<Float>(cos(angle), 0, sin(angle))
            positions.append(topPoints[i]); normals.append(normal); uvs.append([Float(i) / Float(pointCount), 1])
            positions.append(bottomPoints[i]); normals.append(normal); uvs.append([Float(i) / Float(pointCount), 0])
        }
        for i in 0..<pointCount {
            let next = (i + 1) % pointCount
            let topA = sideStart + UInt32(i * 2)
            let botA = sideStart + UInt32(i * 2 + 1)
            let topB = sideStart + UInt32(next * 2)
            let botB = sideStart + UInt32(next * 2 + 1)
            addTriangle(topA, botA, topB)
            addTriangle(botA, botB, topB)
        }

        return SplashGeometry(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    func team(atX x: Float, z: Float) -> Team? {
        let col = Int((x + GameConfig.arenaWidth / 2) / GameConfig.tileSize)
        let row = Int((z + GameConfig.arenaDepth / 2) / GameConfig.tileSize)
        guard col >= 0, col < cols, row >= 0, row < rows else { return nil }
        return owners[row * cols + col]
    }

    /// Paints every tile whose center is within `radius` of the splat point.
    /// Returns the number of tiles newly claimed for `team` — feeds the
    /// per-fighter paint statistics.
    @discardableResult
    func paint(atX x: Float, z: Float, radius: Float, team: Team) -> Int {
        let halfW = GameConfig.arenaWidth / 2
        let halfD = GameConfig.arenaDepth / 2
        let minCol = max(0, Int((x - radius + halfW) / GameConfig.tileSize))
        let maxCol = min(cols - 1, Int((x + radius + halfW) / GameConfig.tileSize))
        let minRow = max(0, Int((z - radius + halfD) / GameConfig.tileSize))
        let maxRow = min(rows - 1, Int((z + radius + halfD) / GameConfig.tileSize))
        guard minCol <= maxCol, minRow <= maxRow else { return 0 }

        var gained = 0
        for row in minRow...maxRow {
            for col in minCol...maxCol {
                let cx = (Float(col) + 0.5) * GameConfig.tileSize - halfW
                let cz = (Float(row) + 0.5) * GameConfig.tileSize - halfD
                let dx = cx - x
                let dz = cz - z
                if dx * dx + dz * dz <= radius * radius {
                    gained += setOwner(row * cols + col, team: team)
                }
            }
        }
        return gained
    }

    /// Flat, consistent material for `team` — same shade everywhere, and now
    /// the exact same raw color as the projectiles/VFX (see `UnlitMaterial`
    /// note above).
    private func material(for team: Team) -> UnlitMaterial {
        team == .orange ? orangeMaterial : purpleMaterial
    }

    private func teamSlot(_ team: Team) -> Int { team == .orange ? 0 : 1 }

    /// Marks one (chunk, team) slot dirty. New slots are appended to the FIFO
    /// queue so the per-flush budget drains them in order without starvation.
    private func markDirty(chunk: Int, team: Team) {
        let slot = chunk * 2 + teamSlot(team)
        if dirtySlots.insert(slot).inserted {
            dirtyQueue.append(slot)
        }
    }

    private func chunkIndex(forTile index: Int) -> Int {
        let col = index % cols
        let row = index / cols
        return (row / chunkSize) * chunkCols + (col / chunkSize)
    }

    /// Deterministic pseudo-random in [0, 1) derived from the tile index.
    private func hash(_ index: Int, _ salt: Int) -> Float {
        let mixed = (index &* 2654435761 &+ salt &* 40503) & 0xFFFF
        return Float(mixed) / Float(0x10000)
    }

    /// Returns 1 when the tile actually changed to `team`, 0 otherwise.
    /// Ownership + coverage counters update immediately; the visual is deferred
    /// to the next `flushPaintBatches()` so a whole frame's worth of newly
    /// painted tiles rebuilds each touched chunk mesh only once.
    @discardableResult
    private func setOwner(_ index: Int, team: Team) -> Int {
        guard !blockedTiles[index] else { return 0 }
        let current = owners[index]
        guard current != team else { return 0 }
        if current == .orange { orangeCount -= 1 }
        if current == .purple { purpleCount -= 1 }
        owners[index] = team
        if team == .orange { orangeCount += 1 } else { purpleCount += 1 }

        // Bake the tile's placement once — repainting a claimed tile keeps the
        // same instance and merely moves it between team buffers on rebuild,
        // so no per-tile entity is ever recreated (matches the old material-
        // only repaint path, now expressed as a chunk rebuild).
        if instances[index] == nil {
            instances[index] = makeInstance(index)
        }
        let chunk = chunkIndex(forTile: index)
        // The new owner's mesh always needs the tile added.
        markDirty(chunk: chunk, team: team)
        // A repaint must also rebuild the PREVIOUS owner's mesh so the tile is
        // removed from it. A virgin tile (current == nil) only touches the new
        // team's mesh.
        if let current { markDirty(chunk: chunk, team: current) }
        return 1
    }

    /// Computes the world transform for a freshly claimed tile. The tile is
    /// plated onto the DECLARED surface under it: it takes that surface's
    /// FIXED normal (a crate top is dead flat at 0°) — never a normal
    /// re-derived from neighbour heights, which used to tilt splats at edges.
    /// A random spin/scale adds organic variety; tiny height jitter avoids
    /// z-fighting. Overflow past the surface edge is handled later by the
    /// tile's `SurfaceClip` at merge time.
    private func makeInstance(_ index: Int) -> TileInstance {
        let col = index % cols
        let row = index / cols
        let cx = (Float(col) + 0.5) * GameConfig.tileSize - GameConfig.arenaWidth / 2
        let cz = (Float(row) + 0.5) * GameConfig.tileSize - GameConfig.arenaDepth / 2
        let surface = heightAt(cx, cz)
        let clip = surfaceAt(cx, cz)
        let normal = clip?.normal ?? SIMD3<Float>(0, 1, 0)

        let scale = SIMD3<Float>(
            0.9 + hash(index, 1) * 0.5,
            1,
            0.9 + hash(index, 2) * 0.5
        )
        let spin = simd_quatf(angle: hash(index, 3) * .pi * 2, axis: [0, 1, 0])
        let rotation = simd_quatf(from: [0, 1, 0], to: normal) * spin
        let jitter: Float = GameConfig.tileSize * 0.16
        let position = SIMD3<Float>(
            cx + (hash(index, 4) - 0.5) * jitter,
            surface + 0.022 + hash(index, 5) * 0.008,
            cz + (hash(index, 6) - 0.5) * jitter
        )
        let meshPick = min(splashGeometries.count - 1, Int(hash(index, 9) * Float(splashGeometries.count)))
        let matrix = Transform(scale: scale, rotation: rotation, translation: position).matrix
        return TileInstance(matrix: matrix, rotation: rotation, meshPick: meshPick, clip: clip)
    }

    /// Rebuilds up to `maxRebuilds` dirty (chunk, team) slots, oldest first.
    /// Any slot left over stays queued for the next flush, so a huge one-shot
    /// paint (e.g. a grenade covering ~9 chunks × 2 teams) spreads its mesh
    /// generation over a few flushes instead of spiking a single frame.
    /// Ownership + coverage are already applied instantly at paint time; only
    /// this visual merge is budgeted.
    func flushPaintBatches(maxRebuilds: Int) {
        var processed = 0
        while processed < maxRebuilds, !dirtyQueue.isEmpty {
            let slot = dirtyQueue.removeFirst()
            // Skip stale queue entries (already flushed or de-duped).
            guard dirtySlots.remove(slot) != nil else { continue }
            rebuildChunk(slot / 2, team: slot % 2 == 0 ? .orange : .purple)
            processed += 1
        }
    }

    /// Visits every cell index belonging to `chunk` in the floor grid.
    private func forEachCell(inChunk chunk: Int, _ body: (Int) -> Void) {
        let cCol = chunk % chunkCols
        let cRow = chunk / chunkCols
        let colStart = cCol * chunkSize
        let colEnd = min(cols, colStart + chunkSize)
        let rowStart = cRow * chunkSize
        let rowEnd = min(rows, rowStart + chunkSize)
        for row in rowStart..<rowEnd {
            let rowBase = row * cols
            for col in colStart..<colEnd { body(rowBase + col) }
        }
    }

    /// Merges every claimed cell of `team` inside `chunk` into a single mesh
    /// on that chunk/team's persistent ModelEntity (created lazily, reused for
    /// the life of the match, and detached when the chunk empties of that team).
    private func rebuildChunk(_ chunk: Int, team: Team) {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        forEachCell(inChunk: chunk) { index in
            guard owners[index] == team, let instance = instances[index] else { return }
            let geo = splashGeometries[instance.meshPick]
            let vertexOffset = UInt32(positions.count)
            let clip = instance.clip
            for p in geo.positions {
                let world4 = instance.matrix * SIMD4<Float>(p, 1)
                var world = SIMD3<Float>(world4.x, world4.y, world4.z)
                // Cut the splat flush to the real surface edge (crate top,
                // platform) before baking into the chunk mesh.
                if let clip { world = clip.clamp(world) }
                positions.append(world)
            }
            for n in geo.normals {
                normals.append(simd_normalize(instance.rotation.act(n)))
            }
            uvs.append(contentsOf: geo.uvs)
            for i in geo.indices {
                indices.append(i + vertexOffset)
            }
        }

        let slot = chunk * 2 + teamSlot(team)
        if positions.isEmpty {
            if let entity = chunkEntities[slot] {
                entity.removeFromParent()
                chunkEntities[slot] = nil
                activePaintEntities -= 1
            }
            return
        }

        var descriptor = MeshDescriptor(name: "inkChunk")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return }

        if let entity = chunkEntities[slot] {
            entity.model?.mesh = mesh
        } else {
            let entity = ModelEntity(mesh: mesh, materials: [material(for: team)])
            chunkEntities[slot] = entity
            root.addChild(entity)
            activePaintEntities += 1
        }
    }
}
