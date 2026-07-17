import Observation
import RealityKit
import SwiftUI
import UIKit
import simd

/// Final numbers shown on the results screen.
struct MatchResult {
    let outcome: GameController.MatchOutcome
    /// The LOCAL player's team in this match — orange in solo/host games,
    /// purple for the duel guest. Drives the "Vous" colors on the results screen.
    let localTeam: Team
    /// Win-condition variant this match was played under — drives which
    /// score the results screen highlights.
    let mode: MatchMode
    /// Coverage share of the LOCAL player's team ("Vous").
    let orangePercent: Int
    /// Coverage share of the opposing team ("Rivaux").
    let purplePercent: Int
    /// Tiles covered by the player's team — feeds the lifetime profile stats.
    let paintedTiles: Int
    /// Final per-fighter statistics, sorted by kills — feeds the podium.
    let standings: [FighterStats]
    /// Duel Mortel: final team kill totals. Contrôle de Zones: final team
    /// zone score. Unused (0) in Guerre de Peinture.
    let orangeScore: Int
    let purpleScore: Int
}

/// One neutral capture point in the Contrôle de Zones mode: a crisp circle
/// outlined on the ground (ring + soft glow + translucent fill) with rising
/// light filaments around the edge and a real point light — everything tints
/// to the color of whichever team currently stands in it (white while empty,
/// golden while contested). Purely visual state lives here; occupancy and
/// scoring live on `GameController`.
@MainActor
final class CaptureZoneVisual {
    let center: SIMD3<Float>
    /// Horizontal scoring radius of THIS zone — per-zone because maps use
    /// different layouts (wide ground circles on Nexus, a tighter ring on
    /// the Temple Lost pyramid top).
    let radius: Float
    let disc: ModelEntity
    let ring: ModelEntity
    let glow: ModelEntity
    let light: PointLight
    let spinner: Entity
    let filaments: [ModelEntity]
    /// Last visual state applied by the recolor pass — 0 empty, 1 orange,
    /// 2 purple, 3 contested, -1 never painted. Tracked separately from
    /// `zoneControllers` so contested → empty transitions repaint too
    /// (both map to a nil controller).
    var appliedState: Int = -1

    init(
        center: SIMD3<Float>,
        radius: Float,
        disc: ModelEntity,
        ring: ModelEntity,
        glow: ModelEntity,
        light: PointLight,
        spinner: Entity,
        filaments: [ModelEntity]
    ) {
        self.center = center
        self.radius = radius
        self.disc = disc
        self.ring = ring
        self.glow = glow
        self.light = light
        self.spinner = spinner
        self.filaments = filaments
    }
}

/// Owns the RealityKit scene, the per-frame simulation, player input,
/// bot AI, ink projectiles, and the HUD-visible match state.
@MainActor
@Observable
final class GameController {
    enum MatchOutcome {
        case win, lose, draw
    }

    // MARK: - HUD state

    var timeRemaining: Double = GameConfig.matchDuration
    /// Exact match clock — the published `timeRemaining` only updates when
    /// the displayed second changes, so the HUD never re-renders per frame.
    @ObservationIgnored var timeLeftExact: Double = GameConfig.matchDuration
    var inkLevel: Float = GameConfig.maxInk
    /// Exact ink tank — the published `inkLevel` is quantized to 2-unit
    /// steps so the gauge never forces a HUD re-render every frame.
    @ObservationIgnored var inkExact: Float = GameConfig.maxInk
    var playerHP: Int = GameConfig.playerMaxHP
    var isPlayerDown = false
    var respawnCountdown: Double = 0
    var isMatchOver = false
    var banner: String?
    /// Stylish one-shot splat notification — shown when the player either
    /// scores or falls victim to an elimination. The highlighted name always
    /// gets the red-outline treatment regardless of who threw the shot.
    struct SplatEvent: Identifiable, Equatable {
        let id = UUID()
        let headline: String
        let name: String
        let isPlayerVictim: Bool
    }
    var splatEvent: SplatEvent?
    var splatEventTask: Task<Void, Never>?
    /// Live alive/dead status of each rival — drives the top-center HUD row.
    struct EnemyStatus: Identifiable, Equatable {
        let id: Int
        let name: String
        var isAlive: Bool
    }
    var enemyStatuses: [EnemyStatus] = []
    /// Incremented every time the player takes a hit — pulses the damage
    /// vignette (paint creeping in from the screen edges).
    var damagePulse: Int = 0
    /// True while the HUD reposition mode is active — toggled from Settings.
    var isHUDEditMode = false
    /// HUD button offsets captured the instant reposition mode is entered —
    /// lets "ANNULER" restore the exact layout the player had before, even
    /// though drags write straight to the persisted profile as they happen.
    var hudEditSnapshot: [String: CGSize]?
    var isDiving = false
    /// True while the player is holding the dive button and has slid onto the
    /// jump button, charging the squid-surge jump. The charge is driven by the
    /// simulation timer; when it reaches `diveJumpChargeDuration`, the player
    /// automatically pops out of the ink with a boosted jump.
    var isDivingAndChargingJump = false
    /// Current charge of the squid-surge jump in seconds (0...diveJumpChargeDuration).
    /// Exact value used for the in-world sponge pulse — updated every frame
    /// without publishing, so it never forces a HUD re-render on its own.
    @ObservationIgnored var diveJumpCharge: Double = 0
    /// Same charge, quantized to ~20 steps and published — drives the visible
    /// charging ring on the sponge/dive button.
    var diveJumpChargeRatio: Double = 0
    /// Duration the player must hold the dive-jump pose before the auto-jump fires.
    let diveJumpChargeDuration: Double = 0.125
    var grenadeCooldown: Double = 0
    /// Exact cooldown — the published value only moves in 0.1 s steps.
    @ObservationIgnored var grenadeCooldownExact: Double = 0
    var isAirborne = false
    /// True while the player is actively scaling a painted wall — drives the
    /// dedicated climb animation loop.
    var isClimbing = false
    /// True while the predicted impact point sits on an enemy — the HUD
    /// reticle shrinks and recolors to confirm the shot will connect.
    var isAimOnTarget = false
    /// Live per-fighter match statistics (player first) — published at a
    /// few Hz so the scoreboard and top-3 panel never re-render every frame.
    var stats: [FighterStats] = []
    /// Full-screen render viewport size, reported by the HUD layer.
    var viewportSize: CGSize = .zero
    /// Currently equipped weapon — selected in the loadout screen, swappable
    /// while waiting to respawn.
    var weapon: WeaponType
    /// Charger charge gauge (0...1) — fills while the fire button is held.
    var chargeLevel: Float = 0
    /// Machine-gun heat gauge (0...1) — fills while firing, cools otherwise.
    var heatLevel: Float = 0
    /// True while the machine gun is locked out after overheating.
    var isOverheated = false
    @ObservationIgnored var heatExact: Float = 0
    /// Active camera perspective — toggleable in the HUD, persisted in the profile.
    var cameraMode: CameraMode
    /// True for the sandbox weapon range (ENTRAÎNEMENT): no bots, no timer,
    /// weapon switch always available, mannequins + moving targets instead
    /// of the real combat maps.
    @ObservationIgnored let isTraining: Bool

    init(weapon: WeaponType = .blaster, training: Bool = false) {
        self.weapon = weapon
        self.isTraining = training
        self.cameraMode = ProfileStore.shared.cameraMode
        GameConfig.isTrainingSession = training
    }

    // MARK: - Input

    var joystick: SIMD2<Float> = .zero
    /// Direction fed by the sponge (dive) joystick — lets the player swim
    /// and steer with the same held finger.
    var diveStick: SIMD2<Float> = .zero
    var isFiring = false

    var onMatchEnd: ((MatchResult) -> Void)?
    /// Fired when the player voluntarily quits a live match from Settings —
    /// distinct from `onMatchEnd`: skips the results sequence entirely and
    /// sends the caller straight back to the Hub.
    var onQuit: (() -> Void)?

    // MARK: - Scene

    var worldRoot: Entity?
    var camera: PerspectiveCamera?
    var grid: PaintGrid?
    /// Texture-backed material set for the arena (loaded once at setup).
    @ObservationIgnored var mats: ArenaMaterials?
    var updateSubscription: EventSubscription?
    /// Published once the whole arena (models, bots, grid) is built — the
    /// loading overlay waits on this before starting its countdown.
    var isSceneReady = false
    /// True once the intro countdown finished: the clock ticks, the bots
    /// fight, and the player controls come alive. Before that the scene
    /// only idles behind the loading overlay.
    var isMatchLive = false

    var playerContainer: Entity?
    var heroAnimator: GeneratedModelAnimationPlayer?
    var heroActiveLoop: String?
    var heroRuntime: Entity?
    var weaponSocket: Entity?
    /// Second pistol socket of the dual-wield loadout — mirrors the main hand.
    var offhandSocket: Entity?
    /// Red targeting laser of the Sniper — visible to everyone while charging.
    var laserBeam: ModelEntity?
    var laserDot: ModelEntity?
    var muzzleEntity: Entity?
    var muzzleFlash: ModelEntity?
    var flashUntil: Double = 0
    var weaponRecoil: Float = 0
    var weaponRestPosition: SIMD3<Float> = .zero
    /// Live tracker of the hero's animated hand joint — the weapon socket
    /// follows it every frame so the weapon moves with the animations.
    let heroHandTracker = HandJointTracker()
    var weaponFollowPosition: SIMD3<Float> = GameConfig.weaponSocketPosition
    var verticalVelocity: Float = 0
    var diveFormEntity: Entity?
    var respawnTimer: Double = 0
    var fireTimer: Double = 0
    var cameraYaw: Float = -.pi / 2
    var cameraPitch: Float = 0.02
    /// Damped aim targets — finger deltas and the auto-follow steer these,
    /// and the live camera angles ease toward them every frame.
    var targetCameraYaw: Float = -.pi / 2
    var targetCameraPitch: Float = 0.02
    /// True while the auto-follow is actively steering behind the run.
    var isAutoAligning = false
    /// Smoothed live field of view — narrows during the Long-Shot charge.
    var currentFieldOfView: Float = GameConfig.cameraFieldOfView
    /// Halves the cost of the ballistic aim-lock prediction (30 Hz).
    var crosshairFrameToggle = false
    /// Screen-center aim ray, refreshed by the camera update every frame.
    /// Firing converges projectiles onto whatever this ray hits, so the
    /// fixed center reticle is always honest.
    @ObservationIgnored var aimRayOrigin: SIMD3<Float> = .zero
    @ObservationIgnored var aimRayDirection: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    /// Distance to skip along the ray so the camera-to-player gap (and the
    /// player's own body) never registers as an aim target.
    @ObservationIgnored var aimRaySkip: Float = 0
    /// Damped camera pivot — follows the character with framerate-independent
    /// smoothing so pure rotation never produces positional judder.
    @ObservationIgnored var smoothedPivot: SIMD3<Float>?
    /// Smoothed camera boom length — collision shortening eases instead of
    /// popping between discrete obstacle-sampling steps.
    @ObservationIgnored var cameraArm: Float = GameConfig.cameraDistance
    /// Accumulated time for the real FPS governor (30/60/120 setting).
    @ObservationIgnored var frameCarry: Float = 0
    /// Accumulated time for the name-tag billboard refresh — recalculated at
    /// ~14 Hz instead of every frame (imperceptible, frees CPU).
    @ObservationIgnored var nameTagAccum: Float = 0
    /// Seconds between name-tag billboard refreshes.
    @ObservationIgnored let nameTagInterval: Float = 1.0 / 14.0
    /// Rolling frame index used to stagger bot AI “thinking” across frames so
    /// they don't all evaluate targets in the same image.
    @ObservationIgnored var botThinkFrame = 0
    /// Native refresh ceiling of the display, cached once.
    @ObservationIgnored let displayMaxFPS = UIScreen.main.maximumFramesPerSecond
    /// Active graphics preset for this match — frozen at setup from the
    /// player's Settings choice (auto-detected or manual), then possibly
    /// stepped down once at runtime if the framerate sags (never upgraded
    /// mid-match). Every performance-sensitive subsystem reads
    /// `qualitySettings`, derived from this, instead of its own thresholds.
    @ObservationIgnored var activeQuality: GraphicsQuality = .standard
    @ObservationIgnored var qualitySettings: QualitySettings = .settings(for: .standard)
    /// Rolling average frame time (seconds), used only to detect a sustained
    /// framerate drop for the runtime auto-downgrade.
    @ObservationIgnored var frameTimeAccum: Float = 0
    @ObservationIgnored var frameTimeSampleCount: Int = 0
    /// Seconds spent under the 45 FPS threshold since the last reset —
    /// crossing 2s triggers one auto-downgrade.
    @ObservationIgnored var sustainedSlowTime: Float = 0
    /// Cooldown between runtime auto-downgrade steps — the preset can now
    /// step down repeatedly (all the way to Lite) on a genuinely struggling
    /// device, but never more than once per cooldown window so it doesn't
    /// chase transient hitches.
    @ObservationIgnored var autoDowngradeCooldown: Float = 0
    /// Brief on-screen notice when the runtime auto-downgrade fires.
    var qualityDowngradeNotice: String?
    @ObservationIgnored var qualityNoticeTimer: Float = 0
    /// Accumulated time since the last paint-chunk mesh rebuild flush —
    /// throttled by `qualitySettings.paintRebuildInterval` instead of
    /// rebuilding every single frame.
    @ObservationIgnored var paintFlushAccum: Float = 0
    @ObservationIgnored var projectileCap = GameConfig.maxLiveProjectiles
    var wasFiring = false
    var lastDamageTime: Double = -10
    var hpRegenTick: Double = 0
    /// Remaining cooldown before the player's next hit-flinch animation.
    var playerFlinchTimer: Double = 0
    var fireStanceStart: Double = -10
    var lastManualAimTime: Double = -10
    var sprayCone: ModelEntity?
    var chargeConsumed = false
    var lastFlingTime: Double = -10
    /// Smoothed weapon socket scale.
    var weaponFollowScale: Float = 1
    var grenadeTemplate: Entity?

    // MARK: Gadget & gear perks

    /// Gadget equipped in the Armurerie — drives the grenade-button slot.
    let gadget: GadgetType = MetaStore.shared.equippedGadget
    /// Utility modifiers from the equipped gear set, frozen at match start.
    @ObservationIgnored let perks = MetaStore.shared.perkModifiers
    /// Bot skill tier chosen on the match preparation screen, frozen for the
    /// whole match — every AI fighter (allies + rivals) shares this tier.
    @ObservationIgnored let botDifficulty: BotDifficulty = ProfileStore.shared.botDifficulty
    /// Win-condition variant chosen on the match preparation screen, frozen
    /// for the whole match.
    @ObservationIgnored let matchMode: MatchMode = GameConfig.currentMode

    // MARK: Grenade aiming

    /// True while the grenade button/key is held: the grenade sits in the
    /// hand and the predicted trajectory + landing zone are shown live.
    var isAimingGrenade = false
    var grenadeAimRoot: Entity?
    var grenadeArcDots: [ModelEntity] = []
    var grenadeLandingDisc: ModelEntity?
    /// Grenade visual carried in the animated hand while aiming/throwing.
    var handGrenade: Entity?

    // MARK: Desktop input

    /// Hardware keyboard/mouse bridge for desktop testing in the simulator.
    let desktopInput = DesktopInputMonitor()
    var isKeyboardConnected = false

    // MARK: Local duel (multipeer)

    /// Shared peer-to-peer session — active only in the « Duel local » mode.
    @ObservationIgnored let localMatch = LocalMatchService.shared
    /// True when this match is a device-to-device duel — 1v1, plus optional
    /// host-simulated AI bots on each team (Partie personnalisée).
    @ObservationIgnored var isLocalDuel = false
    /// Team of the LOCAL player — orange for solo play and the duel host,
    /// purple for the duel guest. Derived once from the network role; every
    /// gameplay path uses this instead of assuming orange.
    var localTeam: Team = .orange
    /// The opposing team — the remote player's team in a duel.
    var enemyTeam: Team { localTeam.opponent }
    /// Network-driven puppet of the remote player (always `enemyTeam`).
    @ObservationIgnored var remoteBot: BotAgent?
    @ObservationIgnored var netStateTimer: Double = 0
    /// Host → guest AI-bot state broadcast cadence (duel with bots).
    @ObservationIgnored var duelBotNetTimer: Double = 0
    /// Newest applied `botState` sequence — drops out-of-order batches.
    @ObservationIgnored var lastBotStateSeq: UInt32 = 0

    /// One timestamped pose from the peer's state stream. Buffered (not
    /// applied directly) so the puppet can render slightly in the past and
    /// interpolate between the two bracketing snapshots (step 5).
    struct RemoteSnapshot {
        var time: TimeInterval
        var position: SIMD3<Float>
        var yaw: Float
        var velocity: SIMD3<Float>
    }

    /// Interpolated pose produced each frame from the snapshot buffer.
    struct RemotePose {
        var position: SIMD3<Float>
        var yaw: Float
    }

    /// Snapshot buffer, ordered by sender timestamp (envelope clock).
    @ObservationIgnored var remoteSnapshots: [RemoteSnapshot] = []
    /// Sender-clock instant currently rendered for the puppet — advances
    /// with the local frame clock, gently re-synced toward
    /// `newest - remoteInterpDelay`. Negative = not initialised.
    @ObservationIgnored var remoteRenderTime: TimeInterval = -1
    /// The puppet renders this far behind the newest snapshot — enough for
    /// 2-3 snapshots at 24 Hz to bracket the render cursor on real Wi-Fi.
    static let remoteInterpDelay: TimeInterval = 0.12
    /// Velocity extrapolation cap when the buffer runs dry (packet loss).
    static let remoteExtrapolationCap: TimeInterval = 0.1

    @ObservationIgnored var remoteIsMoving = false
    @ObservationIgnored var remoteIsRolling = false
    @ObservationIgnored var lastRemoteRollerXZ: SIMD2<Float>?
    /// Highest state-snapshot sequence number applied so far — anything
    /// older is dropped (out-of-order protection for the future unreliable
    /// channel).
    @ObservationIgnored var lastRemoteStateSeq: UInt32 = 0
    /// Last streamed position + send time, used to derive the velocity
    /// carried in each state snapshot (receiver-side extrapolation, step 5).
    @ObservationIgnored var lastNetSentPosition: SIMD3<Float>?
    @ObservationIgnored var lastNetSentAt: Double = -1
    /// Paint primitives applied locally since the last flush — shipped in
    /// batches so the peer's grid converges on the exact same ownership
    /// (host authority, step 4).
    @ObservationIgnored var pendingPaintOps: [NetPaintOp] = []
    @ObservationIgnored var netPaintFlushTimer: Double = 0
    /// Host-side authority broadcaster (coverage + clock) — nil on the guest
    /// and in solo play.
    @ObservationIgnored var matchAuthority: MatchAuthority?
    /// Latest authoritative coverage received from the host (guest only) —
    /// the HUD displays these instead of the local grid's drifting counters.
    @ObservationIgnored var hostCoverage: (orange: Int, purple: Int, total: Int)?

    // MARK: Name tags

    var playerNameTag: Entity?
    let allyBotNames = ["Nino", "Maya"]
    let rivalBotNames = ["Kraze", "Volt", "Zola"]

    struct PlantedBomb {
        let entity: Entity
        let detonateAt: Double
        let team: Team
    }

    var plantedBombs: [PlantedBomb] = []

    var bots: [BotAgent] = []

    enum ProjectileKind {
        case drop, grenade
    }

    struct Projectile {
        let entity: Entity
        var velocity: SIMD3<Float>
        let team: Team
        let kind: ProjectileKind
        let gravity: Float
        let damage: Int
        let paintRadius: Float
        /// Stats row of the fighter who fired this drop (0 = player).
        let ownerIndex: Int
        /// Absolute detonation time for grenades — fixed fuse, never impact.
        var detonateAt: Double = 0
        /// Splash-damage radius applied on landing (bucket blobs). 0 = none.
        var splashRange: Float = 0
        /// Horizontal hit-cylinder radius used for direct in-flight hits —
        /// defaults to the character's own radius, widened for big blobs
        /// (bucket) so the visual size and the hit check actually match.
        var hitRadius: Float = GameConfig.characterHitRadius
    }

    /// Axis-aligned blocker used for movement collision and projectile hits.
    /// Walkable blockers (platforms) can be stood on when reached via ramps.
    struct Obstacle {
        let center: SIMD3<Float>
        let halfX: Float
        let halfZ: Float
        let baseY: Float
        let topY: Float
        let isWalkable: Bool
        /// Team allowed to pass through and shoot through this blocker — used
        /// by the gadget shield wall, which is solid to the enemy but fully
        /// transparent (movement + projectiles) to its owner's team. nil =
        /// blocks everyone.
        var passThroughTeam: Team? = nil
        /// Cosmetic splat decal count for obstacles OUTSIDE the climbable
        /// wall system (cabin walls, paint cans, shield walls, low steps) —
        /// `paintObstacleFace` uses this so paint always visibly sticks even
        /// on surfaces that never register a `ClimbWall`.
        var decalCount: Int = 0
    }

    /// Axis-aligned sloped surface connecting two heights.
    struct Ramp {
        let center: SIMD2<Float>
        let axis: SIMD2<Float>
        let halfLength: Float
        let halfWidth: Float
        let lowY: Float
        let highY: Float
    }

    /// Rectangular water pool — impassable, unpaintable; falling in sends
    /// the character back to the last dry ground it touched.
    struct WaterZone {
        let center: SIMD2<Float>
        let halfX: Float
        let halfZ: Float
    }

    /// Overhead cable between two high points — bidirectional, ridden at
    /// `GameConfig.ziplineSpeed`; weapons stay usable during the ride.
    struct Zipline {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
    }

    /// Vertical paintable surface (axis-aligned box sides): once a team
    /// covers it in ink it becomes climbable for that team — pushing into it
    /// slides the character up to the walkable top. EVERY mid-height
    /// structure (platforms, blocks, containers, dedicated walls) registers
    /// one, so any wall can be painted and climbed.
    struct ClimbWall {
        let center: SIMD2<Float>
        let halfX: Float
        let halfZ: Float
        let topY: Float
    }

    // MARK: SplashCheese interactive zones
    // These four zone kinds only ever get populated on the SplashCheese map;
    // every other arena leaves the arrays empty, so the per-frame checks are
    // no-ops there and the two existing arenas are unaffected.

    /// Cheese-block trampoline: stepping onto it launches the character
    /// straight up at `launch` m/s. `topY` is absolute (pads can sit on
    /// elevated terrain).
    struct BouncePad {
        let center: SIMD2<Float>
        let halfX: Float
        let halfZ: Float
        let topY: Float
        let launch: Float
    }

    /// Floor-fan updraft column: while inside the footprint and below
    /// `topY`, the character is lifted; leaving it lets them glide back down.
    struct AirVent {
        let center: SIMD2<Float>
        let halfX: Float
        let halfZ: Float
        let topY: Float
    }

    /// Conveyor belt: slides a grounded rider along `direction` at `speed`.
    struct Conveyor {
        let center: SIMD2<Float>
        let halfX: Float
        let halfZ: Float
        let surfaceY: Float
        let direction: SIMD2<Float>
        let speed: Float
    }

    var projectiles: [Projectile] = []
    /// Reusable `.drop` entities parented ONCE to `worldRoot` and toggled via
    /// `isEnabled` instead of created/destroyed per shot. A sustained jet
    /// spawns ~50 drops/s; recycling from this pool removes the scene-graph
    /// add/remove churn that was a steady combat CPU spike.
    @ObservationIgnored var dropPool: [ModelEntity] = []
    let dropMesh = MeshResource.generateSphere(radius: 0.12)
    let grenadeMesh = MeshResource.generateSphere(radius: 0.21)
    var projectileMaterials: [Team: UnlitMaterial] = [:]
    /// Cached VFX sphere meshes — generated once and reused so a grenade
    /// splash / kill explosion never allocates a fresh `generateSphere`
    /// (~760 tris each) on the hot path.
    @ObservationIgnored let burstMesh = MeshResource.generateSphere(radius: 0.4)
    @ObservationIgnored let killRingMesh = MeshResource.generateSphere(radius: 0.35)
    @ObservationIgnored let killPlumeMesh = MeshResource.generateSphere(radius: 0.3)
    @ObservationIgnored let killFlashMesh = MeshResource.generateSphere(radius: 0.7)
    /// Hit-feedback VFX meshes and materials, built once — a continuous jet
    /// lands several hits per second, so the per-hit `generateSphere` +
    /// fresh-material allocations were a steady hot-path cost.
    @ObservationIgnored let hitSplashMesh = MeshResource.generateSphere(radius: 0.16)
    @ObservationIgnored let hitPuffMesh = MeshResource.generateSphere(radius: 0.14)
    @ObservationIgnored let hitFlashMesh = MeshResource.generateSphere(radius: GameConfig.characterHitRadius * 0.9)
    @ObservationIgnored let hitPuffMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        m.blending = .transparent(opacity: 0.45)
        return m
    }()
    @ObservationIgnored let hitFlashMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: UIColor(white: 1, alpha: 1))
        m.blending = .transparent(opacity: 0.85)
        return m
    }()
    /// Live transient VFX groups (hit splashes, bursts, kill explosions) —
    /// gated by `qualitySettings.transientVFXBudget` so a chaotic fight can
    /// never snowball entity churn.
    @ObservationIgnored var liveTransientVFX = 0
    /// Shared white flash material for kill explosions — reused every kill.
    @ObservationIgnored let killFlashMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: UIColor(white: 1, alpha: 1))
        m.blending = .transparent(opacity: 0.8)
        return m
    }()

    // MARK: - Shield-wall (ink wall) cache
    /// Cached shield-wall meshes + materials. A shield only ever has two
    /// footprints (thin along X or thin along Z) and two looks (ally pane /
    /// enemy filament), so we build them once and reuse them on every cast —
    /// no `generateBox`/material allocation on the gadget hot path (same idea
    /// as `burstMesh` / `projectileMaterials`). Keyed by `alongX`.
    @ObservationIgnored var inkWallPaneMesh: [Bool: MeshResource] = [:]
    @ObservationIgnored var inkWallPaneMaterial: PhysicallyBasedMaterial?
    @ObservationIgnored var inkWallFilamentMaterial: PhysicallyBasedMaterial?
    /// Vertical corner bar is identical for both orientations.
    @ObservationIgnored var inkWallVerticalBar: MeshResource?
    /// Horizontal edge bars along X / along Z, keyed by orientation (`alongX`).
    @ObservationIgnored var inkWallBarAlongX: [Bool: MeshResource] = [:]
    @ObservationIgnored var inkWallBarAlongZ: [Bool: MeshResource] = [:]

    // MARK: - Paint performance debug
    /// Live paint batching stats, published for the debug overlay. Only
    /// refreshed while `GameConfig.paintPerfDebug` is on.
    var paintPerfStats: PaintPerfStats?
    /// Throttles the debug console log to ~2 Hz.
    @ObservationIgnored var lastPaintPerfLog: Double = 0

    var obstacles: [Obstacle] = []
    /// Walkable subset of `obstacles`, precomputed so the per-frame height
    /// queries never scan the full blocker list.
    var walkableObstacles: [Obstacle] = []
    /// Uniform XZ broadphase grid over `obstacles` / `ramps`, rebuilt on every
    /// mutation. nil in training (obstacles move each frame) — queries then
    /// fall back to their legacy linear scans.
    @ObservationIgnored var obstacleGrid: ObstacleGrid?
    var ramps: [Ramp] = []
    var waterZones: [WaterZone] = []
    var ziplines: [Zipline] = []
    var climbWalls: [ClimbWall] = []
    /// SplashCheese interactive zones (empty on every other map).
    var bouncePads: [BouncePad] = []
    var airVents: [AirVent] = []
    var conveyors: [Conveyor] = []
    // MARK: Training range (ENTRAÎNEMENT only)

    /// One oscillating target dummy: `obstacleIndex` points into `obstacles`
    /// so projectile hits stay accurate as it slides back and forth.
    struct TrainingTarget {
        let entity: Entity
        let obstacleIndex: Int
        let baseCenter: SIMD3<Float>
        let axis: SIMD3<Float>
        let amplitude: Float
        let speed: Float
        let phase: Float
    }
    var trainingTargets: [TrainingTarget] = []

    /// Entities spun every frame (fan blades) for ambient life.
    @ObservationIgnored var cheeseSpinners: [Entity] = []
    /// Entities gently pulsed every frame (tunnel mouths, vent rings).
    @ObservationIgnored var cheesePulsers: [Entity] = []
    /// Throttles the air-vent whoosh SFX.
    @ObservationIgnored var lastVentSfx: Double = -10
    /// True while the player was inside a water pool last frame (splash SFX edge).
    @ObservationIgnored var wasInWater = false
    /// Active zipline ride: cable index, progress (0...1), travel direction.
    var ziplineRide: (index: Int, t: Float, forward: Bool)?
    /// Last solid, dry ground position — the water-dunk return point.
    @ObservationIgnored var lastSafeGround: SIMD3<Float> = .zero
    /// Center of each team's protected spawn bubble.
    var spawnZoneCenters: [Team: SIMD3<Float>] = [:]

    // MARK: Bot navigation

    /// Static ground-level walkability grid built once per match — bots A*
    /// their routes over it so they go around walls, water and platforms
    /// instead of pushing straight lines into geometry.
    @ObservationIgnored var botNav: BotNavGrid?
    /// High-clearance "points of interest" per arena — the default patrol
    /// destinations bots roam between, giving them believable routes.
    @ObservationIgnored var botPatrolPoints: [SIMD3<Float>] = []
    /// Reusable A* scratch buffers (see `findBotPath`) — sized once per match
    /// and reused across every call, with a generation stamp instead of a
    /// full reset each time.
    @ObservationIgnored var pathfindGScore: [Float] = []
    @ObservationIgnored var pathfindCameFrom: [Int] = []
    @ObservationIgnored var pathfindVisitGen: [Int32] = []
    @ObservationIgnored var pathfindGeneration: Int32 = 0
    /// Per-fighter velocity estimates (statsIndex → m/s, player = 0) — feeds
    /// target-leading so harder bots shoot where you're GOING, not where you
    /// are.
    @ObservationIgnored var fighterVelocities: [Int: SIMD3<Float>] = [:]
    @ObservationIgnored var fighterLastPositions: [Int: SIMD3<Float>] = [:]

    // MARK: Contrôle de Zones

    /// The two neutral capture points, built only in `.zoneControl` matches.
    @ObservationIgnored var captureZoneVisuals: [CaptureZoneVisual] = []
    /// Live team totals, published for the HUD (throttled like coverage).
    var zoneScoreOrange: Int = 0
    var zoneScorePurple: Int = 0
    /// Who currently controls each zone (index-aligned with
    /// `captureZoneVisuals`) — nil while neutral or contested. Drives the
    /// small HUD indicator dots.
    var zoneControllers: [Team?] = []
    /// Scripted multi-leg climbing routes toward ELEVATED capture zones
    /// (Temple Lost pyramid summit). The bot nav grid is ground-level only —
    /// platforms and raised ramps read as walls — so bots follow these
    /// waypoint chains (ramp entry → base deck → shrine ramp → summit) to
    /// physically walk up. Empty on maps whose zones sit on the ground.
    @ObservationIgnored var zoneClimbRoutes: [[SIMD3<Float>]] = []
    /// Exact, unquantized running totals — `zoneScoreOrange`/`zoneScorePurple`
    /// only publish the rounded-down value so the HUD doesn't re-render
    /// every frame.
    @ObservationIgnored var zoneScoreExactOrange: Double = 0
    @ObservationIgnored var zoneScoreExactPurple: Double = 0
    /// Non-published working copy of the match statistics.
    @ObservationIgnored var liveStats: [FighterStats] = []
    /// Stats indices of everyone who damaged the player since last spawn.
    @ObservationIgnored var playerRecentAttackers: Set<Int> = []

    var coverageTimer: Double = 0
    /// Guest-only: waiting for the host's authoritative end-of-match score.
    @ObservationIgnored var awaitingHostResult = false
    /// Ensures the final result is built exactly once per match.
    @ObservationIgnored var hasPublishedResult = false
    var bannerTask: Task<Void, Never>?
    var elapsed: Double = 0
    var lastSplatSfx: Double = 0
    var lastJetSfx: Double = 0

    /// The local player's base — left side for orange, right side for the
    /// duel guest (purple). Both devices share ONE world frame: the left
    /// base always belongs to orange, the right base to purple.
    var playerHome: SIMD3<Float> {
        let x = GameConfig.arenaWidth / 2 - 2.6
        return localTeam == .orange ? [-x, 0, 0] : [x, 0, 0]
    }

    /// The remote duel player's base — the opposite side of the arena.
    var remoteHome: SIMD3<Float> {
        let x = GameConfig.arenaWidth / 2 - 2.6
        return localTeam == .orange ? [x, 0, 0] : [-x, 0, 0]
    }

    /// World yaw looking toward the arena centre from a team's base.
    func baseFacing(for team: Team) -> Float {
        team == .orange ? .pi / 2 : -.pi / 2
    }

    var allyHomes: [SIMD3<Float>] {
        let x = -(GameConfig.arenaWidth / 2 - 2.6)
        return [[x, 0, -4.5], [x, 0, 4.5]]
    }

    var enemyHomes: [SIMD3<Float>] {
        let x = GameConfig.arenaWidth / 2 - 2.6
        return [[x, 0, -7], [x, 0, 0], [x, 0, 7]]
    }

    // MARK: - Map art direction

    /// Every structural helper (floor, platforms, ramps, blocks, cabins)
    /// pulls its texture through these accessors, so all arenas share the
    /// same geometry code with a completely different look.
    var isTempleMap: Bool { GameConfig.currentMap == .templeLost }

    var floorTextureName: String {
        switch GameConfig.currentMap {
        case .nexusDocks: ArenaMaterials.asphaltName
        case .templeLost: ArenaMaterials.templeFloorName
        }
    }
    var perimeterTextureName: String {
        switch GameConfig.currentMap {
        case .nexusDocks: ArenaMaterials.graffitiName
        case .templeLost: ArenaMaterials.templeWallName
        }
    }
    var platformTextureName: String {
        switch GameConfig.currentMap {
        case .nexusDocks: ArenaMaterials.towerName
        case .templeLost: ArenaMaterials.templeTechName
        }
    }
    var rampTextureName: String {
        switch GameConfig.currentMap {
        case .nexusDocks: ArenaMaterials.grateName
        case .templeLost: ArenaMaterials.templePlanksName
        }
    }
    var blockTextureName: String {
        switch GameConfig.currentMap {
        case .nexusDocks: ArenaMaterials.containerName
        case .templeLost: ArenaMaterials.templeWallName
        }
    }
    var skyTextureName: String {
        switch GameConfig.currentMap {
        case .nexusDocks: ArenaMaterials.skyName
        case .templeLost: ArenaMaterials.jungleSkyName
        }
    }
    var skylineTextureName: String {
        switch GameConfig.currentMap {
        case .nexusDocks: ArenaMaterials.skylineName
        case .templeLost: ArenaMaterials.jungleSkylineName
        }
    }

    // MARK: Per-map fallback / accent colors
    // Pulled through accessors so the shared builders (arena, water, lights,
    // sky) stay identical in structure while switching look per map.

    var floorFallbackColor: UIColor {
        switch GameConfig.currentMap {
        case .nexusDocks: UIColor(red: 0.8, green: 0.82, blue: 0.86, alpha: 1)
        case .templeLost: UIColor(red: 0.55, green: 0.62, blue: 0.5, alpha: 1)
        }
    }
    var floorTextureScale: SIMD2<Float> {
        switch GameConfig.currentMap {
        case .nexusDocks: [7, 4.5]
        case .templeLost: [9, 5.5]
        }
    }
    var apronTintColor: UIColor {
        switch GameConfig.currentMap {
        case .nexusDocks: UIColor(red: 1, green: 0.72, blue: 0.55, alpha: 1)
        case .templeLost: UIColor(red: 0.5, green: 0.85, blue: 0.55, alpha: 1)
        }
    }
    var apronFallbackColor: UIColor {
        switch GameConfig.currentMap {
        case .nexusDocks: UIColor(red: 0.62, green: 0.42, blue: 0.4, alpha: 1)
        case .templeLost: UIColor(red: 0.24, green: 0.45, blue: 0.28, alpha: 1)
        }
    }
    var wallFallbackColor: UIColor {
        switch GameConfig.currentMap {
        case .nexusDocks: UIColor(red: 0.35, green: 0.3, blue: 0.45, alpha: 1)
        case .templeLost: UIColor(red: 0.4, green: 0.48, blue: 0.36, alpha: 1)
        }
    }
    var waterColor: UIColor {
        switch GameConfig.currentMap {
        case .nexusDocks: UIColor(red: 0.16, green: 0.8, blue: 0.84, alpha: 1)
        case .templeLost: UIColor(red: 0.12, green: 0.75, blue: 0.62, alpha: 1)
        }
    }
    var sunLightColor: UIColor {
        switch GameConfig.currentMap {
        case .nexusDocks: UIColor(red: 1, green: 0.88, blue: 0.72, alpha: 1)
        case .templeLost: UIColor(red: 1, green: 0.95, blue: 0.78, alpha: 1)
        }
    }
    var fillLightColor: UIColor {
        switch GameConfig.currentMap {
        case .nexusDocks: UIColor(red: 0.85, green: 0.78, blue: 1, alpha: 1)
        case .templeLost: UIColor(red: 0.72, green: 1, blue: 0.85, alpha: 1)
        }
    }
    var fallbackSkyColor: UIColor {
        switch GameConfig.currentMap {
        case .nexusDocks: UIColor(red: 1, green: 0.55, blue: 0.32, alpha: 1)
        case .templeLost: UIColor(red: 0.45, green: 0.78, blue: 0.62, alpha: 1)
        }
    }


}
