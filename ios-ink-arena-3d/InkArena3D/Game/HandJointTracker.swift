import RealityKit
import simd

/// Tracks a character's animated hand joints so hand-anchored props (the
/// weapon) follow the skeletal animation every frame instead of staying
/// frozen at a fixed mount point.
///
/// The tracker finds the currently visible skinned `ModelEntity` under the
/// character container (the base visual or the active animation clone),
/// picks the best RIGHT and LEFT hand joints from `jointNames`, and
/// accumulates each joint chain's `jointTransforms` — which RealityKit
/// updates during playback — to produce each hand's live position in
/// container space. Two-handed props (the roller) anchor to the midpoint of
/// both hands instead of drifting toward a single tracked joint.
@MainActor
final class HandJointTracker {
    private weak var trackedModel: ModelEntity?
    private var primaryChain: [Int] = []
    private var secondaryChain: [Int] = []

    /// Container-space position of the primary (right) hand joint of the
    /// currently visible skinned model, or nil when no usable skeleton is
    /// visible (hidden body in first person, fallback models without a rig, ...).
    func handPosition(in container: Entity) -> SIMD3<Float>? {
        ensureResolved(in: container)
        return position(for: primaryChain, in: container)
    }

    /// Container-space position of the secondary (left/off) hand joint —
    /// used to anchor two-handed weapons at the true midpoint between both
    /// hands instead of a single joint plus a guessed offset. Nil when the
    /// skeleton has no distinguishable second hand joint.
    func secondaryHandPosition(in container: Entity) -> SIMD3<Float>? {
        ensureResolved(in: container)
        return position(for: secondaryChain, in: container)
    }

    private func ensureResolved(in container: Entity) {
        if trackedModel?.isActive != true {
            resolveModel(in: container)
        }
    }

    private func position(for chain: [Int], in container: Entity) -> SIMD3<Float>? {
        guard let model = trackedModel, !chain.isEmpty else { return nil }
        let transforms = model.jointTransforms
        var matrix = matrix_identity_float4x4
        for index in chain {
            guard index < transforms.count else { return nil }
            matrix *= transforms[index].matrix
        }
        let inContainer = model.transformMatrix(relativeTo: container) * matrix
        return SIMD3<Float>(
            inContainer.columns.3.x,
            inContainer.columns.3.y,
            inContainer.columns.3.z
        )
    }

    /// Re-finds the visible skinned model — called whenever the previously
    /// tracked one is swapped out by the animation player or disabled.
    private func resolveModel(in container: Entity) {
        trackedModel = nil
        primaryChain = []
        secondaryChain = []
        guard let model = Self.findSkinnedModel(in: container) else { return }
        if let path = Self.selectHandJoint(model.jointNames, preferRight: true) {
            primaryChain = Self.jointChain(for: path, in: model.jointNames)
        }
        if let path = Self.selectHandJoint(model.jointNames, preferRight: false) {
            secondaryChain = Self.jointChain(for: path, in: model.jointNames)
        }
        trackedModel = model
    }

    /// Joint transforms are relative to the parent joint, so build the
    /// ancestor index chain (every path prefix) once and cache it.
    private static func jointChain(for path: String, in names: [String]) -> [Int] {
        var chain: [Int] = []
        var prefix = ""
        for component in path.split(separator: "/") {
            prefix = prefix.isEmpty ? String(component) : prefix + "/" + String(component)
            guard let index = names.firstIndex(of: prefix) else { return [] }
            chain.append(index)
        }
        return chain
    }

    /// Depth-first search for an enabled skinned mesh, skipping the weapon
    /// and dive-form subtrees so the tracker never latches onto a prop.
    private static func findSkinnedModel(in entity: Entity) -> ModelEntity? {
        if entity.name == "weapon_socket" || entity.name == "dive_form" { return nil }
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty {
            return model
        }
        for child in entity.children where child.isEnabled {
            if let found = findSkinnedModel(in: child) {
                return found
            }
        }
        return nil
    }

    /// Picks a hand joint: when `preferRight` is true, favors the right hand
    /// (primary weapon-holding hand); otherwise favors the left hand (the
    /// off/support hand used to anchor two-handed props). Always skips
    /// finger joints.
    private static func selectHandJoint(_ names: [String], preferRight: Bool) -> String? {
        var best: (score: Int, depth: Int, name: String)?
        let fingerParts = ["thumb", "index", "middle", "ring", "pinky", "finger"]
        for name in names {
            guard let lastComponent = name.split(separator: "/").last else { continue }
            let joint = lastComponent.lowercased()
            guard joint.contains("hand") else { continue }
            if fingerParts.contains(where: { joint.contains($0) }) { continue }

            let isRight = joint.contains("right") || joint.hasSuffix("_r") || joint.hasSuffix(".r") || joint.hasPrefix("r_")
            let isLeft = joint.contains("left") || joint.hasSuffix("_l") || joint.hasSuffix(".l") || joint.hasPrefix("l_")

            var score = 0
            if preferRight, isRight { score += 4 }
            if !preferRight, isLeft { score += 4 }
            // If the skeleton has no explicit left/right naming, both
            // selections fall back to whatever "hand" joint scores highest
            // below — better a shared anchor than no anchor at all.
            if joint.contains("weapon") || joint.contains("prop") || joint.contains("attach") {
                score += 2
            }
            let depth = name.split(separator: "/").count
            if let current = best {
                if score > current.score || (score == current.score && depth < current.depth) {
                    best = (score, depth, name)
                }
            } else {
                best = (score, depth, name)
            }
        }
        return best?.name
    }
}
