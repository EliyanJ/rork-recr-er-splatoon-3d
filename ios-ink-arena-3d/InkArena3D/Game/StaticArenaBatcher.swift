import RealityKit
import UIKit
import simd

/// Fuses the arena's many static, opaque primitives (platforms, ramps, walls,
/// obstacles, neon trims, pads…) into a handful of merged `ModelEntity`s — one
/// per material "bucket" — instead of one entity per primitive. RealityKit
/// cannot batch distinct meshes/materials on iOS 18, so ~200-300 static draw
/// calls collapse to ≈20 without `MeshInstancesComponent` (iOS 26+).
///
/// Same merge technique as `PaintGrid.rebuildChunk`: accumulate transformed
/// vertices/normals/uvs/indices in WORLD space per bucket, then emit one
/// `MeshDescriptor` → `MeshResource` per bucket at `build(into:)`.
///
/// Only OPAQUE geometry is fused. Transparent surfaces (water, holo screens,
/// glowing tree foliage, window strips) and anything animated/mutated at
/// runtime stay individual entities to avoid render-order artifacts.
///
/// Tiling note: individual entities tiled textures via
/// `material.textureCoordinateTransform.scale`. A merged bucket shares ONE
/// material, so tiling is baked directly into each face's UVs instead, and the
/// shared material keeps an identity texture transform — reproducing the exact
/// same texel/meter ratio the per-entity `scale:` produced.
@MainActor
final class StaticArenaBatcher {
    /// Exact material recipe for a primitive. `pbr`'s `fallback` participates
    /// only in the missing-texture path; buckets are keyed WITHOUT it so all
    /// same-texture/tint/roughness primitives merge into one entity when the
    /// texture loads (the real-device case this optimization targets).
    enum MaterialSpec {
        case pbr(texture: String, tint: UIColor, roughness: Float, fallback: UIColor)
        case unlit(UIColor)
        case simple(color: UIColor, roughness: Float, metallic: Bool)

        /// Builds the RealityKit material. `tilingScale` is `[1, 1]` for merged
        /// buckets (tiling is baked into the mesh UVs) and the requested scale
        /// for the standalone (non-batched) fallback path.
        func makeMaterial(mats: ArenaMaterials?, tilingScale: SIMD2<Float>) -> any RealityKit.Material {
            switch self {
            case let .pbr(texture, tint, roughness, fallback):
                return mats?.pbr(texture, tint: tint, roughness: roughness, scale: tilingScale, fallback: fallback)
                    ?? SimpleMaterial(color: fallback, roughness: .init(floatLiteral: roughness), isMetallic: false)
            case let .unlit(color):
                return UnlitMaterial(color: color)
            case let .simple(color, roughness, metallic):
                return SimpleMaterial(color: color, roughness: .init(floatLiteral: roughness), isMetallic: metallic)
            }
        }
    }

    /// Bucket identity: primitives sharing a key merge into one mesh/entity.
    private enum MaterialKey: Hashable {
        case pbr(texture: String, tint: UInt32, roughness: UInt16)
        case unlit(color: UInt32)
        case simple(color: UInt32, roughness: UInt16, metallic: Bool)
    }

    private final class Bucket {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let spec: MaterialSpec
        init(spec: MaterialSpec) { self.spec = spec }
    }

    private var buckets: [MaterialKey: Bucket] = [:]

    private static func rgba(_ color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var w: CGFloat = 0
            color.getWhite(&w, alpha: &a)
            r = w; g = w; b = w
        }
        func q(_ v: CGFloat) -> UInt32 { UInt32((max(0, min(1, v)) * 255).rounded()) }
        return (q(r) << 24) | (q(g) << 16) | (q(b) << 8) | q(a)
    }

    private static func key(for spec: MaterialSpec) -> MaterialKey {
        switch spec {
        case let .pbr(texture, tint, roughness, _):
            return .pbr(texture: texture, tint: rgba(tint), roughness: UInt16((roughness * 1000).rounded()))
        case let .unlit(color):
            return .unlit(color: rgba(color))
        case let .simple(color, roughness, metallic):
            return .simple(color: rgba(color), roughness: UInt16((roughness * 1000).rounded()), metallic: metallic)
        }
    }

    private func bucket(for spec: MaterialSpec) -> Bucket {
        let key = Self.key(for: spec)
        if let existing = buckets[key] { return existing }
        let created = Bucket(spec: spec)
        buckets[key] = created
        return created
    }

    // MARK: - Accumulation

    /// Appends an axis-or-rotated box (24 verts, flat-shaded, no corner
    /// rounding) into `spec`'s bucket, in world space. `uvScale` bakes the
    /// per-face tiling that `textureCoordinateTransform.scale` used to apply.
    func addBox(size: SIMD3<Float>, transform: Transform, spec: MaterialSpec, uvScale: SIMD2<Float> = [1, 1]) {
        let bucket = bucket(for: spec)
        let matrix = transform.matrix
        let rotation = transform.rotation
        let h = size / 2

        // Each face: 4 corners (CCW seen from outside) + normal + which local
        // axes map to U and V (0=x,1=y,2=z). Winding gives outward normals so
        // default back-face culling keeps them visible.
        struct Face {
            let corners: [SIMD3<Float>]
            let normal: SIMD3<Float>
            let uAxis: Int
            let vAxis: Int
        }
        let faces: [Face] = [
            Face(corners: [[-h.x, h.y, h.z], [h.x, h.y, h.z], [h.x, h.y, -h.z], [-h.x, h.y, -h.z]],
                 normal: [0, 1, 0], uAxis: 0, vAxis: 2),
            Face(corners: [[-h.x, -h.y, -h.z], [h.x, -h.y, -h.z], [h.x, -h.y, h.z], [-h.x, -h.y, h.z]],
                 normal: [0, -1, 0], uAxis: 0, vAxis: 2),
            Face(corners: [[-h.x, -h.y, h.z], [h.x, -h.y, h.z], [h.x, h.y, h.z], [-h.x, h.y, h.z]],
                 normal: [0, 0, 1], uAxis: 0, vAxis: 1),
            Face(corners: [[h.x, -h.y, -h.z], [-h.x, -h.y, -h.z], [-h.x, h.y, -h.z], [h.x, h.y, -h.z]],
                 normal: [0, 0, -1], uAxis: 0, vAxis: 1),
            Face(corners: [[h.x, -h.y, h.z], [h.x, -h.y, -h.z], [h.x, h.y, -h.z], [h.x, h.y, h.z]],
                 normal: [1, 0, 0], uAxis: 2, vAxis: 1),
            Face(corners: [[-h.x, -h.y, -h.z], [-h.x, -h.y, h.z], [-h.x, h.y, h.z], [-h.x, h.y, -h.z]],
                 normal: [-1, 0, 0], uAxis: 2, vAxis: 1),
        ]

        for face in faces {
            let base = UInt32(bucket.positions.count)
            let worldNormal = simd_normalize(rotation.act(face.normal))
            for corner in face.corners {
                let world4 = matrix * SIMD4<Float>(corner, 1)
                bucket.positions.append(SIMD3<Float>(world4.x, world4.y, world4.z))
                bucket.normals.append(worldNormal)
                let u = (corner[face.uAxis] + h[face.uAxis]) / size[face.uAxis] * uvScale.x
                let v = (corner[face.vAxis] + h[face.vAxis]) / size[face.vAxis] * uvScale.y
                bucket.uvs.append([u, v])
            }
            bucket.indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
    }

    /// Appends a Y-axis cylinder (centered at the local origin, matching
    /// `MeshResource.generateCylinder`) into `spec`'s bucket, in world space.
    /// Cylinders in the arena are all solid-color, so UVs are zero.
    func addCylinder(height: Float, radius: Float, transform: Transform, spec: MaterialSpec, segments: Int = 24) {
        let bucket = bucket(for: spec)
        let matrix = transform.matrix
        let rotation = transform.rotation
        let hh = height / 2

        func addVertex(_ local: SIMD3<Float>, _ normal: SIMD3<Float>) -> UInt32 {
            let index = UInt32(bucket.positions.count)
            let world4 = matrix * SIMD4<Float>(local, 1)
            bucket.positions.append(SIMD3<Float>(world4.x, world4.y, world4.z))
            bucket.normals.append(simd_normalize(rotation.act(normal)))
            bucket.uvs.append([0, 0])
            return index
        }

        // Side skin.
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let n0 = SIMD3<Float>(cos(a0), 0, sin(a0))
            let n1 = SIMD3<Float>(cos(a1), 0, sin(a1))
            let bl = addVertex([n0.x * radius, -hh, n0.z * radius], n0)
            let br = addVertex([n1.x * radius, -hh, n1.z * radius], n1)
            let tr = addVertex([n1.x * radius, hh, n1.z * radius], n1)
            let tl = addVertex([n0.x * radius, hh, n0.z * radius], n0)
            bucket.indices.append(contentsOf: [bl, br, tr, bl, tr, tl])
        }

        // Top cap (+Y).
        let topCenter = addVertex([0, hh, 0], [0, 1, 0])
        var topRing: [UInt32] = []
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            topRing.append(addVertex([cos(a) * radius, hh, sin(a) * radius], [0, 1, 0]))
        }
        for i in 0..<segments {
            let next = (i + 1) % segments
            bucket.indices.append(contentsOf: [topCenter, topRing[next], topRing[i]])
        }

        // Bottom cap (-Y).
        let bottomCenter = addVertex([0, -hh, 0], [0, -1, 0])
        var bottomRing: [UInt32] = []
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            bottomRing.append(addVertex([cos(a) * radius, -hh, sin(a) * radius], [0, -1, 0]))
        }
        for i in 0..<segments {
            let next = (i + 1) % segments
            bucket.indices.append(contentsOf: [bottomCenter, bottomRing[i], bottomRing[next]])
        }
    }

    // MARK: - Emit

    /// Emits one merged `ModelEntity` per non-empty bucket under `root`.
    /// Returns the number of draw calls (entities) produced.
    @discardableResult
    func build(into root: Entity, mats: ArenaMaterials?) -> Int {
        var emitted = 0
        for (_, bucket) in buckets where !bucket.positions.isEmpty {
            var descriptor = MeshDescriptor(name: "arenaBatch")
            descriptor.positions = MeshBuffers.Positions(bucket.positions)
            descriptor.normals = MeshBuffers.Normals(bucket.normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(bucket.uvs)
            descriptor.primitives = .triangles(bucket.indices)
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }
            let material = bucket.spec.makeMaterial(mats: mats, tilingScale: [1, 1])
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
            emitted += 1
        }
        buckets.removeAll(keepingCapacity: false)
        return emitted
    }
}
