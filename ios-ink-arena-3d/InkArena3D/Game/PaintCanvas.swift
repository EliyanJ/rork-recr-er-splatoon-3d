import Foundation
import UIKit
import simd

/// Deterministic, seedable RNG (SplitMix64) — used once at startup to carve
/// the ink stamp masks, so every device/session gets the same silhouettes.
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

/// CPU-side, top-down RGBA8 image of the whole arena's ink coverage.
///
/// WHY THIS EXISTS — the geometry-based paint (`PaintGrid`'s merged chunk
/// meshes) costs MORE as the match goes on: every new splat enlarges the chunk
/// mesh that has to be rebuilt, so a match starts smooth and ends stuttering.
/// That is structural, no quality preset fixes it. Paint is not a 3D object —
/// it is an image lying on the floor. Writing a splat into a bitmap costs the
/// same at 2% coverage as at 98%, and no geometry is ever rebuilt.
///
/// This type owns ONLY the pixels: world→pixel mapping, the pre-baked stamp
/// masks, and the dirty rectangle bookkeeping. It creates no entity, holds no
/// RealityKit object, and renders nothing — the display side is a later step.
///
/// Threading: MainActor-bound on purpose. Every writer (`PaintGrid.paint`) is
/// already on the MainActor and the writes are cheap (a few thousand bytes);
/// keeping it single-threaded removes any need for locking on the buffer.
@MainActor
final class PaintCanvas {
    /// Sub-rectangle of the buffer touched since the last GPU upload.
    struct DirtyRect: Equatable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    /// Texel density. 8 px per game meter puts a 1 m tile on an 8×8 block —
    /// enough for organic edges once the texture is sampled with linear
    /// filtering, and it keeps even the biggest arena inside one 1024² page.
    static let pixelsPerMeter: Float = 8
    /// Hard memory ceiling: 1024² RGBA8 = 4 MB, whatever the arena size.
    static let maxDimension = 1024
    /// Side of a stamp mask in mask-space pixels.
    private static let stampSize = 48
    /// Number of pre-baked silhouettes cycled through for variety.
    private static let stampVariants = 6
    /// Mask opacity at or above which the pixel is written fully opaque.
    /// Below it, the pixel is treated as a soft fringe (see `stamp`).
    private static let coverThreshold: UInt8 = 110

    let width: Int
    let height: Int

    /// RGBA8, row-major, top row first. Alpha 0 = bare ground.
    private(set) var pixels: [UInt8]

    /// Arena footprint captured once — `GameConfig.arenaWidth/Depth` are
    /// computed from the selected map, and the mapping must not shift if
    /// anything mutates them mid-match.
    private let arenaWidth: Float
    private let arenaDepth: Float

    private let stamps: [[UInt8]]

    private var dirtyMinX = Int.max
    private var dirtyMinY = Int.max
    private var dirtyMaxX = Int.min
    private var dirtyMaxY = Int.min

    /// Per-pixel registry of which walkable surface owns each texel. Installed
    /// once at match setup; until then every pixel counts as open floor.
    private(set) var surfaceMap: PaintSurfaceMap?

    /// Diagnostics only — how much work the canvas has actually done.
    private(set) var stampCount = 0
    private(set) var writtenPixelCount = 0
    /// Pixel centre of the most recent blot, for checking the world→texture
    /// mapping against where the shot actually landed.
    private(set) var lastStampX = -1
    private(set) var lastStampY = -1

    /// The region touched since the last `clearDirtyRect()`, or nil if the
    /// buffer is unchanged. The GPU upload step will consume exactly this.
    var dirtyRect: DirtyRect? {
        guard dirtyMinX <= dirtyMaxX, dirtyMinY <= dirtyMaxY else { return nil }
        return DirtyRect(
            x: dirtyMinX,
            y: dirtyMinY,
            width: dirtyMaxX - dirtyMinX + 1,
            height: dirtyMaxY - dirtyMinY + 1
        )
    }

    init(arenaWidth: Float, arenaDepth: Float) {
        self.arenaWidth = arenaWidth
        self.arenaDepth = arenaDepth
        width = PaintCanvas.textureExtent(forMeters: arenaWidth)
        height = PaintCanvas.textureExtent(forMeters: arenaDepth)
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        stamps = (0..<PaintCanvas.stampVariants).map {
            PaintCanvas.makeStampMask(
                seed: UInt64($0) &+ 17,
                size: PaintCanvas.stampSize,
                pointCount: 12
            )
        }
        if GameConfig.paintPerfDebug {
            NSLog("[PaintCanvas] \(width)×\(height) px for \(arenaWidth)×\(arenaDepth) m — \(pixels.count / 1024) KB")
        }
    }

    /// Installs the surface registry. Called once, before the first stamp.
    func setSurfaceMap(_ map: PaintSurfaceMap) {
        surfaceMap = map
    }

    /// Which surface owns the texel under a world point.
    func surfaceID(atWorldX x: Float, z: Float) -> UInt16 {
        surfaceMap?.id(atWorldX: x, z: z) ?? PaintSurfaceMap.ground
    }

    /// Power-of-two texture side covering `meters` at the target density,
    /// capped so memory stays bounded on the smallest supported devices.
    private static func textureExtent(forMeters meters: Float) -> Int {
        let wanted = max(1, Int((meters * pixelsPerMeter).rounded(.up)))
        var extent = 64
        while extent < wanted, extent < maxDimension { extent <<= 1 }
        return min(extent, maxDimension)
    }

    // MARK: - Stamp masks

    /// Bakes one irregular ink-blot opacity mask.
    ///
    /// Same silhouette rule as the mesh splats it replaces (`SplitMix64`, a
    /// radius wobbling in 0.68…1.0 with occasional outward spikes) — but
    /// rasterized into opacity instead of turned into vertices. The angular
    /// radius profile is smoothstep-interpolated between lobes so the outline
    /// reads as organic rather than polygonal, and the inner edge fades out
    /// over a few pixels so blots blend instead of hard-clipping.
    private static func makeStampMask(seed: UInt64, size: Int, pointCount: Int) -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        var profile = [Float](repeating: 0, count: pointCount)
        var maxRadius: Float = 0.0001
        for i in 0..<pointCount {
            var r = Float.random(in: 0.68...1.0, using: &rng)
            if Float.random(in: 0...1, using: &rng) < 0.4 {
                r *= Float.random(in: 1.08...1.4, using: &rng)
            }
            profile[i] = r
            maxRadius = max(maxRadius, r)
        }
        // Normalize so the widest lobe just touches the mask border.
        for i in 0..<pointCount { profile[i] = profile[i] / maxRadius * 0.98 }

        var mask = [UInt8](repeating: 0, count: size * size)
        let half = Float(size) / 2
        let softEdge: Float = 0.12
        for py in 0..<size {
            let dy = (Float(py) + 0.5 - half) / half
            for px in 0..<size {
                let dx = (Float(px) + 0.5 - half) / half
                let r = sqrt(dx * dx + dy * dy)
                guard r <= 1 else { continue }
                var turn = atan2(dy, dx) / (2 * .pi)
                if turn < 0 { turn += 1 }
                let t = min(turn * Float(pointCount), Float(pointCount) - 0.0001)
                let i0 = Int(t)
                let i1 = (i0 + 1) % pointCount
                var f = t - Float(i0)
                f = f * f * (3 - 2 * f)
                let edge = profile[i0] * (1 - f) + profile[i1] * f
                guard r < edge else { continue }
                let fade = min(1, (edge - r) / softEdge)
                mask[py * size + px] = UInt8(max(0, min(255, fade * 255)))
            }
        }
        return mask
    }

    // MARK: - Writing

    /// World X/Z → pixel column/row (may fall outside the buffer).
    func pixelX(forWorldX x: Float) -> Float {
        (x + arenaWidth / 2) / arenaWidth * Float(width)
    }

    func pixelY(forWorldZ z: Float) -> Float {
        (z + arenaDepth / 2) / arenaDepth * Float(height)
    }

    /// Writes one ink blot centred on (`x`, `z`).
    ///
    /// - Parameters:
    ///   - radius: the gameplay paint radius. The blot is drawn slightly wider
    ///     so neighbouring hits merge into one continuous coat, matching how
    ///     the mesh splats overhang their tile.
    ///   - color: straight RGBA bytes of the owning team.
    ///   - surfaceID: the surface the impact belongs to (see
    ///     `surfaceID(atWorldX:z:)`). ONLY texels registered to that same
    ///     surface are written, so ink laid on the floor stops flush at a
    ///     crate's edge and ink laid on a crate top never leaks onto the floor
    ///     around it. An exact identity test — no height tolerance, therefore
    ///     no dead zones on flat ground.
    ///
    /// Cost is proportional to the blot's area in pixels — a few thousand byte
    /// writes — and does NOT grow with match progress.
    func stamp(
        atX x: Float,
        z: Float,
        radius: Float,
        color: SIMD4<UInt8>,
        surfaceID: UInt16
    ) {
        // Overhang matches the mesh splats' radius (tileSize * 0.82) so the
        // texture covers the same visual footprint as the geometry it mirrors.
        let worldRadius = radius + GameConfig.tileSize * 0.75
        let centerX = pixelX(forWorldX: x)
        let centerY = pixelY(forWorldZ: z)
        let radiusX = worldRadius / arenaWidth * Float(width)
        let radiusY = worldRadius / arenaDepth * Float(height)
        guard radiusX > 0.5, radiusY > 0.5 else { return }

        let minPX = max(0, Int((centerX - radiusX).rounded(.down)))
        let maxPX = min(width - 1, Int((centerX + radiusX).rounded(.up)))
        let minPY = max(0, Int((centerY - radiusY).rounded(.down)))
        let maxPY = min(height - 1, Int((centerY + radiusY).rounded(.up)))
        guard minPX <= maxPX, minPY <= maxPY else { return }

        // Deterministic variant + quarter-turn from the world position, so the
        // same impact point always produces the same blot (replays, network
        // peers) while nearby hits still look different.
        let quantX = Int(x * 4)
        let quantZ = Int(z * 4)
        let mixed = (quantX &* 73_856_093) ^ (quantZ &* 19_349_663)
        let stamp = stamps[abs(mixed) % stamps.count]
        let orientation = abs(mixed >> 8) % 4
        let stampSize = PaintCanvas.stampSize
        let threshold = PaintCanvas.coverThreshold

        var touchedMinX = Int.max
        var touchedMinY = Int.max
        var touchedMaxX = Int.min
        var touchedMaxY = Int.min
        var written = 0

        for py in minPY...maxPY {
            let v = (Float(py) + 0.5 - centerY) / radiusY
            guard v > -1, v < 1 else { continue }
            let rowBase = py * width * 4
            for px in minPX...maxPX {
                let u = (Float(px) + 0.5 - centerX) / radiusX
                guard u * u + v * v <= 1 else { continue }

                // Quarter-turn the sampling coords instead of the mask itself.
                var su = u
                var sv = v
                switch orientation {
                case 1: su = v; sv = -u
                case 2: su = -u; sv = -v
                case 3: su = -v; sv = u
                default: break
                }
                let mx = min(stampSize - 1, max(0, Int((su * 0.5 + 0.5) * Float(stampSize))))
                let my = min(stampSize - 1, max(0, Int((sv * 0.5 + 0.5) * Float(stampSize))))
                let opacity = stamp[my * stampSize + mx]
                guard opacity > 0 else { continue }

                // One array read replaces the old per-pixel world-space blocked
                // test (two divisions plus a closure call): the registry
                // already knows the answer, exactly.
                if let surfaceMap, surfaceMap.id(pixelX: px, pixelY: py) != surfaceID { continue }

                let index = rowBase + px * 4
                if opacity >= threshold {
                    pixels[index] = color.x
                    pixels[index + 1] = color.y
                    pixels[index + 2] = color.z
                    pixels[index + 3] = 255
                } else if opacity > pixels[index + 3] {
                    // Soft fringe: only deepens a pixel, never erodes ink that
                    // an earlier blot already laid down solid.
                    pixels[index] = color.x
                    pixels[index + 1] = color.y
                    pixels[index + 2] = color.z
                    pixels[index + 3] = opacity
                } else {
                    continue
                }
                written += 1
                if px < touchedMinX { touchedMinX = px }
                if px > touchedMaxX { touchedMaxX = px }
                if py < touchedMinY { touchedMinY = py }
                if py > touchedMaxY { touchedMaxY = py }
            }
        }

        guard written > 0 else { return }
        lastStampX = Int(centerX)
        lastStampY = Int(centerY)
        stampCount += 1
        writtenPixelCount += written
        markDirty(minX: touchedMinX, minY: touchedMinY, maxX: touchedMaxX, maxY: touchedMaxY)
    }

    private func markDirty(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        if minX < dirtyMinX { dirtyMinX = minX }
        if minY < dirtyMinY { dirtyMinY = minY }
        if maxX > dirtyMaxX { dirtyMaxX = maxX }
        if maxY > dirtyMaxY { dirtyMaxY = maxY }
    }

    /// Called by the upload step once the dirty region has been pushed to the
    /// GPU. Separate from `stamp` so a frame's worth of blots coalesces into a
    /// single upload.
    func clearDirtyRect() {
        dirtyMinX = Int.max
        dirtyMinY = Int.max
        dirtyMaxX = Int.min
        dirtyMaxY = Int.min
    }

    /// Wipes all ink and marks the whole buffer dirty. No allocation, no
    /// entity teardown — the between-matches reset is a memset.
    func reset() {
        for i in pixels.indices { pixels[i] = 0 }
        stampCount = 0
        writtenPixelCount = 0
        markDirty(minX: 0, minY: 0, maxX: width - 1, maxY: height - 1)
    }
}
