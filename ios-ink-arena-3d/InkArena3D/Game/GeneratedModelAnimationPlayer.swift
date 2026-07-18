import Foundation
import RealityKit
import simd

/// Drives a character's animation by replaying shared `AnimationResource`
/// clips directly on the character's single skinned model.
///
/// Placement contract: container → runtime ("generated_model_runtime") →
/// base visual (normalized). At first use the player inserts a lightweight
/// compensation entity between the runtime and the base visual so root-motion
/// cancellation can offset the body without fighting the animation's own root
/// transform track (which targets the base visual).
///
/// The clips themselves live in `AnimationClipStore` (one decode per clip for
/// the whole app). Because every clip shares the base model's rig, there is no
/// per-clip mesh clone and no entity swapping: clip transitions are true
/// crossfades on the same skeleton, and memory stays flat.
@MainActor
final class GeneratedModelAnimationPlayer {
    private let container: Entity

    // Resolved once, on first preload/play.
    private var resolved = false
    /// The base model root the animation is played on (structural twin of each
    /// clip's root, so the shared resource retargets cleanly).
    private var baseVisual: Entity?
    private var baseVisualHome: SIMD3<Float> = .zero
    /// First skinned mesh under `baseVisual` — source of `jointTransforms`.
    private var skinnedModel: ModelEntity?
    private var baseJointNames: [String] = []
    private var rootChain: [Int]?
    /// Parent of `baseVisual`, offset every frame to cancel horizontal drift.
    private var compensationEntity: Entity?
    private var compHome: SIMD3<Float> = .zero
    /// Bind-pose bounds of the base visual (compensation-entity space), used to
    /// scale the divergent-rig clone fallback. Nil until resolved.
    private var baseBounds: BoundingBox?

    private var currentLoop: String?
    private var oneShotRestoreTask: Task<Void, Never>?

    // Root-motion compensation for the active non-inplace looping clip.
    private var rootMotionActive = false
    private var startJoint: SIMD3<Float>?

    // Divergent-rig safety net (see `preload`) — never expected to be used.
    private var fallbackTemplates: [String: Entity] = [:]
    private var fallbackClones: [String: Entity] = [:]
    private var activeFallback: Entity?

    init(container: Entity) {
        self.container = container
    }

    private var runtime: Entity {
        container.findEntity(named: "generated_model_runtime") ?? container
    }

    /// Resolves the base model and inserts the compensation entity once.
    private func resolveBaseIfNeeded() {
        guard !resolved else { return }
        resolved = true
        let rt = runtime
        guard let visual = rt.children.first else { return }
        // Insert a compensation wrapper between runtime and the base visual.
        // It carries no normalization (that lives on runtime) so its rest
        // transform is identity — reparenting keeps the world pose unchanged.
        let comp = Entity()
        comp.name = "anim_root_comp"
        rt.addChild(comp)
        comp.addChild(visual)
        baseVisual = visual
        baseVisualHome = visual.position
        compensationEntity = comp
        compHome = comp.position
        let model = AnimationClipStore.findSkinnedModel(in: visual)
        skinnedModel = model
        baseJointNames = model?.jointNames ?? []
        rootChain = model.flatMap { Self.rootJointChain($0) }
        baseBounds = visual.visualBounds(relativeTo: comp)
    }

    func preload(_ resourceNames: [String]) async {
        resolveBaseIfNeeded()
        await AnimationClipStore.shared.load(resourceNames)
        // Divergent-rig detection: any clip whose skeleton doesn't match the
        // base model can't be replayed on it, so retain its template for the
        // clone fallback. With matching Meshy exports this never triggers.
        guard !baseJointNames.isEmpty else { return }
        for name in resourceNames {
            guard let clipJoints = AnimationClipStore.shared.joints(name) else { continue }
            if clipJoints != baseJointNames, fallbackTemplates[name] == nil {
                NSLog("[AnimPlayer] Rig mismatch for clip \(name) — using clone fallback")
                fallbackTemplates[name] = try? await Entity(named: name)
            }
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
        resolveBaseIfNeeded()
        // Stop whatever was playing and clear the compensation offset.
        baseVisual?.stopAllAnimations()
        activeFallback?.stopAllAnimations()
        if let fallback = activeFallback {
            fallback.isEnabled = false
            activeFallback = nil
            baseVisual?.isEnabled = true
        }
        resetCompensation()
        guard let resourceName else { return }

        // Divergent rig → clone fallback (never expected in normal play).
        if fallbackTemplates[resourceName] != nil {
            playFallback(resourceName, looping: looping)
            return
        }

        guard let base = baseVisual,
              let clip = AnimationClipStore.shared.clip(resourceName) else { return }
        base.playAnimation(
            looping ? clip.repeat() : clip,
            transitionDuration: 0.2,
            startsPaused: false
        )

        // Non-inplace looping clips carry baked forward root motion that must
        // be cancelled every frame; inplace clips and one-shots play as-is.
        if looping, !resourceName.contains("inplace"), rootChain != nil {
            rootMotionActive = true
            startJoint = nil
        }
    }

    /// Cancels the horizontal root motion of the active non-inplace looping
    /// clip — call once per frame from the game update. The body then plays in
    /// place while the game moves the character container itself, with no
    /// forward drift or loop snap-back. No-op otherwise.
    func cancelHorizontalRootMotion() {
        guard rootMotionActive,
              let comp = compensationEntity,
              let base = baseVisual,
              let model = skinnedModel,
              let chain = rootChain else { return }
        let joint = Self.chainTranslation(model, chain: chain)
        guard let startJoint else {
            self.startJoint = joint
            return
        }
        let toComp = model.transformMatrix(relativeTo: comp)
        let current = toComp * SIMD4<Float>(joint.x, joint.y, joint.z, 1)
        let start = toComp * SIMD4<Float>(startJoint.x, startJoint.y, startJoint.z, 1)
        var drift = SIMD3<Float>(current.x - start.x, current.y - start.y, current.z - start.z)
        drift += base.position - baseVisualHome
        drift *= comp.scale.x
        comp.position = compHome - SIMD3<Float>(drift.x, 0, drift.z)
    }

    /// Restores the compensation entity and base visual to their rest poses and
    /// disarms the per-frame root-motion lock.
    private func resetCompensation() {
        rootMotionActive = false
        startJoint = nil
        compensationEntity?.position = compHome
        baseVisual?.position = baseVisualHome
    }

    // MARK: Divergent-rig clone fallback

    /// Plays a clip whose rig differs from the base model by cloning the clip's
    /// own mesh (old behaviour), scaled to the base visual's height. Kept
    /// minimal — it only runs when `preload` logged a rig mismatch.
    private func playFallback(_ name: String, looping: Bool) {
        guard let comp = compensationEntity else { return }
        let clone: Entity
        if let existing = fallbackClones[name] {
            clone = existing
        } else if let template = fallbackTemplates[name] {
            let animated = template.clone(recursive: true)
            comp.addChild(animated)
            alignClone(animated)
            fallbackClones[name] = animated
            clone = animated
        } else {
            return
        }
        baseVisual?.isEnabled = false
        clone.isEnabled = true
        if let anim = clone.availableAnimations.first {
            clone.playAnimation(looping ? anim.repeat() : anim, transitionDuration: 0.2)
        }
        activeFallback = clone
    }

    /// Scales and offsets a fallback clone so its bind-pose bounds match the
    /// base visual (same height, same bottom-center anchor).
    private func alignClone(_ animated: Entity) {
        guard let baseBounds, baseBounds.extents.y > 0.001 else { return }
        let bounds = animated.visualBounds(relativeTo: animated.parent)
        guard bounds.extents.y > 0.001 else { return }
        let scale = baseBounds.extents.y / bounds.extents.y
        animated.scale = SIMD3<Float>(repeating: scale)
        animated.position = SIMD3<Float>(
            baseBounds.center.x - bounds.center.x * scale,
            baseBounds.min.y - bounds.min.y * scale,
            baseBounds.center.z - bounds.center.z * scale
        )
    }

    // MARK: Joint helpers

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
}
