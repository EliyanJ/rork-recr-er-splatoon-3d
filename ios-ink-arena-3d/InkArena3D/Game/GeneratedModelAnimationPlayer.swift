import RealityKit
import simd

/// Swaps generated Meshy animation entities under a model container.
/// Assumes the placement contract: container → runtime child
/// ("generated_model_runtime") → normalized base visual.
@MainActor
final class GeneratedModelAnimationPlayer {
    private let container: Entity
    private var templates: [String: Entity] = [:]
    private var activeAnimation: Entity?
    private var baseVisual: Entity?
    private var baseBounds: BoundingBox?
    private var currentLoop: String?
    private var oneShotRestoreTask: Task<Void, Never>?
    /// Per-clip wrapper scale + position, computed once (from the template's
    /// bind-pose bounds) instead of recalculated on every `play()` call —
    /// clip transitions happen constantly during combat (idle↔run↔hit), so
    /// this avoids a `visualBounds` walk of the skeleton each time.
    private var alignmentCache: [String: (scale: Float, position: SIMD3<Float>)] = [:]
    /// One reusable animated clone per clip. Cloning a skinned skeleton
    /// recursively is one of the most expensive RealityKit operations, and
    /// clip transitions (idle↔run↔hit) fire constantly in combat for every
    /// fighter — so each clip is cloned ONCE and then re-enabled/replayed.
    private struct CachedClone {
        let wrapper: Entity
        let animated: Entity
        /// Wrapper transform right after alignment — restored on every reuse
        /// (the root-motion lock moves the wrapper during playback).
        let alignedScale: SIMD3<Float>
        let alignedPosition: SIMD3<Float>
        let initialAnimatedPosition: SIMD3<Float>
        /// Skinned model + hips joint chain, resolved once per clip instead
        /// of walking the entity tree on every transition.
        let skinnedModel: ModelEntity?
        let jointChain: [Int]?
    }

    private var clones: [String: CachedClone] = [:]
    private var activeClone: CachedClone?

    /// Live compensation state for looping clips that carry baked-in root
    /// motion (non-inplace walk-style clips like the roller push): the
    /// skeleton drifts forward during playback and snaps back on loop, so
    /// the wrapper is re-offset every frame to cancel the horizontal drift.
    private struct RootMotionLock {
        let wrapper: Entity
        let animated: Entity
        let model: ModelEntity
        let chain: [Int]
        var startJoint: SIMD3<Float>?
        let startEntityPosition: SIMD3<Float>
        let alignedPosition: SIMD3<Float>
    }

    private var rootLock: RootMotionLock?

    init(container: Entity) {
        self.container = container
    }

    private var runtime: Entity {
        container.findEntity(named: "generated_model_runtime") ?? container
    }

    func preload(_ resourceNames: [String]) async {
        if baseVisual == nil { baseVisual = runtime.children.first }
        if baseBounds == nil, let baseVisual {
            baseBounds = baseVisual.visualBounds(relativeTo: runtime)
        }
        for name in resourceNames where templates[name] == nil {
            templates[name] = try? await Entity(named: name)
        }
        // Bake the wrapper scale/offset for every newly loaded clip once,
        // from a throwaway (unparented) clone — every future clone of the
        // same template shares the same bind-pose bounds.
        guard let baseBounds, baseBounds.extents.y > 0.001 else { return }
        for name in resourceNames where alignmentCache[name] == nil {
            guard let template = templates[name] else { continue }
            let probe = template.clone(recursive: true)
            let bounds = probe.visualBounds(relativeTo: nil)
            guard bounds.extents.y > 0.001 else { continue }
            let scale = baseBounds.extents.y / bounds.extents.y
            let position = SIMD3<Float>(
                baseBounds.center.x - bounds.center.x * scale,
                baseBounds.min.y - bounds.min.y * scale,
                baseBounds.center.z - bounds.center.z * scale
            )
            alignmentCache[name] = (scale, position)
        }
    }

    /// Passing nil stops generated playback and restores the base visual — use
    /// it for states without a bundled clip so stale walk/run loops never stick.
    func setLoop(_ resourceName: String?) {
        currentLoop = resourceName
        oneShotRestoreTask?.cancel()
        play(resourceName, looping: true)
    }

    func playOnce(_ resourceName: String?, restoreAfter duration: Duration = .milliseconds(650)) {
        guard let resourceName else { return }
        play(resourceName, looping: false)
        oneShotRestoreTask?.cancel()
        oneShotRestoreTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            self.play(self.currentLoop, looping: true)
        }
    }

    func stop() {
        currentLoop = nil
        oneShotRestoreTask?.cancel()
        play(nil, looping: false)
    }

    private func play(_ resourceName: String?, looping: Bool) {
        // Hide (never destroy) the previous clip's clone — it will be
        // re-enabled on its next turn instead of re-cloned.
        if let previous = activeClone {
            previous.animated.stopAllAnimations()
            previous.wrapper.isEnabled = false
        } else {
            activeAnimation?.removeFromParent()
        }
        activeAnimation = nil
        activeClone = nil
        rootLock = nil
        baseVisual?.isEnabled = true
        guard let resourceName, let template = templates[resourceName] else { return }

        let cached: CachedClone
        if let existing = clones[resourceName] {
            cached = existing
        } else {
            // First use of this clip: build its reusable clone. Normalization
            // (scale / orientation / centering) lives on the runtime parent,
            // so the animated clone is added at identity — animation clips
            // with root transform tracks can no longer knock the character
            // over. A wrapper carries a per-clip correction so every clone
            // matches the base visual's size and foot placement exactly —
            // otherwise clips exported at a different raw size/origin shift
            // the rendered body up and hand-anchored props (the weapon) end
            // up at the character's feet.
            let animated = template.clone(recursive: true)
            let wrapper = Entity()
            wrapper.name = "generated_anim_wrapper"
            wrapper.addChild(animated)
            runtime.addChild(wrapper)
            if let alignment = alignmentCache[resourceName] {
                wrapper.scale = SIMD3<Float>(repeating: alignment.scale)
                wrapper.position = alignment.position
            } else {
                // Not preloaded (shouldn't normally happen) — fall back to
                // the per-call bounds computation so playback still lines up.
                alignToBase(wrapper: wrapper, animated: animated)
            }
            let model = Self.findSkinnedModel(in: animated)
            cached = CachedClone(
                wrapper: wrapper,
                animated: animated,
                alignedScale: wrapper.scale,
                alignedPosition: wrapper.position,
                initialAnimatedPosition: animated.position,
                skinnedModel: model,
                jointChain: model.flatMap { Self.rootJointChain($0) }
            )
            clones[resourceName] = cached
        }

        // Restore the exact aligned pose — the root-motion lock may have
        // shifted the wrapper during the clip's previous playback.
        cached.wrapper.scale = cached.alignedScale
        cached.wrapper.position = cached.alignedPosition
        cached.animated.position = cached.initialAnimatedPosition
        baseVisual?.isEnabled = false
        cached.wrapper.isEnabled = true
        if let animation = cached.animated.availableAnimations.first {
            cached.animated.playAnimation(looping ? animation.repeat() : animation, transitionDuration: 0.2)
        }
        activeAnimation = cached.wrapper
        activeClone = cached

        // Non-inplace looping clips need per-frame root-motion cancellation;
        // inplace clips (and one-shots) play as-is.
        if looping, !resourceName.contains("inplace"),
           let model = cached.skinnedModel,
           let chain = cached.jointChain {
            rootLock = RootMotionLock(
                wrapper: cached.wrapper,
                animated: cached.animated,
                model: model,
                chain: chain,
                startJoint: nil,
                startEntityPosition: cached.initialAnimatedPosition,
                alignedPosition: cached.alignedPosition
            )
        }
    }

    /// Cancels the horizontal root motion of the active non-inplace looping
    /// clip — call once per frame from the game update. Walk-style clips then
    /// play in place while the game moves the character container itself,
    /// with no forward drift or loop snap-back. No-op otherwise.
    func cancelHorizontalRootMotion() {
        guard let lock = rootLock else { return }
        let joint = Self.chainTranslation(lock.model, chain: lock.chain)
        guard let startJoint = lock.startJoint else {
            rootLock?.startJoint = joint
            return
        }
        let toWrapper = lock.model.transformMatrix(relativeTo: lock.wrapper)
        let current = toWrapper * SIMD4<Float>(joint.x, joint.y, joint.z, 1)
        let start = toWrapper * SIMD4<Float>(startJoint.x, startJoint.y, startJoint.z, 1)
        var drift = SIMD3<Float>(current.x - start.x, current.y - start.y, current.z - start.z)
        drift += lock.animated.position - lock.startEntityPosition
        drift *= lock.wrapper.scale.x
        lock.wrapper.position = lock.alignedPosition - SIMD3<Float>(drift.x, 0, drift.z)
    }

    /// Accumulated translation of the joint chain in the model's local space.
    private static func chainTranslation(_ model: ModelEntity, chain: [Int]) -> SIMD3<Float> {
        let transforms = model.jointTransforms
        var matrix = matrix_identity_float4x4
        for index in chain {
            guard index < transforms.count else { return .zero }
            matrix *= transforms[index].matrix
        }
        return SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    /// Chain of ancestor joint indices leading to the hips/pelvis (where
    /// walk-cycle root motion is baked), falling back to the shallowest joint.
    private static func rootJointChain(_ model: ModelEntity) -> [Int]? {
        let names = model.jointNames
        guard !names.isEmpty else { return nil }
        let target = names.first { name in
            let last = name.split(separator: "/").last?.lowercased() ?? ""
            return last.contains("hips") || last.contains("pelvis")
        } ?? names.min { $0.split(separator: "/").count < $1.split(separator: "/").count }
        guard let target else { return nil }
        var chain: [Int] = []
        var prefix = ""
        for component in target.split(separator: "/") {
            prefix = prefix.isEmpty ? String(component) : prefix + "/" + String(component)
            guard let index = names.firstIndex(of: prefix) else { return nil }
            chain.append(index)
        }
        return chain
    }

    /// First skinned mesh under the animated clone.
    private static func findSkinnedModel(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty {
            return model
        }
        for child in entity.children {
            if let found = findSkinnedModel(in: child) {
                return found
            }
        }
        return nil
    }

    /// Scales and offsets the wrapper so the clone's bind-pose bounds line up
    /// with the base visual (same height, same bottom-center anchor).
    private func alignToBase(wrapper: Entity, animated: Entity) {
        guard let baseBounds else { return }
        let bounds = animated.visualBounds(relativeTo: runtime)
        guard bounds.extents.y > 0.001, baseBounds.extents.y > 0.001 else { return }
        let scale = baseBounds.extents.y / bounds.extents.y
        wrapper.scale = SIMD3<Float>(repeating: scale)
        wrapper.position = SIMD3<Float>(
            baseBounds.center.x - bounds.center.x * scale,
            baseBounds.min.y - bounds.min.y * scale,
            baseBounds.center.z - bounds.center.z * scale
        )
    }
}
