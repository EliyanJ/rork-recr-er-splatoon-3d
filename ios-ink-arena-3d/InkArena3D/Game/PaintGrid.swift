import Combine
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
/// `nonisolated` (like every value type below) so the chunk merge can run off
/// the MainActor: these carry only scalars and simd data, no RealityKit object.
nonisolated private struct SplashGeometry: Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
}

/// Result of merging a chunk's tiles: raw vertex data, ready to be handed to
/// RealityKit back on the MainActor.
nonisolated private struct MergedGeometry: Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]

    var isEmpty: Bool { positions.isEmpty }

    /// Same geometry expressed as `MeshResource.Contents`, the form
    /// `replaceAsync(with:)` needs to refill an existing mesh in place.
    func contents() -> MeshResource.Contents {
        var part = MeshResource.Part(id: "inkPart", materialIndex: 0)
        part.positions = MeshBuffers.Positions(positions)
        part.normals = MeshBuffers.Normals(normals)
        part.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        var contents = MeshResource.Contents()
        contents.models = MeshModelCollection([
            MeshResource.Model(id: "inkModel", parts: [part])
        ])
        contents.instances = MeshInstanceCollection([
            MeshResource.Instance(id: "inkInstance", model: "inkModel")
        ])
        return contents
    }

    /// Descriptor form, used only for a chunk's very first mesh creation.
    func descriptor() -> MeshDescriptor {
        var descriptor = MeshDescriptor(name: "inkChunk")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return descriptor
    }
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
nonisolated struct SurfaceClip: Sendable {
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
nonisolated private struct TileInstance: Sendable {
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
    private var splashGeometries: [SplashGeometry]
    /// Whether the current `splashGeometries` use the low-point silhouette.
    /// Mutable so a runtime quality downgrade takes effect on new splats.
    private var simplifiedSplash: Bool
    // Flat, unlit color — matches the projectiles/VFX exactly (same
    // `UnlitMaterial` family, same raw team color) instead of the old
    // `SimpleMaterial`, which is scene-lit and got darkened/tinted by the
    // sun + fill light, so painted ground read as a muddy, mismatched shade
    // vs. the vivid ink flying through the air. Unlit is also cheaper: no
    // per-fragment lighting evaluation on the (often huge) merged paint mesh.
    private var orangeMaterial: UnlitMaterial
    private var purpleMaterial: UnlitMaterial

    // MARK: Texture-based paint
    /// Top-down RGBA image of the arena's ink. It costs the same per shot
    /// whatever the coverage, whereas the merged chunk meshes get heavier as
    /// the match fills up.
    let canvas: PaintCanvas
    /// The single textured quad displaying `canvas` over the floor. When it
    /// exists it IS the paint: no chunk slot is ever marked dirty, so no splat
    /// geometry is merged or generated (see `markDirty`). nil only if
    /// `GameConfig.texturePaint` is off or Metal setup failed, in which case
    /// the geometry path stays in charge.
    private var canvasSurface: PaintCanvasSurface?
    private let orangeInk: SIMD4<UInt8>
    private let purpleInk: SIMD4<UInt8>
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
    /// Slots whose merge is currently running off the MainActor. A slot already
    /// in flight is never merged twice concurrently: it is simply re-marked
    /// dirty so the next flush rebuilds it from the newer ownership state.
    private var rebuildingSlots: Set<Int> = []

    private var tileOrangeCount = 0
    private var tilePurpleCount = 0

    /// Ink held by each team.
    ///
    /// With texture paint on, these come STRAIGHT from the canvas texels the
    /// player sees. The 1 m tile counters below stay maintained for the
    /// geometry fallback, but they are no longer what the score reads: a tile
    /// was only claimed when its CENTRE fell inside the blot, so coverage
    /// jumped in 1 m steps that had little to do with the ink on screen.
    var orangeCount: Int {
        usesTexturePaint ? canvas.orangePixels : tileOrangeCount
    }
    var purpleCount: Int {
        usesTexturePaint ? canvas.purplePixels : tilePurpleCount
    }
    /// Live count of merged chunk/team meshes currently in the scene — this is
    /// the real paint draw-call count with batching enabled.
    private(set) var activePaintEntities = 0

    var totalCount: Int {
        usesTexturePaint ? canvas.paintablePixels : owners.count - blockedCount
    }
    /// Number of painted tiles = the paint draw-call count the OLD, unbatched
    /// design would have produced (one entity per tile). Used by the debug
    /// overlay to show the before/after gain live.
    var paintedTileCount: Int { tileOrangeCount + tilePurpleCount }

    /// The shared pool of splash silhouettes for the given detail level.
    private static func makeSplashGeometries(simplified: Bool) -> [SplashGeometry] {
        let baseRadius = GameConfig.tileSize * 0.82
        let pointCount = simplified ? 6 : 12
        return (0..<6).map {
            PaintGrid.generateSplashGeometry(
                seed: UInt64($0) &+ 17,
                baseRadius: baseRadius,
                height: 0.012,
                pointCount: pointCount
            )
        }
    }

    /// Switches the splash silhouette detail mid-match (runtime quality
    /// downgrade). Only affects splats merged from now on: already-built chunk
    /// meshes keep the shapes they were baked with, which is invisible in play
    /// and avoids re-merging the entire arena at the exact moment the device is
    /// already struggling.
    func setSimplifiedSplash(_ simplified: Bool) {
        guard simplified != simplifiedSplash else { return }
        simplifiedSplash = simplified
        splashGeometries = PaintGrid.makeSplashGeometries(simplified: simplified)
    }

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
        canvas = PaintCanvas(
            arenaWidth: GameConfig.arenaWidth,
            arenaDepth: GameConfig.arenaDepth
        )
        orangeInk = PaintGrid.inkBytes(Team.orange.uiColor)
        purpleInk = PaintGrid.inkBytes(Team.purple.uiColor)
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
        self.simplifiedSplash = simplifiedSplash
        splashGeometries = PaintGrid.makeSplashGeometries(simplified: simplifiedSplash)
        // Paint is a flat decal lying on the ground: only the upward-facing cap
        // exists (see `generateSplashGeometry`), wound counter-clockwise as seen
        // from above, so standard back-face culling is both correct AND cheaper.
        // The old `.none` culling was only needed because the splat used to be a
        // closed extruded solid whose down-facing cap and side skirt were never
        // visible yet still rasterized.
        orangeMaterial = UnlitMaterial(color: Team.orange.uiColor)
        purpleMaterial = UnlitMaterial(color: Team.purple.uiColor)
        orangeMaterial.faceCulling = .back
        purpleMaterial.faceCulling = .back
        if GameConfig.texturePaint {
            canvasSurface = PaintCanvasSurface(
                canvas: canvas,
                arenaWidth: GameConfig.arenaWidth,
                arenaDepth: GameConfig.arenaDepth
            )
            if let canvasSurface {
                root.addChild(canvasSurface.entity)
            } else {
                NSLog("[PaintGrid] texture paint unavailable — falling back to merged splat meshes")
            }
        }
    }

    /// Registers the arena's real paintable ground, once, at match setup.
    ///
    /// Two things are built from the SAME sorted deck list, which is what keeps
    /// them consistent:
    /// - the per-pixel `PaintSurfaceMap`, so every stamp knows exactly which
    ///   surface each texel belongs to (no ink bleeding between a crate top and
    ///   the floor, and no height-tolerance dead zones);
    /// - one quad per raised top, so ink standing on a crate is DRAWN on the
    ///   crate instead of on the ground hidden underneath it.
    ///
    /// Deck N owns registry id `firstDeck + N`; the list must be sorted by
    /// ascending height so the highest surface wins wherever two overlap.
    func configureSurfaces(
        decks: [PaintCanvasSurface.Deck],
        blockers: [PaintSurfaceMap.Box],
        rampBlockers: [PaintSurfaceMap.OrientedBox]
    ) {
        let map = PaintSurfaceMap(
            width: canvas.width,
            height: canvas.height,
            arenaWidth: GameConfig.arenaWidth,
            arenaDepth: GameConfig.arenaDepth,
            blockers: blockers,
            rampBlockers: rampBlockers,
            decks: decks.map {
                PaintSurfaceMap.Box(
                    centerX: $0.centerX,
                    centerZ: $0.centerZ,
                    halfX: $0.halfX,
                    halfZ: $0.halfZ
                )
            }
        )
        canvas.setSurfaceMap(map)
        canvasSurface?.addDecks(decks)
        if GameConfig.paintPerfDebug {
            NSLog("[PaintGrid] registre surfaces — sol \(map.groundPixels) px · surélevé \(map.deckPixels) px · bloqué \(map.blockedPixels) px")
        }
    }

    /// True while the textured quad is what the player actually sees.
    var usesTexturePaint: Bool { canvasSurface != nil }

    /// GPU uploads performed by the canvas surface — diagnostics overlay only.
    var canvasUploadCount: Int { canvasSurface?.uploadCount ?? 0 }

    /// Pushes any ink painted since the last tick to the GPU. Called once per
    /// frame from the simulation loop; no-op on the geometry path.
    func flushCanvas(dt: Float) {
        canvasSurface?.uploadIfNeeded(dt: dt)
    }

    /// RGBA bytes of a team color for direct writes into the canvas.
    ///
    /// Stored LINEAR, not sRGB: the canvas texture uses a linear pixel format
    /// (`PaintCanvasSurface.pixelFormat`), so the renderer takes the bytes as
    /// they are. Writing the raw sRGB components would show the ink washed
    /// out and too bright next to the projectiles using the same color.
    private static func inkBytes(_ color: UIColor) -> SIMD4<UInt8> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt8 {
            let linear = v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            return UInt8(max(0, min(255, (linear * 255).rounded())))
        }
        return SIMD4<UInt8>(byte(r), byte(g), byte(b), 255)
    }

    /// Builds a star/splash-shaped FLAT decal: a closed ring of points whose
    /// radius wobbles (and occasionally spikes outward, like an ink arm) around
    /// `baseRadius`, filled by a single triangle fan facing straight up.
    ///
    /// PERFORMANCE — this used to be a closed extruded solid (top cap + bottom
    /// cap + side skirt = 4× these triangles) rendered with face culling off.
    /// The splat sits 0.012 above the ground and is only ever seen from above,
    /// so the bottom cap and the side skirt were 100% invisible while still
    /// being rasterized on every merged chunk mesh — and the bottom cap, poking
    /// through the floor, was a z-fighting source. Keeping only the top cap cuts
    /// the triangle count, the vertex count, and the per-chunk merge cost by ~4×.
    /// The fan is wound counter-clockwise seen from +Y so the geometric normal is
    /// up and back-face culling keeps it visible.
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
        // Wound (center, next, current) so the cross product points +Y — the
        // opposite order would face the fan downward into the floor.
        for i in 0..<pointCount {
            let a = topStart + UInt32(i)
            let b = topStart + UInt32((i + 1) % pointCount)
            addTriangle(centerTopIndex, b, a)
        }

        return SplashGeometry(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    /// Which team's ink covers a world point.
    ///
    /// SOURCE OF TRUTH — with texture paint on this reads the very texel drawn
    /// under the player's feet, so the sponge dive boost, the walk boost and
    /// the bots all react to the ink that is actually visible. The old 1 m tile
    /// lookup is why the boost felt random: a tile 1 m wide was claimed (or
    /// not) from its centre alone, so you could stand on bright team ink with
    /// no boost, or on bare ground with one.
    func team(atX x: Float, z: Float) -> Team? {
        if usesTexturePaint {
            switch canvas.owner(atWorldX: x, z: z) {
            case 1: return .orange
            case 2: return .purple
            default: return nil
            }
        }
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

        // Visual-only, runs in parallel with the mesh path for now. Written on
        // every call (not only when tiles are gained) so re-inking already-held
        // ground still refreshes the image, exactly like the splats do.
        // Every pixel inside the 2D radius is written, whatever its height —
        // exactly what the mesh path does (each tile in radius takes a splat at
        // its own level). The earlier "same level as the impact only" filter
        // rejected the whole floor around any structure hit (a top graze put
        // the reference at the summit, so every ground pixel differed by
        // metres) and its tile-centre sampling cut hard straight lines into
        // flat ground — the dead zones. Water/ramp/out-of-arena stay excluded,
        // nothing else.
        let claimedPixels = canvas.stamp(
            atX: x,
            z: z,
            radius: radius,
            color: team == .orange ? orangeInk : purpleInk,
            team: team == .orange ? 1 : 2
        )

        var gained = 0
        // Texture paint owns the score: report the gain in tile-equivalents so
        // the per-fighter statistics keep the same scale as before, but derived
        // from the texels actually taken.
        if usesTexturePaint {
            return Int((Float(claimedPixels) / pixelsPerTile).rounded())
        }
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

    /// Canvas texels covering one 1 m gameplay tile — converts a texel gain
    /// back into the tile-count unit the stats and HUD were built around.
    private var pixelsPerTile: Float {
        let perMeterX = Float(canvas.width) / GameConfig.arenaWidth
        let perMeterZ = Float(canvas.height) / GameConfig.arenaDepth
        return max(1, perMeterX * GameConfig.tileSize * perMeterZ * GameConfig.tileSize)
    }

    private func teamSlot(_ team: Team) -> Int { team == .orange ? 0 : 1 }

    /// Marks one (chunk, team) slot dirty. New slots are appended to the FIFO
    /// queue so the per-flush budget drains them in order without starvation.
    private func markDirty(chunk: Int, team: Team) {
        // Texture paint owns the visuals: never queue a chunk merge. This is
        // what removes the rebuild cost entirely rather than just pacing it —
        // the geometry code below stays intact but is never reached.
        guard canvasSurface == nil else { return }
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
        if current == .orange { tileOrangeCount -= 1 }
        if current == .purple { tilePurpleCount -= 1 }
        owners[index] = team
        if team == .orange { tileOrangeCount += 1 } else { tilePurpleCount += 1 }

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
        var requeue: [Int] = []
        while processed < maxRebuilds, !dirtyQueue.isEmpty {
            let slot = dirtyQueue.removeFirst()
            // Skip stale queue entries (already flushed or de-duped).
            guard dirtySlots.remove(slot) != nil else { continue }
            // Already merging: re-mark dirty AFTER this loop so it isn't picked
            // again in the same flush, and don't spend budget on it.
            if rebuildingSlots.contains(slot) {
                requeue.append(slot)
                continue
            }
            startRebuild(slot: slot)
            processed += 1
        }
        for slot in requeue where dirtySlots.insert(slot).inserted {
            dirtyQueue.append(slot)
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

    /// Starts the rebuild of one (chunk, team) slot: snapshots the chunk's
    /// claimed tiles on the MainActor (cheap — value types only), merges the
    /// geometry OFF the MainActor, then applies the result back on it.
    ///
    /// PERFORMANCE — the merge loop (world-transforming and clipping every
    /// vertex of every painted tile) used to run inline on the MainActor, right
    /// in the middle of the frame, together with a synchronous
    /// `MeshResource.generate`. On a chunk holding a few hundred splats that is
    /// milliseconds of vertex math blocking the render loop, which is what made
    /// sustained firing stutter. Now only the snapshot and the RealityKit upload
    /// touch the MainActor.
    private func startRebuild(slot: Int) {
        let chunk = slot / 2
        let team: Team = slot % 2 == 0 ? .orange : .purple

        var tiles: [TileInstance] = []
        forEachCell(inChunk: chunk) { index in
            guard owners[index] == team, let instance = instances[index] else { return }
            tiles.append(instance)
        }
        // Nothing left of this team here — detach synchronously, no merge needed.
        guard !tiles.isEmpty else {
            detachChunk(slot: slot)
            return
        }

        let geometries = splashGeometries
        rebuildingSlots.insert(slot)
        Task { @MainActor [weak self] in
            let merged = await PaintGrid.mergeTiles(tiles, geometries: geometries)
            guard let self else { return }
            await self.applyMerged(merged, slot: slot, team: team)
            self.rebuildingSlots.remove(slot)
        }
    }

    /// Pure geometry merge — no RealityKit, no actor state, only value types,
    /// so it runs on the cooperative pool instead of the MainActor.
    nonisolated private static func mergeTiles(
        _ tiles: [TileInstance],
        geometries: [SplashGeometry]
    ) async -> MergedGeometry {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        // One splash silhouette's worth of vertices per tile, give or take —
        // reserving up front keeps the merge allocation-free.
        if let sample = geometries.first {
            positions.reserveCapacity(tiles.count * sample.positions.count)
            normals.reserveCapacity(tiles.count * sample.normals.count)
            uvs.reserveCapacity(tiles.count * sample.uvs.count)
            indices.reserveCapacity(tiles.count * sample.indices.count)
        }

        for instance in tiles {
            guard instance.meshPick >= 0, instance.meshPick < geometries.count else { continue }
            let geo = geometries[instance.meshPick]
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
        return MergedGeometry(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    /// Applies a finished merge to the chunk/team entity. An existing chunk has
    /// its MeshResource refilled in place via `replaceAsync`; `generate` is only
    /// ever called for a chunk's very first mesh.
    private func applyMerged(_ merged: MergedGeometry, slot: Int, team: Team) async {
        guard !merged.isEmpty else {
            detachChunk(slot: slot)
            return
        }
        if let entity = chunkEntities[slot], let mesh = entity.model?.mesh {
            // `replaceAsync` hands back a Combine publisher rather than an
            // awaitable value, so it is consumed as an async sequence.
            _ = try? await mesh.replaceAsync(with: merged.contents()).values.first { _ in true }
            return
        }
        guard let mesh = try? MeshResource.generate(from: [merged.descriptor()]) else { return }
        let entity = ModelEntity(mesh: mesh, materials: [material(for: team)])
        chunkEntities[slot] = entity
        root.addChild(entity)
        activePaintEntities += 1
    }

    /// Removes the chunk/team entity once no tile of that team remains there.
    private func detachChunk(slot: Int) {
        guard let entity = chunkEntities[slot] else { return }
        entity.removeFromParent()
        chunkEntities[slot] = nil
        activePaintEntities -= 1
    }
}
