import Foundation
import Metal
import RealityKit
import UIKit
import simd

/// Displays a `PaintCanvas` as ONE flat quad lying over the arena floor.
///
/// This is the display half of the geometry→texture switch. Instead of ~110
/// merged chunk meshes that had to be regenerated as coverage grew, the whole
/// arena's ink is a single immutable quad sampling a single texture. Painting
/// no longer touches geometry at all: it writes pixels, and once per upload
/// tick the changed rows are pushed to the GPU.
///
/// Upload path — `LowLevelTexture` (iOS 18+), the API meant for textures the
/// app rewrites every frame: the texture is allocated once and its contents are
/// replaced through a command buffer, with RealityKit picking the new contents
/// up on the next render. No reallocation, no `CGImage`, nothing that blocks
/// the render loop.
///
/// It replaces the first attempt, which drove the texture from a
/// `TextureResource.DrawableQueue`. A drawable queue hands out a ring of
/// textures that must each be presented in order and only refreshes the
/// material once a drawable is actually presented — if a present is missed the
/// material keeps sampling a texture that was never filled, which shows up as
/// paint that simply never appears. `LowLevelTexture` has one texture and no
/// presentation handshake, so there is nothing to miss.
///
/// A CPU-writable staging texture still sits in front of it: `LowLevelTexture`
/// is written GPU-side, so the canvas bytes land in a `.shared` texture (dirty
/// rows only) that is then blitted across.
@MainActor
final class PaintCanvasSurface {
    /// A raised walkable top (crate, platform, container deck) that needs its
    /// own quad. The ground quad lies at floor level, so without these the ink
    /// painted on top of a structure is drawn UNDER it and never seen.
    nonisolated struct Deck: Sendable {
        let centerX: Float
        let centerZ: Float
        let halfX: Float
        let halfZ: Float
        let topY: Float
    }

    /// The ground quad, and parent of every raised deck quad.
    let entity: ModelEntity

    private let canvas: PaintCanvas
    /// Shared by the ground quad and every deck: one texture, one material,
    /// so a raised deck costs a draw call and nothing else.
    private let inkMaterial: UnlitMaterial
    private let arenaWidth: Float
    private let arenaDepth: Float
    private let commandQueue: MTLCommandQueue
    private let staging: MTLTexture
    private let lowLevelTexture: LowLevelTexture

    /// Uploads are paced rather than per-frame: a continuous jet dirties the
    /// canvas every frame, but 30 Hz of texture refresh is indistinguishable
    /// in play. Constant cost — it does not grow with coverage.
    private static let uploadInterval: Float = 1.0 / 30
    private var uploadAccum: Float = PaintCanvasSurface.uploadInterval
    /// Set when the staging texture holds bytes the GPU copy has not taken yet.
    /// The retry must not depend on new paint arriving, otherwise the last
    /// splat of a burst could stay invisible until the next shot.
    private var hasPendingBlit = false

    /// Diagnostics only — GPU uploads actually committed.
    private(set) var uploadCount = 0

    /// Sits just above the floor: high enough to beat z-fighting with the
    /// ground, low enough that the ink still reads as lying ON it. Matches the
    /// old splat height (`surface + 0.022`).
    private static let floorOffsetY: Float = 0.022

    /// Linear (non-sRGB) on purpose. The texture is written by the CPU and
    /// copied with a blit; an `_srgb` format cannot carry the `.shaderWrite`
    /// usage a `LowLevelTexture` needs, so the ink bytes are stored already
    /// linear-encoded (see `PaintGrid.inkBytes`) and land on screen as the
    /// exact team shade.
    static let pixelFormat: MTLPixelFormat = .rgba8Unorm

    /// Fails (returns nil) only if Metal or the texture is unavailable, in
    /// which case the caller keeps the mesh-based paint.
    init?(canvas: PaintCanvas, arenaWidth: Float, arenaDepth: Float) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            NSLog("[PaintCanvasSurface] no Metal device — keeping mesh paint")
            return nil
        }

        let stagingDescriptor = MTLTextureDescriptor()
        stagingDescriptor.textureType = .type2D
        stagingDescriptor.pixelFormat = PaintCanvasSurface.pixelFormat
        stagingDescriptor.width = canvas.width
        stagingDescriptor.height = canvas.height
        stagingDescriptor.mipmapLevelCount = 1
        stagingDescriptor.usage = [.shaderRead]
        stagingDescriptor.storageMode = .shared
        guard let staging = device.makeTexture(descriptor: stagingDescriptor) else {
            NSLog("[PaintCanvasSurface] staging texture allocation failed")
            return nil
        }

        var descriptor = LowLevelTexture.Descriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = PaintCanvasSurface.pixelFormat
        descriptor.width = canvas.width
        descriptor.height = canvas.height
        descriptor.depth = 1
        descriptor.mipmapLevelCount = 1
        descriptor.arrayLength = 1
        descriptor.textureUsage = [.shaderRead, .shaderWrite]

        let lowLevelTexture: LowLevelTexture
        let resource: TextureResource
        do {
            lowLevelTexture = try LowLevelTexture(descriptor: descriptor)
            resource = try TextureResource(from: lowLevelTexture)
        } catch {
            NSLog("[PaintCanvasSurface] texture creation failed: \(error.localizedDescription)")
            return nil
        }

        self.canvas = canvas
        self.commandQueue = commandQueue
        self.staging = staging
        self.lowLevelTexture = lowLevelTexture

        // Linear filtering on purpose: the slight softening is what makes the
        // 8 px/m stamps read as organic ink edges instead of stair-stepped
        // pixels. Clamped so the border texel never wraps across the arena.
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        var material = UnlitMaterial()
        material.color = .init(
            tint: .white,
            texture: .init(resource, sampler: .init(samplerDescriptor))
        )
        // Unpainted ground must show through. `opacityThreshold` is what
        // actually makes RealityKit honour the texture's alpha channel here:
        // it discards every texel below the cut, so bare floor stays bare
        // instead of the quad covering the whole arena in a flat sheet.
        material.opacityThreshold = 0.35
        material.faceCulling = .back

        self.inkMaterial = material
        self.arenaWidth = arenaWidth
        self.arenaDepth = arenaDepth

        entity = ModelEntity(
            mesh: PaintCanvasSurface.floorMesh(width: arenaWidth, depth: arenaDepth),
            materials: [material]
        )
        entity.position.y = PaintCanvasSurface.floorOffsetY
        entity.name = "paintCanvasFloor"
        if GameConfig.paintPerfDebug {
            NSLog("[PaintCanvasSurface] ready — \(canvas.width)×\(canvas.height) quad \(arenaWidth)×\(arenaDepth) m")
        }
    }

    /// Adds one quad per raised walkable top.
    ///
    /// The arena is not flat: crates, platforms and container decks are stood
    /// on and painted, but a single ground-level quad can only ever show ink
    /// at floor height — every splat landed on a structure was being drawn on
    /// the ground underneath it, hidden by the structure itself. That is why
    /// paint appeared on some parts of the arena and not others.
    ///
    /// Each deck samples the SAME canvas texture with UVs taken from its world
    /// footprint, so a texel painted at (x, z) shows at the height the player
    /// actually stands on, with no extra memory and no second canvas.
    func addDecks(_ decks: [Deck]) {
        for deck in decks {
            let mesh = PaintCanvasSurface.deckMesh(
                deck: deck,
                arenaWidth: arenaWidth,
                arenaDepth: arenaDepth
            )
            let quad = ModelEntity(mesh: mesh, materials: [inkMaterial])
            // Local Y only: the parent already sits at `floorOffsetY`, so the
            // deck lands the same hair above its own top surface.
            quad.position = SIMD3<Float>(deck.centerX, deck.topY, deck.centerZ)
            quad.name = "paintCanvasDeck"
            entity.addChild(quad)
        }
        if GameConfig.paintPerfDebug {
            NSLog("[PaintCanvasSurface] \(decks.count) raised paint decks")
        }
    }

    /// Quad covering one raised top, UV-mapped to its slice of the canvas so
    /// it lines up exactly with the ground quad's mapping.
    private static func deckMesh(deck: Deck, arenaWidth: Float, arenaDepth: Float) -> MeshResource {
        let u0 = (deck.centerX - deck.halfX + arenaWidth / 2) / arenaWidth
        let u1 = (deck.centerX + deck.halfX + arenaWidth / 2) / arenaWidth
        let v0 = (deck.centerZ - deck.halfZ + arenaDepth / 2) / arenaDepth
        let v1 = (deck.centerZ + deck.halfZ + arenaDepth / 2) / arenaDepth

        var descriptor = MeshDescriptor(name: "paintCanvasDeck")
        descriptor.positions = MeshBuffers.Positions([
            SIMD3<Float>(-deck.halfX, 0, -deck.halfZ),
            SIMD3<Float>(deck.halfX, 0, -deck.halfZ),
            SIMD3<Float>(deck.halfX, 0, deck.halfZ),
            SIMD3<Float>(-deck.halfX, 0, deck.halfZ)
        ])
        descriptor.normals = MeshBuffers.Normals([
            SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 1, 0)
        ])
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates([
            SIMD2<Float>(u0, v0), SIMD2<Float>(u1, v0),
            SIMD2<Float>(u1, v1), SIMD2<Float>(u0, v1)
        ])
        descriptor.primitives = .triangles([0, 2, 1, 0, 3, 2])
        return (try? MeshResource.generate(from: [descriptor]))
            ?? MeshResource.generatePlane(width: deck.halfX * 2, depth: deck.halfZ * 2)
    }

    /// One arena-sized quad in the XZ plane, wound counter-clockwise as seen
    /// from +Y so its normal points up and back-face culling keeps it visible.
    ///
    /// The UVs are written explicitly rather than relying on `generatePlane`:
    /// they must match `PaintCanvas`'s world→pixel mapping exactly, i.e.
    /// u = (x + w/2)/w and v = (z + d/2)/d, so v = 0 is the first row of the
    /// buffer. Any other convention would mirror the paint across the arena.
    private static func floorMesh(width: Float, depth: Float) -> MeshResource {
        let halfW = width / 2
        let halfD = depth / 2
        var descriptor = MeshDescriptor(name: "paintCanvasFloor")
        descriptor.positions = MeshBuffers.Positions([
            SIMD3<Float>(-halfW, 0, -halfD),
            SIMD3<Float>(halfW, 0, -halfD),
            SIMD3<Float>(halfW, 0, halfD),
            SIMD3<Float>(-halfW, 0, halfD)
        ])
        descriptor.normals = MeshBuffers.Normals([
            SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 1, 0)
        ])
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates([
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1), SIMD2<Float>(0, 1)
        ])
        descriptor.primitives = .triangles([0, 2, 1, 0, 3, 2])
        return (try? MeshResource.generate(from: [descriptor]))
            ?? MeshResource.generatePlane(width: width, depth: depth)
    }

    /// Pushes the canvas's changed rows to the GPU, at most every
    /// `uploadInterval`. Cheap and, crucially, constant: the cost tracks the
    /// area painted since the last upload, never the arena's total coverage.
    func uploadIfNeeded(dt: Float) {
        uploadAccum += dt
        guard uploadAccum >= PaintCanvasSurface.uploadInterval else { return }
        uploadAccum = 0

        let bytesPerRow = canvas.width * 4
        if let rect = canvas.dirtyRect {
            canvas.pixels.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                staging.replace(
                    region: MTLRegionMake2D(rect.x, rect.y, rect.width, rect.height),
                    mipmapLevel: 0,
                    withBytes: base.advanced(by: rect.y * bytesPerRow + rect.x * 4),
                    bytesPerRow: bytesPerRow
                )
            }
            canvas.clearDirtyRect()
            hasPendingBlit = true
        }
        guard hasPendingBlit else { return }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        // `replace(using:)` hands back the texture to write into and tells
        // RealityKit new contents are coming on this command buffer.
        let destination = lowLevelTexture.replace(using: commandBuffer)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: staging, to: destination)
        blit.endEncoding()
        commandBuffer.commit()
        hasPendingBlit = false
        uploadCount += 1
    }
}
