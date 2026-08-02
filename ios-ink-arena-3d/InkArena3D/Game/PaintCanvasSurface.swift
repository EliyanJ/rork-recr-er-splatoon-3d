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
    /// The quad to parent into the scene.
    let entity: ModelEntity

    private let canvas: PaintCanvas
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
    }
}
