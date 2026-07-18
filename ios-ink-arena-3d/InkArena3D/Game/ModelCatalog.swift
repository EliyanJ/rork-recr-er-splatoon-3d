import Foundation

/// Bundled generated-model resource names and their persisted orientation
/// metadata. Resource names come verbatim from the generation tool output.
enum ModelCatalog {
    struct GeneratedModelSpec {
        let resourceName: String?
        let localFrontAxis: GeneratedModelAxis?
        let localUpAxis: GeneratedModelAxis
    }

    // NOTE: the three base character models (`stylized_cartoon_urban_warrior_character`,
    // `urban_paint_warrior`, `cartoon_paint_warrior`) are STATIC meshes with no
    // skeleton — the 24-joint rig lives only inside the `-anim-*` clip files.
    // A character's animatable body is therefore its `-anim-idle` clip (a fully
    // rigged, textured model), NOT the static base file. The base specs are kept
    // only for orientation metadata and the procedural fallback.
    // IMPORTANT: never strip the mesh/texture out of any `-anim-idle` file — it
    // doubles as the rigged body. Other clips may be mesh-stripped safely.

    static let hero = GeneratedModelSpec(
        resourceName: "stylized_cartoon_urban_warrior_character",
        localFrontAxis: .positiveZ,
        localUpAxis: .positiveY
    )

    static let rival = GeneratedModelSpec(
        resourceName: "cartoon_paint_warrior",
        localFrontAxis: .positiveZ,
        localUpAxis: .positiveY
    )

    static let blaster = GeneratedModelSpec(
        resourceName: "toy_paint_blaster",
        localFrontAxis: .negativeX,
        localUpAxis: .positiveY
    )

    /// Generated sniper rifle — muzzle at the front (-X per orientation
    /// metadata), stock and scope at the back.
    static let sniper = GeneratedModelSpec(
        resourceName: "sniper_paint_rifle",
        localFrontAxis: .negativeX,
        localUpAxis: .positiveY
    )

    /// Generated machine gun — triple barrel at the front (-X).
    static let machineGun = GeneratedModelSpec(
        resourceName: "paint_machine_gun",
        localFrontAxis: .negativeX,
        localUpAxis: .positiveY
    )

    /// Generated bucket launcher — wide muzzle at the front (-X).
    static let bucketLauncher = GeneratedModelSpec(
        resourceName: "paint_bucket_launcher",
        localFrontAxis: .negativeX,
        localUpAxis: .positiveY
    )

    /// Generated paint pistol (-X muzzle) — cloned for the dual off-hand.
    static let pistol = GeneratedModelSpec(
        resourceName: "paint_pistol",
        localFrontAxis: .negativeX,
        localUpAxis: .positiveY
    )

    /// Generated paint grenade — radially symmetric, no intrinsic front.
    static let grenade = GeneratedModelSpec(
        resourceName: "cartoon_paint_grenade",
        localFrontAxis: nil,
        localUpAxis: .positiveY
    )

    /// Generated sponge dive form — googly eyes on the front face (+Z).
    static let sponge = GeneratedModelSpec(
        resourceName: "cartoon_sponge_character",
        localFrontAxis: .positiveZ,
        localUpAxis: .positiveY
    )

    /// Rigged, textured body used as the hero's animatable model (the static
    /// base mesh carries no skeleton).
    static var heroBody: String? { heroIdle }
    /// Rigged, textured body used for rival bots.
    static var rivalBody: String? { rivalIdle }

    static let heroIdle: String? = "stylized_cartoon_urban_warrior_character-anim-idle"
    static let heroDraw: String? = "stylized_cartoon_urban_warrior_character-anim-cowboy-quick-draw-shooting"
    static let heroFire: String? = "stylized_cartoon_urban_warrior_character-anim-rifle-charge-inplace"
    static let heroJump: String? = "stylized_cartoon_urban_warrior_character-anim-regular-jump"
    static let heroRun: String? = "stylized_cartoon_urban_warrior_character-anim-run-fast-3-inplace"
    static let heroVictory: String? = "stylized_cartoon_urban_warrior_character-anim-victory"
    static let heroSplat: String? = "stylized_cartoon_urban_warrior_character-anim-shot-and-blown-back"
    static let heroThrow: String? = "stylized_cartoon_urban_warrior_character-anim-over-shoulder-throw"
    static let heroPlant: String? = "stylized_cartoon_urban_warrior_character-anim-female-crouch-pick-up-place-side"
    /// Weapon-ready standing pose (gun held in both hands near the body).
    static let heroArmedIdle: String? = "stylized_cartoon_urban_warrior_character-anim-combat-stance"
    /// Weapon-carrying run — same clip as the fire loop (rifle charge).
    static let heroArmedRun: String? = "stylized_cartoon_urban_warrior_character-anim-rifle-charge-inplace"
    static let heroHit: String? = "stylized_cartoon_urban_warrior_character-anim-hit-reaction"
    /// Dedicated wall-climb loop — the character clings and hauls itself up a
    /// painted wall (in-place clip, driven while the climb mechanic engages).
    static let heroClimb: String? = "stylized_cartoon_urban_warrior_character-anim-climb-left-with-both-limbs-inplace"
    static let heroInjuredRun: String? = "stylized_cartoon_urban_warrior_character-anim-injured-walk-inplace"
    static let heroInjuredIdle: String? = "stylized_cartoon_urban_warrior_character-anim-catching-breath"

    // MARK: Player skins

    /// Selectable player appearances — the classic look plus generated
    /// alternate outfits, all sharing the same body style/proportions so
    /// gameplay animations line up. Alt skins only ship a reduced clip set
    /// (idle/run/combat/jump/hit/victory/injured); missing weapon-specific
    /// one-shots (draw, roll, fling, throw, plant) simply no-op safely and
    /// fall back to the base pose.
    enum PlayerSkin: String, CaseIterable, Identifiable {
        case classic
        case corsair

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .classic: "Classique"
            case .corsair: "Corsaire Urbain"
            }
        }

        var spec: GeneratedModelSpec {
            switch self {
            case .classic: ModelCatalog.hero
            case .corsair: GeneratedModelSpec(
                    resourceName: "urban_paint_warrior",
                    localFrontAxis: .positiveZ,
                    localUpAxis: .positiveY
                )
            }
        }

        private var prefix: String? { spec.resourceName }

        /// Rigged, textured body for this skin — the idle clip doubles as the
        /// animatable base model since the static skin mesh has no skeleton.
        var bodyResource: String? { idleAnim }

        var idleAnim: String? { self == .classic ? ModelCatalog.heroIdle : prefix.map { "\($0)-anim-idle" } }
        var runAnim: String? { self == .classic ? ModelCatalog.heroRun : prefix.map { "\($0)-anim-run-fast-3-inplace" } }
        var jumpAnim: String? { self == .classic ? ModelCatalog.heroJump : prefix.map { "\($0)-anim-basic-jump" } }
        var armedIdleAnim: String? { self == .classic ? ModelCatalog.heroArmedIdle : prefix.map { "\($0)-anim-combat-stance" } }
        var victoryAnim: String? { self == .classic ? ModelCatalog.heroVictory : prefix.map { "\($0)-anim-victory" } }
        var hitAnim: String? { self == .classic ? ModelCatalog.heroHit : prefix.map { "\($0)-anim-hit-reaction" } }
        var injuredIdleAnim: String? { self == .classic ? ModelCatalog.heroInjuredIdle : prefix.map { "\($0)-anim-catching-breath" } }
        var injuredRunAnim: String? { self == .classic ? ModelCatalog.heroInjuredRun : prefix.map { "\($0)-anim-injured-walk-inplace" } }
    }

    static let rivalIdle: String? = "cartoon_paint_warrior-anim-idle"
    static let rivalRun: String? = "cartoon_paint_warrior-anim-run-fast-3-inplace"
    static let rivalSplat: String? = "cartoon_paint_warrior-anim-shot-and-blown-back"
    static let rivalArmedIdle: String? = "cartoon_paint_warrior-anim-combat-stance"
    static let rivalHit: String? = "cartoon_paint_warrior-anim-hit-reaction"
    static let rivalInjuredRun: String? = "cartoon_paint_warrior-anim-injured-walk-inplace"
    static let rivalInjuredIdle: String? = "cartoon_paint_warrior-anim-catching-breath"
}
