import Foundation
import simd

/// Snapshot of the paint-rendering cost, surfaced by the debug overlay so the
/// batching win can be read live without Instruments or a physical device.
struct PaintPerfStats: Equatable {
    /// Merged chunk/team meshes currently drawn = real paint draw calls now.
    let activeEntities: Int
    /// Painted tiles = the draw calls the OLD one-entity-per-tile design used.
    let legacyDrawCalls: Int
}

/// Central tuning values for the turf-war match.
enum GameConfig {
    /// Debug flag: when true, the HUD shows a live paint-performance overlay
    /// (active paint draw calls vs the legacy per-tile count) and logs the
    /// same numbers to the console at ~2 Hz. Flip to `true` to compare the
    /// batched cost against the old design during a match.
    static var paintPerfDebug = false

    /// Arena selected for the next match — set from the loadout screen
    /// BEFORE the GameController is created, so every dimension-derived
    /// value (spawns, grid, walls) picks up the right footprint.
    static var currentMap: ArenaMap = .nexusDocks

    /// Win-condition variant for the next match — set from the match
    /// preparation screen BEFORE the GameController is created, same pattern
    /// as `currentMap`.
    static var currentMode: MatchMode = .turfWar

    /// Partie personnalisée: AI bots added to EACH team of a local duel
    /// (0 = pure 1v1). Chosen by the host lobby and synced to the guest
    /// through the `start` message BEFORE the GameController is created.
    static var duelBotsPerTeam: Int = 0

    /// True for the sandbox weapon range (ENTRAÎNEMENT) — swaps the arena
    /// dimensions for the small dedicated training footprint without
    /// touching any of the three real combat maps.
    static var isTrainingSession = false
    static let trainingArenaSize: Float = 36

    static var arenaWidth: Float { isTrainingSession ? trainingArenaSize : currentMap.width }
    static var arenaDepth: Float { isTrainingSession ? trainingArenaSize : currentMap.depth }
    static let tileSize: Float = 1.0

    static let matchDuration: Double = 240

    /// Normalized character height — doubled so characters read clearly on
    /// screen and interact convincingly with the environment.
    static let characterHeight: Float = 2.24
    /// Horizontal hit-cylinder radius for characters.
    static let characterHitRadius: Float = 0.8

    /// Fallback weapon socket in character-container space — chest/hand
    /// height of the 2.24 m character. Used only when no animated hand joint
    /// is trackable (hidden body in first person, unrigged fallback models).
    /// Shared by the player and every bot.
    static let weaponSocketPosition: SIMD3<Float> = [0.4, 1.48, 0.56]
    /// Offset from the tracked hand joint to the weapon's center, in
    /// character space — pushes the grip into the palm so the barrel sits
    /// naturally in front of the hand.
    static let weaponHandOffset: SIMD3<Float> = [0.02, 0.04, 0.26]
    /// Smoothing speed for the weapon following the animated hand — high
    /// enough to track the run bobbing, low enough to hide joint jitter.
    static let weaponFollowLerpSpeed: Float = 16
    /// Normalized weapon length along its front axis.
    static let weaponTargetSize: Float = 1.05

    /// Close over-the-shoulder camera: just above and behind the character's
    /// head, FPS-style framing showing the weapon and part of the body.
    static let cameraDistance: Float = 3.8
    static let cameraShoulderOffset: Float = 0.55
    static let cameraHeightOffset: Float = 0.35
    /// The camera never drops below this height above the character's feet.
    static let cameraMinHeight: Float = 0.5
    static let cameraFieldOfView: Float = 74
    static let cameraMinPitch: Float = -0.6
    static let cameraMaxPitch: Float = 0.55
    /// Eye height of the toggleable true first-person view.
    static let firstPersonEyeHeight: Float = 2.02

    /// Auto-follow: the camera smoothly steers behind the run direction with
    /// exponential damping — no notches, no snapping, framerate-independent.
    static let cameraAutoAlignResponse: Float = 1.7
    /// Auto-follow only engages once the run direction is at least this far
    /// from the current heading — small course corrections never move it.
    static let cameraAutoAlignThreshold: Float = .pi / 5
    /// Seconds after a manual camera drag before auto-follow kicks back in.
    static let cameraAutoAlignDelay: Double = 0.8
    /// Damping speed of the manual aim — finger/mouse deltas steer a target
    /// angle and the live camera eases toward it every frame.
    static let cameraAimSmoothing: Float = 15

    // MARK: Spawn protection

    /// Radius of each team's protected spawn bubble.
    static let spawnZoneRadius: Float = 7.5
    /// Clearance kept between a pushed-out intruder and the bubble edge.
    static let spawnZoneMargin: Float = 0.05

    /// Delay between pressing fire and the first paint drop — matches the
    /// weapon-draw animation so the character visibly raises the blaster.
    static let weaponDrawDelay: Double = 0.32

    static let playerSpeed: Float = 6.2
    static let botSpeed: Float = 5.0
    static let enemyCount: Int = 3
    static let allyCount: Int = 2

    /// Max ledge height a character can walk up without a ramp.
    static let stepUpHeight: Float = 0.8

    /// Jump physics — tuned so a jump clears the 1.5 m platforms.
    static let jumpVelocity: Float = 6.8
    static let gravity: Float = 13

    /// Walking multipliers depending on the paint under your feet.
    static let ownPaintWalkBoost: Float = 1.1
    static let enemyPaintPenalty: Float = 0.6

    /// Squid-dive multipliers (swim mode).
    static let swimBoost: Float = 1.8
    static let swimEnemyPaintPenalty: Float = 0.4
    static let swimNeutralPenalty: Float = 0.75

    static let maxInk: Float = 100
    static let inkRegenPerSecond: Float = 30
    static let swimInkRegenPerSecond: Float = 60

    // MARK: Charger (sniper)

    /// Seconds of holding fire to reach a full charge.
    static let chargerChargeDuration: Float = 1.15
    static let chargerMinInkCost: Float = 8
    /// A max-charge shot consumes more than half the ink tank.
    static let chargerMaxInkCost: Float = 55
    static let chargerMinSpeed: Float = 22
    static let chargerMaxSpeed: Float = 44
    /// Nearly straight-line ballistics for the charged sniper shot.
    static let chargerShotGravity: Float = 1.8
    static let chargerMinPaintRadius: Float = 0.8
    static let chargerMaxPaintRadius: Float = 1.9
    /// Minimum charge fraction required for the shot to leave at all.
    static let chargerMinCharge: Float = 0.12
    /// Optical zoom of the Long-Shot: the field of view narrows toward this
    /// value as the charge fills, then relaxes back after the shot.
    static let chargerZoomFieldOfView: Float = 26

    /// Damage of the charged sniper shot. RULE (never break it): at 50%
    /// charge or more, the shot must one-shot a standard target. The kill
    /// damage is derived from the target's CURRENT max HP instead of being
    /// a hardcoded number, so future HP balancing never breaks the rule.
    static func chargerDamage(charge: Float, targetMaxHP: Int) -> Int {
        if charge >= 0.5 { return targetMaxHP + 1 }
        return max(1, Int((Float(targetMaxHP) * charge * 1.7).rounded()))
    }

    // MARK: Machine gun (rapid)

    /// Heat added per fired tick — roughly 3.5 s of continuous fire before
    /// the gun overheats.
    static let rapidHeatPerShot: Float = 0.011
    /// Heat dissipated per second while not firing.
    static let rapidCoolPerSecond: Float = 0.55
    /// Once overheated, the gun stays locked until heat falls below this.
    static let rapidOverheatUnlockLevel: Float = 0.08

    // MARK: Bucket launcher

    /// Seconds between two bucket lobs — burst fire, never hold-to-spray.
    static let bucketFireInterval: Double = 1.0
    static let bucketInkCost: Float = 18
    /// Extra upward tilt of the lob so the blob flies in a high arc.
    static let bucketLobLift: Float = 0.55
    /// Characters within this range of the landing blob take splash damage.
    static let bucketSplashRange: Float = 2.3

    // MARK: Dual pistols

    /// Seconds between two staggered shot pairs.
    static let dualFireInterval: Double = 0.24
    /// Delay between the right-hand shot and the left-hand shot of a pair.
    static let dualStaggerDelay: Double = 0.09
    /// Horizontal offset of the off-hand pistol's muzzle.
    static let dualOffhandOffset: Float = 0.55

    // MARK: Sniper laser

    /// Thickness of the red targeting laser visible while charging.
    static let laserThickness: Float = 0.028

    // MARK: Feedback & audio

    /// The HUD reticle locks (shrinks + recolors) when the predicted impact
    /// point is within this range of an enemy.
    static let aimLockRadius: Float = 1.5
    /// Distance at which a positional sound fades to silence.
    static let audioFalloffDistance: Float = 34
    /// Hard cap on live paint droplets — keeps the per-frame projectile
    /// update bounded for a stable framerate.
    static let maxLiveProjectiles: Int = 240
    /// Blends the visible paint stream's origin from the animated hand's
    /// true (low) position toward eye height, so the jet appears to leave
    /// from roughly where the fixed center reticle is aiming instead of
    /// visibly below it. 0 = raw hand position, 1 = full eye height. Purely
    /// visual — the real flight direction still converges on the exact
    /// spot the reticle covers via `convergedAimDirection`.
    static let jetOriginEyeBlend: Float = 0.5
    /// Ground-splat radius credited to the killing team the instant a kill
    /// lands — wider than the in-combat hit splat so the kill VFX reads as
    /// a real payoff.
    static let killPaintRadius: Float = 2.6

    // MARK: Grenade

    /// Number of dots drawn along the predicted grenade arc while aiming.
    static let grenadeArcDotCount: Int = 16
    /// A predicted landing point closer than this to the player plants the
    /// grenade at the feet instead of throwing it.
    static let grenadePlantDistance: Float = 2.0

    static let grenadeInkCost: Float = 40
    static let grenadeCooldownDuration: Double = 5
    static let grenadeSpeed: Float = 10.5
    /// Fixed arming delay of a thrown grenade — it bounces and detonates
    /// after this constant time, NEVER on impact, so short and long throws
    /// behave identically.
    static let grenadeFuse: Double = 1.9
    /// Explosion zone radii, bumped +50% for a much punchier blast — both
    /// the ground paint coverage and the damage range grow together.
    static let grenadePaintRadius: Float = 5.1
    static let grenadeSplatRange: Float = 3.6
    /// Fuse of a grenade planted on the ground as a trap.
    static let plantedGrenadeFuse: Double = 2.4
    /// Normalized grenade size (its longest axis) — bigger and more visible
    /// in flight and in the hand.
    static let grenadeVisualSize: Float = 0.58

    // MARK: Gadgets

    /// Ink wall: footprint, lifetime and forward placement distance.
    static let inkWallWidth: Float = 3.6
    static let inkWallHeight: Float = 2.3
    static let inkWallThickness: Float = 0.35
    static let inkWallDuration: Double = 4.0
    /// Forward placement distance — the shield spawns clearly in front of the
    /// player so it acts as an advanced cover, never wrapped around them.
    static let inkWallDistance: Float = 3.2

    // MARK: Nexus Docks

    /// Riding speed along a zipline cable.
    static let ziplineSpeed: Float = 12
    /// Vertical drop from the cable down to the rider's feet.
    static let ziplineHangHeight: Float = 2.3
    /// Horizontal catch radius around a zipline endpoint.
    static let ziplineAttachRadius: Float = 2.4

    // MARK: Water (swimmable)

    /// Speed multiplier while wading through a water pool on foot — water
    /// is a slow, risky shortcut instead of a wall.
    static let waterWadeSpeedFactor: Float = 0.45
    /// Speed multiplier while crossing water in squid/dive form — swimming
    /// in your own ink is noticeably faster than wading.
    static let waterDiveSpeedFactor: Float = 0.75
    /// How deep the body sinks while crossing water (waist-deep look).
    static let waterSinkDepth: Float = -0.5

    // MARK: Wall-climb

    /// Upward slide speed on a wall — constant; every wall/base crate is
    /// climbable while in sponge form (walls are not paintable).
    static let wallClimbSpeed: Float = 3.4
    /// Horizontal reach from the wall face within which the climb engages.
    /// Generous so brushing a painted wall in sponge form is enough to grab it.
    static let wallClimbReach: Float = 1.6
    /// Minimum push toward the wall face (dot of move dir vs. inward normal)
    /// needed to engage the climb. Low = forgiving: barely leaning in grabs.
    static let wallClimbPushThreshold: Float = 0.12
    /// While climbing, horizontal input along the face is scaled by this factor
    /// so the fast upward slide doesn't fling the player sideways off the patch.
    /// Climb assist: lower = steadier, easier to control where you go up.
    static let wallClimbHorizontalAssist: Float = 0.34
    /// Once the contact point is within this distance of the wall's top, the
    /// climb keeps going even if the push-toward-wall dot check momentarily
    /// dips (thumbstick jitter near the ledge). Without this, a single frame
    /// of weak push right before mantling drops the climb, gravity kicks in
    /// for an instant, and the wall re-grabs next frame — read as the
    /// character vibrating right at the top of certain walls.
    static let wallClimbTopCommitDistance: Float = 0.5

    /// Bot durability — identical to the player's pool so fights feel fair
    /// and bots don't melt faster than the player. The sniper one-shot rule
    /// is charge-based and derives from this value, so it stays consistent.
    static let maxHP: Int = 10

    /// Player durability — generous pool plus out-of-combat regeneration so
    /// a single skirmish never feels like an instant death. Raised (+25%)
    /// together with the hit-flash and damage-vignette feedback.
    static let playerMaxHP: Int = 10
    static let grenadePlayerDamage: Int = 4
    /// Seconds without taking damage before HP starts regenerating.
    static let hpRegenDelay: Double = 3.0
    /// Seconds per regenerated HP point once regen has started.
    static let hpRegenInterval: Double = 1.0

    /// Minimum delay between two hit-flinch reactions on the same character.
    static let hitFlinchCooldown: Double = 0.35

    /// HP at or below which a bot switches to injured (near-death) animations.
    static let botLowHPThreshold: Int = 4
    /// HP at or below which the player switches to injured animations.
    static let playerLowHPThreshold: Int = 4

    static let respawnDelay: Double = 5.5

    /// Height of the floating name tag above a character's feet.
    static let nameTagHeight: Float = characterHeight + 0.42

    // MARK: Contrôle de Zones

    /// Horizontal radius of each capture zone's scoring footprint.
    static let zoneControlRadius: Float = 3.4
    /// Team score needed to win the match outright, before the clock runs out.
    static let zoneControlTargetScore: Double = 150
    /// Players of the same team inside a zone at or above this count score
    /// at the maximum rate — extra bodies past this add nothing more.
    static let zoneControlMaxScoringPlayers: Int = 2
    /// Points per second banked by a team holding a zone alone with at least
    /// `zoneControlMaxScoringPlayers` present. Deliberately slow so a match
    /// is a long tug-of-war, not a 30-second rush.
    static let zoneControlMaxRatePerSecond: Double = 1.5
    /// Points per second with only a single player holding the zone.
    static let zoneControlSoloRatePerSecond: Double = 0.6
}
