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
/// tick the changed rectangle is pushed to the GPU.
///
/// Upload path — `TextureResource.DrawableQueue` (iOS 15+), the API designed
/// for continuously updated RealityKit textures: no texture is reallocated, no
/// `CGImage` is built, nothing blocks the render loop.
///
/// Why a staging texture instead of writing into the drawable directly: a
/// drawable queue hands out a small ring of textures, so writing only the dirty
/// rectangle into whichever drawable comes up would leave the other drawables
/// holding stale ink. The full canvas lives in one CPU-writable staging texture
/// (only its dirty rows are rewritten), which is then blitted whole into the
/// drawable — so every drawable in the ring is always complete.
@MainActor
final class PaintCanvasSurface {
    /// The quad to parent into the scene.
    let entity: ModelEntity

    private let canvas: PaintCanvas
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let staging: MTLTexture
    private let drawables: TextureResource.DrawableQueue

    /// Uploads are paced rather than per-frame: a continuous jet dirties the
    /// canvas every frame, but 30 Hz of texture refresh is indistinguishable
    /// in play. Constant cost — it does not grow with coverage.
    private static let uploadInterval: Float = 1.0 / 30
    private var uploadAccum: Float = PaintCanvasSurface.uploadInterval
    /// Set when a blit could not be encoded (no drawable available). The retry
    /// must not depend on new paint arriving, otherwise the GPU copy of a
    /// finished splat could stay stale until the next shot.
    private var hasPendingBlit = false

    /// Sits just above the floor: high enough to beat z-fighting with the
    /// ground, low enough that the ink still reads as lying ON it. Matches the
    /// old splat height (`surface + 0.022`).
    private static let floorOffsetY: Float = 0.022

    /// Fails (returns nil) only if Metal or the texture resource is
    /// unavailable, in which case the caller keeps the mesh-based paint.
    init?(canvas: PaintCanvas, arenaWidth: Float, arenaDepth: Float) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else { return nil }

        // sRGB so the bytes written from `UIColor` components land on screen as
        // the same shade the projectiles and VFX use (a linear format would
        // render the ink washed out and too bright).
        let pixelFormat = MTLPixelFormat.rgba8Unorm_srgb
        let bytesPerRow = canvas.width * 4

        let stagingDescriptor = MTLTextureDescriptor()
        stagingDescriptor.textureType = .type2D
        stagingDescriptor.pixelFormat = pixelFormat
        stagingDescriptor.width = canvas.width
        stagingDescriptor.height = canvas.height
        stagingDescriptor.mipmapLevelCount = 1
        stagingDescriptor.usage = [.shaderRead]
        stagingDescriptor.storageMode = .shared
        guard let staging = device.makeTexture(descriptor: stagingDescriptor) else { return nil }

        let texture: TextureResource
        do {
            texture = try TextureResource(
                dimensions: .dimensions(width: canvas.width, height: canvas.height),
                format: .raw(pixelFormat: pixelFormat),
                contents: .init(
                    mipmapLevels: [.mip(data: Data(canvas.pixels), bytesPerRow: bytesPerRow)]
                )
            )
        } catch {
            NSLog("[PaintCanvasSurface] texture creation failed: \(error.localizedDescription)")
            return nil
        }

        let queueDescriptor = TextureResource.DrawableQueue.Descriptor(
            pixelFormat: pixelFormat,
            width: canvas.width,
            height: canvas.height,
            usage: [.renderTarget, .shaderRead, .shaderWrite],
            mipmapsMode: .none
        )
        guard let drawables = try? TextureResource.DrawableQueue(queueDescriptor) else {
            NSLog("[PaintCanvasSurface] drawable queue creation failed")
            return nil
        }
        // Never block the frame waiting for a free drawable — a skipped upload
        // is retried on the next tick.
        drawables.allowsNextDrawableTimeout = true
        texture.replace(withDrawables: drawables)

        self.canvas = canvas
        self.device = device
        self.commandQueue = commandQueue
        self.staging = staging
        self.drawables = drawables

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
            texture: .init(texture, sampler: .init(samplerDescriptor))
        )
        // Unpainted ground must show through: alpha 0 texels are the bare floor.
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.faceCulling = .back

        entity = ModelEntity(
            mesh: PaintCanvasSurface.floorMesh(width: arenaWidth, depth: arenaDepth),
            materials: [material]
        )
        entity.position.y = PaintCanvasSurface.floorOffsetY
        entity.name = "paintCanvasFloor"
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

        guard let drawable = try? drawables.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            // No drawable free this tick — keep the flag so the staging content
            // still reaches the GPU on a later tick.
            return
        }
        blit.copy(from: staging, to: drawable.texture)
        blit.endEncoding()
        commandBuffer.commit()
        // Presented on the next scene update instead of waiting on the GPU, so
        // the upload never stalls the frame.
        drawable.presentOnSceneUpdate()
        hasPendingBlit = false
    }
}
