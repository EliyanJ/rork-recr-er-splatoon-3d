import Foundation
import RealityKit
import UIKit
import simd

/// Merges the arena's static geometry into a handful of big meshes.
///
/// WHY — the two traces we captured agree: about 83 % of a frame is spent
/// outside our own code, in RealityKit's render submission and waiting on the
/// GPU, while everything we measure (bots, projectiles, paint, HUD,
/// animations) adds up to roughly 4 ms. The arena is built from ~250 separate
/// `ModelEntity` objects — every platform, every neon trim strip, every crate,
/// every backdrop building is its own draw call with its own transform upload
/// and material binding, every single frame, forever. None of them ever move.
///
/// HOW — after the arena is built, this pass walks the static subtree, groups
/// every mesh by the material it uses, bakes each entity's world transform
/// straight into its vertices, and emits ONE merged mesh per material. The
/// originals are removed. Same pixels, same materials, a fraction of the
/// submission work.
///
/// SAFETY RULES — an entity is only absorbed when it is provably inert:
/// - it is a `ModelEntity` with exactly one recognised material;
/// - that material is fully opaque (transparent surfaces — water, holograms,
///   crystals — keep their own entity so RealityKit can still sort them
///   back-to-front, which a merged mesh would break);
/// - it has no animation, no collision and no physics attached.
/// Anything failing a rule is left exactly as it was, so a mistake here can
/// cost performance but cannot corrupt the scene.
@MainActor
enum StaticBatcher {
    /// What one merge pass did — surfaced in the performance report so a
    /// TestFlight run can confirm the batching actually happened.
    struct Stats {
        var absorbed = 0
        var produced = 0
        var keptAsIs = 0

        var drawCallsSaved: Int { max(0, absorbed - produced) }

        static func + (lhs: Stats, rhs: Stats) -> Stats {
            Stats(
                absorbed: lhs.absorbed + rhs.absorbed,
                produced: lhs.produced + rhs.produced,
                keptAsIs: lhs.keptAsIs + rhs.keptAsIs
            )
        }
    }

    /// Vertex ceiling per merged mesh. Well under any index limit, and small
    /// enough that a batch stays a sensible culling unit.
    private static let maxVerticesPerBatch = 60_000

    // MARK: - Entry point

    /// Merges every eligible descendant of `roots` into batches parented to
    /// each root. Roots are processed independently, so a branch that must
    /// stay switchable as a whole (the decorative layer) keeps its own
    /// batches and can still be disabled in one assignment.
    @discardableResult
    private static func merge(roots: [Entity], protecting protected: Set<ObjectIdentifier>) -> Stats {
        var stats = Stats()
        for root in roots {
            stats = stats + mergeSubtree(of: root, protecting: protected)
        }
        return stats
    }

    private static func mergeSubtree(of root: Entity, protecting protected: Set<ObjectIdentifier>) -> Stats {
        var groups: [String: Group] = [:]
        var stats = Stats()

        for child in root.children.map({ $0 }) where !protected.contains(ObjectIdentifier(child)) {
            collect(entity: child, root: root, groups: &groups, protected: protected, stats: &stats)
        }

        // Post-order removal: an entity disappears only once every part of it
        // (its own mesh and all of its children) has been absorbed.
        for child in root.children.map({ $0 }) where !protected.contains(ObjectIdentifier(child)) {
            prune(entity: child, protected: protected)
        }

        for (_, group) in groups {
            for batch in group.batches {
                guard let mesh = batch.makeMesh() else {
                    stats.keptAsIs += batch.sourceCount
                    continue
                }
                let entity = ModelEntity(mesh: mesh, materials: [group.material])
                entity.name = "static_batch"
                root.addChild(entity)
                stats.absorbed += batch.sourceCount
                stats.produced += 1
            }
        }
        return stats
    }

    // MARK: - Collection

    private static func collect(
        entity: Entity,
        root: Entity,
        groups: inout [String: Group],
        protected: Set<ObjectIdentifier>,
        stats: inout Stats
    ) {
        guard !protected.contains(ObjectIdentifier(entity)) else { return }
        for child in entity.children.map({ $0 }) {
            collect(entity: child, root: root, groups: &groups, protected: protected, stats: &stats)
        }

        guard let model = entity as? ModelEntity,
              let component = model.model,
              component.materials.count == 1,
              isInert(model)
        else {
            if entity is ModelEntity { stats.keptAsIs += 1 }
            return
        }
        let material = component.materials[0]
        guard let key = batchKey(for: material) else {
            stats.keptAsIs += 1
            return
        }

        let transform = entity.transformMatrix(relativeTo: root)
        var group = groups[key] ?? Group(material: material)
        guard group.append(mesh: component.mesh, transform: transform, limit: maxVerticesPerBatch) else {
            stats.keptAsIs += 1
            return
        }
        groups[key] = group
        absorbedEntities.insert(ObjectIdentifier(entity))
    }

    /// Entities whose geometry has been copied into a batch and which must
    /// therefore leave the scene. Cleared at the start of every pass.
    private static var absorbedEntities: Set<ObjectIdentifier> = []

    /// True when nothing but a transform and a mesh is attached — no skeleton
    /// to animate, no collider to query, no physics to step.
    private static func isInert(_ entity: ModelEntity) -> Bool {
        entity.isEnabled
            && entity.components[CollisionComponent.self] == nil
            && entity.components[PhysicsBodyComponent.self] == nil
            && entity.components[PhysicsMotionComponent.self] == nil
            && entity.availableAnimations.isEmpty
    }

    /// Removes fully absorbed branches. Returns true when `entity` itself was
    /// removed, so the caller can decide about its own parent.
    @discardableResult
    private static func prune(entity: Entity, protected: Set<ObjectIdentifier>) -> Bool {
        guard !protected.contains(ObjectIdentifier(entity)) else { return false }
        var allChildrenGone = true
        for child in entity.children.map({ $0 }) {
            if !prune(entity: child, protected: protected) { allChildrenGone = false }
        }
        guard allChildrenGone,
              absorbedEntities.contains(ObjectIdentifier(entity))
        else { return false }
        entity.removeFromParent()
        return true
    }

    // MARK: - Geometry accumulation

    private struct Group {
        let material: any RealityKit.Material
        var batches: [Batch] = [Batch()]

        init(material: any RealityKit.Material) {
            self.material = material
        }

        /// Appends one mesh, opening a fresh batch when the current one is
        /// full. Returns false when the mesh could not be read at all.
        mutating func append(mesh: MeshResource, transform: simd_float4x4, limit: Int) -> Bool {
            guard let piece = Piece(mesh: mesh, transform: transform), !piece.positions.isEmpty else {
                return false
            }
            if batches[batches.count - 1].positions.count + piece.positions.count > limit {
                batches.append(Batch())
            }
            batches[batches.count - 1].add(piece)
            return true
        }
    }

    /// One entity's geometry, already expressed in the batch's space.
    private struct Piece {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        init?(mesh: MeshResource, transform: simd_float4x4) {
            let contents = mesh.contents
            // A mirrored transform (negative determinant) turns every triangle
            // inside out; the winding has to be flipped to compensate.
            let flipWinding = transform.determinant < 0
            let linear = simd_float3x3(
                SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            )
            // Normals need the inverse-transpose, otherwise any non-uniform
            // scale (the stretched blimp hulls, the paint drips) would light
            // wrongly after baking.
            let normalMatrix = linear.inverse.transpose

            for instance in contents.instances {
                guard let model = contents.models[instance.model] else { continue }
                let full = transform * instance.transform
                let instanceFlip = flipWinding != (instance.transform.determinant < 0)
                for part in model.parts {
                    guard let triangles = part.triangleIndices?.elements, !triangles.isEmpty else { continue }
                    let localPositions = part.positions.elements
                    guard !localPositions.isEmpty else { continue }
                    let localNormals = part.normals?.elements
                    let localUVs = part.textureCoordinates?.elements
                    let base = UInt32(positions.count)

                    for (index, position) in localPositions.enumerated() {
                        let world = full * SIMD4<Float>(position, 1)
                        positions.append(SIMD3<Float>(world.x, world.y, world.z))
                        if let localNormals, index < localNormals.count {
                            let n = normalMatrix * localNormals[index]
                            let length = simd_length(n)
                            normals.append(length > 1e-6 ? n / length : SIMD3<Float>(0, 1, 0))
                        } else {
                            normals.append(SIMD3<Float>(0, 1, 0))
                        }
                        if let localUVs, index < localUVs.count {
                            uvs.append(localUVs[index])
                        } else {
                            uvs.append(.zero)
                        }
                    }

                    var i = 0
                    while i + 2 < triangles.count {
                        let a = base + triangles[i]
                        let b = base + triangles[i + 1]
                        let c = base + triangles[i + 2]
                        if instanceFlip {
                            indices.append(contentsOf: [a, c, b])
                        } else {
                            indices.append(contentsOf: [a, b, c])
                        }
                        i += 3
                    }
                }
            }
            if positions.isEmpty { return nil }
        }
    }

    private struct Batch {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var sourceCount = 0

        mutating func add(_ piece: Piece) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: piece.positions)
            normals.append(contentsOf: piece.normals)
            uvs.append(contentsOf: piece.uvs)
            indices.append(contentsOf: piece.indices.map { $0 + base })
            sourceCount += 1
        }

        func makeMesh() -> MeshResource? {
            guard !positions.isEmpty, !indices.isEmpty else { return nil }
            var descriptor = MeshDescriptor(name: "static_batch")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
            descriptor.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [descriptor])
        }
    }

    // MARK: - Material identity

    /// A string that is equal for two materials exactly when swapping one for
    /// the other would change nothing on screen. Returns nil for materials we
    /// refuse to batch (unknown types, anything translucent).
    private static func batchKey(for material: any RealityKit.Material) -> String? {
        if let unlit = material as? UnlitMaterial {
            guard isOpaque(unlit.blending) else { return nil }
            return [
                "unlit",
                colorKey(unlit.color.tint),
                textureKey(unlit.color.texture),
                String(describing: unlit.textureCoordinateTransform),
                String(describing: unlit.opacityThreshold),
            ].joined(separator: "|")
        }
        if let pbr = material as? PhysicallyBasedMaterial {
            guard isOpaque(pbr.blending) else { return nil }
            return [
                "pbr",
                colorKey(pbr.baseColor.tint),
                textureKey(pbr.baseColor.texture),
                String(describing: pbr.roughness),
                String(describing: pbr.metallic),
                String(describing: pbr.emissiveColor),
                String(describing: pbr.textureCoordinateTransform),
                String(describing: pbr.opacityThreshold),
            ].joined(separator: "|")
        }
        if let simple = material as? SimpleMaterial {
            // SimpleMaterial has no blending knob: a tint alpha below 1 is the
            // only way it can be translucent.
            guard simple.color.tint.cgColor.alpha >= 0.999 else { return nil }
            return [
                "simple",
                colorKey(simple.color.tint),
                textureKey(simple.color.texture),
                String(describing: simple.roughness),
                String(describing: simple.metallic),
            ].joined(separator: "|")
        }
        return nil
    }

    private static func isOpaque(_ blending: PhysicallyBasedMaterial.Blending) -> Bool {
        String(describing: blending).hasPrefix("opaque")
    }

    private static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return String(describing: color)
        }
        return String(format: "%.4f,%.4f,%.4f,%.4f", r, g, b, a)
    }

    private static func textureKey(_ texture: MaterialParameters.Texture?) -> String {
        guard let texture else { return "none" }
        return String(UInt(bitPattern: ObjectIdentifier(texture.resource).hashValue))
    }

    /// Resets the per-pass bookkeeping. Called by `merge(roots:protecting:)`
    /// so two matches in a row never see each other's state.
    fileprivate static func beginPass() {
        absorbedEntities.removeAll(keepingCapacity: true)
    }
}

extension StaticBatcher {
    /// Convenience wrapper that clears state, merges, and returns the stats.
    static func run(roots: [Entity], protecting protected: Set<ObjectIdentifier> = []) -> Stats {
        beginPass()
        let stats = merge(roots: roots, protecting: protected)
        absorbedEntities.removeAll(keepingCapacity: true)
        return stats
    }
}
