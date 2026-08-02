import Foundation
import simd

/// Per-pixel registry of the arena's paintable ground: for every texel of the
/// ink canvas, WHICH walkable surface it belongs to — the open floor, one
/// specific raised deck (crate top, container roof, platform), or nothing at
/// all (water, ramp, wall footprint).
///
/// WHY THIS EXISTS — the ink canvas is a single top-down image, so a texel at
/// (x, z) is ambiguous by nature: it can be the floor AND the roof of the crate
/// standing there. Earlier builds resolved that ambiguity per shot, either by
/// ignoring it (ink bled from the floor onto crate tops and vice versa) or by
/// comparing heights with a tolerance (which carved hard straight dead zones
/// into perfectly flat ground, because the reference height was sampled at a
/// tile centre metres away).
///
/// Both failures share one cause: the answer was recomputed, approximately, on
/// every impact. Here it is computed ONCE at match setup, exactly, from the
/// same rectangles the collision system uses — then every stamp is a single
/// array read: paint a pixel only if it belongs to the same surface as the
/// impact point. No tolerance, no heuristic, no dead zone.
///
/// Resolution is the canvas resolution (~14 px/m), against the 1 m tile grid
/// the old test used — edges land where the geometry actually is.
///
/// `nonisolated` and immutable after `init`: pure value data, no RealityKit
/// object, safe to read from anywhere.
nonisolated struct PaintSurfaceMap: Sendable {
    /// Axis-aligned world-space footprint (water pools, crate tops, walls).
    struct Box: Sendable {
        let centerX: Float
        let centerZ: Float
        let halfX: Float
        let halfZ: Float

        init(centerX: Float, centerZ: Float, halfX: Float, halfZ: Float) {
            self.centerX = centerX
            self.centerZ = centerZ
            self.halfX = halfX
            self.halfZ = halfZ
        }
    }

    /// Rotated world-space footprint — ramp decks, which are never paintable.
    struct OrientedBox: Sendable {
        let centerX: Float
        let centerZ: Float
        let axisX: Float
        let axisZ: Float
        let halfLength: Float
        let halfWidth: Float
    }

    /// Unpaintable: water, ramp, wall footprint, or outside the arena.
    static let blocked: UInt16 = 0
    /// The open arena floor.
    static let ground: UInt16 = 1
    /// First raised deck; deck N has id `firstDeck + N`.
    static let firstDeck: UInt16 = 2

    let width: Int
    let height: Int

    private let arenaWidth: Float
    private let arenaDepth: Float
    private let ids: [UInt16]

    /// Diagnostics: how the arena's texels were classified.
    let groundPixels: Int
    let deckPixels: Int
    let blockedPixels: Int

    /// Rasterizes the registry.
    ///
    /// Order matters and encodes the priority of the real world: blockers are
    /// carved out of the floor first, then decks are stamped on top — a
    /// platform built over water is paintable, the water under it is not. Decks
    /// must be passed sorted by ascending height so the highest one wins where
    /// two overlap, exactly like `paintSurfaceHeight` resolves it in 3D.
    ///
    /// Cost is proportional to the total area of the rectangles, not to the
    /// texture size: only touched pixels are visited (a few ms at setup).
    init(
        width: Int,
        height: Int,
        arenaWidth: Float,
        arenaDepth: Float,
        blockers: [Box],
        rampBlockers: [OrientedBox],
        decks: [Box]
    ) {
        self.width = width
        self.height = height
        self.arenaWidth = arenaWidth
        self.arenaDepth = arenaDepth

        var buffer = [UInt16](repeating: PaintSurfaceMap.ground, count: width * height)
        let pxPerMeterX = Float(width) / arenaWidth
        let pxPerMeterZ = Float(height) / arenaDepth
        let halfW = arenaWidth / 2
        let halfD = arenaDepth / 2

        /// Pixel bounds of a world-space AABB, clamped to the buffer.
        func pixelRange(
            minX: Float, maxX: Float, minZ: Float, maxZ: Float
        ) -> (Int, Int, Int, Int)? {
            let x0 = max(0, Int(((minX + halfW) * pxPerMeterX).rounded(.down)))
            let x1 = min(width - 1, Int(((maxX + halfW) * pxPerMeterX).rounded(.up)))
            let y0 = max(0, Int(((minZ + halfD) * pxPerMeterZ).rounded(.down)))
            let y1 = min(height - 1, Int(((maxZ + halfD) * pxPerMeterZ).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { return nil }
            return (x0, x1, y0, y1)
        }

        func fill(_ box: Box, with value: UInt16) {
            guard let (x0, x1, y0, y1) = pixelRange(
                minX: box.centerX - box.halfX, maxX: box.centerX + box.halfX,
                minZ: box.centerZ - box.halfZ, maxZ: box.centerZ + box.halfZ
            ) else { return }
            for y in y0...y1 {
                let row = y * width
                for x in x0...x1 { buffer[row + x] = value }
            }
        }

        for box in blockers { fill(box, with: PaintSurfaceMap.blocked) }

        // Ramps are rotated, so their bounding box is scanned and each pixel
        // tested against the real oriented rectangle.
        for ramp in rampBlockers {
            let reach = max(ramp.halfLength, ramp.halfWidth)
            guard let (x0, x1, y0, y1) = pixelRange(
                minX: ramp.centerX - reach, maxX: ramp.centerX + reach,
                minZ: ramp.centerZ - reach, maxZ: ramp.centerZ + reach
            ) else { continue }
            for y in y0...y1 {
                let worldZ = (Float(y) + 0.5) / pxPerMeterZ - halfD
                let row = y * width
                for x in x0...x1 {
                    let worldX = (Float(x) + 0.5) / pxPerMeterX - halfW
                    let dx = worldX - ramp.centerX
                    let dz = worldZ - ramp.centerZ
                    let along = dx * ramp.axisX + dz * ramp.axisZ
                    let across = -dx * ramp.axisZ + dz * ramp.axisX
                    if abs(along) <= ramp.halfLength, abs(across) <= ramp.halfWidth {
                        buffer[row + x] = PaintSurfaceMap.blocked
                    }
                }
            }
        }

        for (index, deck) in decks.enumerated() {
            fill(deck, with: PaintSurfaceMap.firstDeck &+ UInt16(index))
        }

        var ground = 0
        var deck = 0
        var blocked = 0
        for value in buffer {
            switch value {
            case PaintSurfaceMap.blocked: blocked += 1
            case PaintSurfaceMap.ground: ground += 1
            default: deck += 1
            }
        }
        groundPixels = ground
        deckPixels = deck
        blockedPixels = blocked
        ids = buffer
    }

    /// Surface owning a texel. Out-of-range reads answer `blocked`, so no
    /// caller can paint outside the arena.
    @inline(__always)
    func id(pixelX: Int, pixelY: Int) -> UInt16 {
        guard pixelX >= 0, pixelX < width, pixelY >= 0, pixelY < height else {
            return PaintSurfaceMap.blocked
        }
        return ids[pixelY * width + pixelX]
    }

    /// Surface owning a world point — used to decide which surface an impact
    /// belongs to before stamping.
    func id(atWorldX x: Float, z: Float) -> UInt16 {
        let px = Int((x + arenaWidth / 2) / arenaWidth * Float(width))
        let py = Int((z + arenaDepth / 2) / arenaDepth * Float(height))
        return id(pixelX: px, pixelY: py)
    }
}
