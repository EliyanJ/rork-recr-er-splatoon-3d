import Foundation

/// Graphics detail level — lets lower-end devices trade visual richness for
/// a steadier framerate. Four tiers instead of a flat on/off: `ultra` keeps
/// everything maxed, `lite` strips everything non-essential for the oldest
/// supported hardware or a match that starts lagging.
enum GraphicsQuality: String, CaseIterable, Comparable {
    case ultra, standard, performance, lite

    /// Ordering used by `Comparable` and by the runtime auto-downgrade
    /// (never rendered directly).
    private var rank: Int {
        switch self {
        case .ultra: return 3
        case .standard: return 2
        case .performance: return 1
        case .lite: return 0
        }
    }

    static func < (lhs: GraphicsQuality, rhs: GraphicsQuality) -> Bool {
        lhs.rank < rhs.rank
    }

    var displayName: String {
        switch self {
        case .ultra: "Ultra"
        case .standard: "Standard"
        case .performance: "Performance"
        case .lite: "Lite"
        }
    }

    /// Short subtitle shown under each option in Settings.
    var subtitle: String {
        switch self {
        case .ultra: "Tout à fond (iPhone 15 Pro+)"
        case .standard: "Équilibré (recommandé)"
        case .performance: "Priorité fluidité"
        case .lite: "Minimal, maximum de FPS"
        }
    }

    /// One notch down, floored at `.lite` — used by the runtime
    /// auto-downgrade when the framerate sags mid-match.
    var oneStepDown: GraphicsQuality {
        switch self {
        case .ultra: return .standard
        case .standard: return .performance
        case .performance, .lite: return .lite
        }
    }
}

/// Every performance-relevant knob controlled by the active `GraphicsQuality`
/// preset. Computed once at match setup (and again on a runtime
/// auto-downgrade) from `GameController.activeQuality`, then consulted by
/// every subsystem that needs to scale its own cost instead of each one
/// re-deriving its own threshold.
struct QualitySettings {
    /// Cap on simultaneous live paint droplets — the most direct lever for
    /// keeping the per-frame projectile update bounded.
    let projectileCap: Int
    /// Multiplier applied to the secondary fill light's intensity. 0 drops
    /// the extra dynamic light entirely (fewer per-fragment light
    /// evaluations, no gameplay impact).
    let fillLightScale: Float
    /// Multiplier applied to the key sun light's intensity.
    let sunIntensityScale: Float
    /// Seconds between paint-grid chunk mesh rebuilds. Painting itself
    /// (ownership + coverage) always applies instantly; only the visual
    /// merge of dirty chunks into batched meshes is throttled.
    let paintRebuildInterval: Float
    /// Width/height of one paint chunk, in tiles. Bigger chunks mean fewer,
    /// larger rebuilds instead of many small ones.
    let paintChunkSize: Int
    /// Max number of (chunk, team) meshes rebuilt per paint flush. Caps the
    /// worst-case cost of a single flush (e.g. a grenade painting many chunks
    /// at once); leftover dirty slots roll to the next flush.
    let maxChunkRebuildsPerFlush: Int
    /// Fewer points on the generated ink-splash silhouette — a plainer but
    /// much cheaper shape for the lightest tiers.
    let simplifiedSplash: Bool
    /// Seconds between AI target-scan "thinks" per bot. Movement and
    /// following the current waypoint still run every frame; only the O(n)
    /// nearest-target scan is throttled.
    let botThinkInterval: Float
    /// Non-essential set dressing (trees, holo panels, extra props) skipped
    /// entirely at this tier.
    let decorEnabled: Bool
    let nameTagsEnabled: Bool
    /// Flat unlit color instead of the panoramic sky dome texture.
    let simplifiedSkybox: Bool
    let vfx: VFXLevel
    /// Cap on the DECORATIVE-only transient VFX layer (the drifting mist
    /// puff after a hit). The hit splash + hitmarker flash — the feedback
    /// the player actually needs to see — are never capped, on any preset;
    /// this budget only trims the purely cosmetic extra layer under load.
    let transientVFXBudget: Int

    /// How much impact/kill feedback VFX spawn per event.
    enum VFXLevel: Int {
        /// Splash + mist puff + hit-marker flash.
        case full
        /// Splash + flash only (no drifting mist puff).
        case reduced
        /// Splash only — no flash, no puff, no plume.
        case minimal
    }

    static func settings(for quality: GraphicsQuality) -> QualitySettings {
        switch quality {
        case .ultra:
            return QualitySettings(
                projectileCap: 120,
                fillLightScale: 1,
                sunIntensityScale: 1,
                paintRebuildInterval: 1.0 / 30,
                paintChunkSize: 8,
                maxChunkRebuildsPerFlush: 10,
                simplifiedSplash: false,
                botThinkInterval: 1.0 / 60,
                decorEnabled: true,
                nameTagsEnabled: true,
                simplifiedSkybox: false,
                vfx: .full,
                transientVFXBudget: 60
            )
        case .standard:
            return QualitySettings(
                projectileCap: 80,
                fillLightScale: 1,
                sunIntensityScale: 1,
                paintRebuildInterval: 1.0 / 20,
                paintChunkSize: 10,
                maxChunkRebuildsPerFlush: 8,
                simplifiedSplash: false,
                botThinkInterval: 1.0 / 30,
                decorEnabled: true,
                nameTagsEnabled: true,
                simplifiedSkybox: false,
                vfx: .full,
                transientVFXBudget: 45
            )
        case .performance:
            return QualitySettings(
                projectileCap: 50,
                fillLightScale: 0,
                sunIntensityScale: 1,
                paintRebuildInterval: 1.0 / 15,
                paintChunkSize: 12,
                maxChunkRebuildsPerFlush: 6,
                simplifiedSplash: true,
                botThinkInterval: 1.0 / 20,
                decorEnabled: false,
                nameTagsEnabled: true,
                simplifiedSkybox: false,
                vfx: .reduced,
                transientVFXBudget: 30
            )
        case .lite:
            return QualitySettings(
                projectileCap: 30,
                fillLightScale: 0,
                sunIntensityScale: 0.75,
                paintRebuildInterval: 1.0 / 10,
                paintChunkSize: 16,
                maxChunkRebuildsPerFlush: 4,
                simplifiedSplash: true,
                botThinkInterval: 1.0 / 15,
                decorEnabled: false,
                nameTagsEnabled: false,
                simplifiedSkybox: true,
                vfx: .minimal,
                transientVFXBudget: 20
            )
        }
    }
}
