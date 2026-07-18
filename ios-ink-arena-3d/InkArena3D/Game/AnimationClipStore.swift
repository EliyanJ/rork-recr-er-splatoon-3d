import RealityKit

/// Process-wide cache of animation clips, keyed by resource name.
///
/// Meshy exports every clip as a full USDZ (mesh + skeleton + texture), but we
/// only ever need the clip's `AnimationResource` — the skeleton is shared with
/// the character's base model, so the animation can be replayed directly on
/// that single skinned model. Extracting and caching just the resource means:
///   * each clip USDZ is decoded ONCE for the whole app (not once per animator
///     instance × clip, which was ~50 redundant decodes per match), and
///   * the heavy mesh/texture of the clip template is released immediately,
///     leaving only the lightweight animation curves resident.
///
/// `@MainActor` serializes all dictionary access; concurrent decodes still run
/// in parallel because `Entity(named:)` performs its heavy work off the main
/// thread and only resumes here to store the result.
@MainActor
final class AnimationClipStore {
    static let shared = AnimationClipStore()

    private var clips: [String: AnimationResource] = [:]
    /// Joint names of each clip's skinned model, used to validate that a clip
    /// shares the base model's rig before it is replayed on it.
    private var jointSignatures: [String: [String]] = [:]
    /// In-flight loads, so concurrent callers requesting the same clip await a
    /// single decode instead of racing to decode it twice.
    private var inFlight: [String: Task<Void, Never>] = [:]

    private init() {}

    /// Loads (once per name) every requested clip. Returns only after all
    /// requested clips are resident, so callers can `play` them immediately.
    func load(_ names: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask { @MainActor [weak self] in
                    await self?.loadOne(name)
                }
            }
        }
    }

    private func loadOne(_ name: String) async {
        if clips[name] != nil { return }
        if let existing = inFlight[name] {
            await existing.value
            return
        }
        let task = Task { @MainActor in
            guard let entity = try? await Entity(named: name) else { return }
            guard let anim = entity.availableAnimations.first else { return }
            clips[name] = anim
            // Only record a signature when the clip still carries a skinned
            // mesh. Production clips are stripped to skeleton + animation only
            // (see tools/strip_anim_usdz.py), so they expose no skinned model
            // and no signature — the rig-match check then simply trusts them
            // (a stripped clip is derived from the correct source and can't
            // carry the wrong rig). Un-stripped dev clips still get validated.
            if let joints = Self.findSkinnedModel(in: entity)?.jointNames {
                jointSignatures[name] = joints
            }
            // `entity` (mesh + skeleton + texture) is released here; only the
            // AnimationResource survives.
        }
        inFlight[name] = task
        await task.value
        inFlight[name] = nil
    }

    func clip(_ name: String) -> AnimationResource? { clips[name] }

    func joints(_ name: String) -> [String]? { jointSignatures[name] }

    /// First skinned mesh (a `ModelEntity` with a non-empty joint list) under
    /// `entity`, found depth-first.
    static func findSkinnedModel(in entity: Entity) -> ModelEntity? {
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
}
