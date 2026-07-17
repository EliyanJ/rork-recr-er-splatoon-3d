import RealityKit
import simd

/// State for a single AI-controlled painter (ally or rival).
@MainActor
final class BotAgent {
    let container: Entity
    let animator: GeneratedModelAnimationPlayer
    let home: SIMD3<Float>
    let team: Team
    let weaponSocket: Entity?
    /// Floating billboarded pseudo above the head.
    let nameTag: Entity?
    /// Row of this bot in the controller's live match statistics.
    let statsIndex: Int

    /// Local duel: stable roster id shared by host & guest (same spawn order
    /// on both devices) — nil for solo-match bots and the remote player puppet.
    var netID: Int?
    /// True on the GUEST device for host-simulated duel bots: rendered as
    /// network puppets — no local AI, no local damage resolution.
    var isNetPuppet = false
    /// Latest streamed pose target for a duel bot puppet (guest side).
    var netTargetPos: SIMD3<Float>?
    var netTargetYaw: Float = 0
    var netIsMoving = false

    /// The animated character runtime (hidden while this agent is in sponge
    /// dive form). Captured after the body model is attached.
    var bodyRuntime: Entity?
    /// Sponge dive form shown while `isDiving` — built for every fighter
    /// (solo AI bots dive tactically too, not just the remote duel puppet).
    var diveForm: Entity?
    /// Weapon currently held, mirrored from the network stream for the remote
    /// puppet so its held model matches the opponent's real loadout.
    var currentWeapon: WeaponType = .blaster
    /// True while this agent is in sponge form — submerged in its own paint,
    /// hidden from targeting (stealth), faster, and out of the fight until
    /// it surfaces. Driven by the AI for solo bots, by the network stream
    /// for the remote duel puppet.
    var isDiving = false
    /// Cooldown before the bot AI re-evaluates whether to dive or surface —
    /// avoids flickering in and out of sponge form every frame.
    var diveDecisionTimer: Double = 0
    /// Cooldown before a new dodge/strafe direction is rolled.
    var dodgeTimer: Double = 0
    /// Current lateral strafe sign (±1), refreshed every `dodgeTimer` cycle.
    var dodgeSign: Float = 1
    /// Whether the current dodge window actually strafes — rolled ONCE per
    /// window (not per frame) so the heading stays stable between rolls.
    var dodgeActive = false
    /// Cached nearest-opponent scan result, refreshed only on think frames
    /// — the O(n) scan per bot per frame was an O(n²) hidden cost.
    var cachedEngagedTarget: SIMD3<Float>?
    var hasEngagedScan = false

    var hp: Int = GameConfig.maxHP
    var isDown = false
    var respawnTimer: Double = 0
    var waypoint: SIMD3<Float>
    var waypointTimer: Double = 0
    /// Current A* route toward `waypoint` (world points), followed node by
    /// node — computed by `GameController.assignPath`.
    var path: [SIMD3<Float>] = []
    /// Index of the next `path` node to reach.
    var pathIndex: Int = 0
    /// Seconds spent trying to move while barely progressing — drives the
    /// stuck-recovery repath so bots never grind against walls.
    var stuckTime: Double = 0
    /// Consecutive stuck-recovery repaths — escalates to a brand-new
    /// destination when re-pathing to the same waypoint didn't free the bot.
    var repathAttempts: Int = 0
    var fireCooldown: Double = 1.5
    /// Remaining cooldown before this bot can lob its next paint grenade —
    /// bots use the grenade mechanic just like the player.
    var grenadeCooldown: Double = Double.random(in: 6...14)
    /// Remaining cooldown before the next hit-flinch reaction can play.
    var flinchTimer: Double = 0
    /// Stats indices of everyone who damaged this bot since its last spawn —
    /// feeds kill/assist attribution.
    var recentAttackers: Set<Int> = []
    /// Elapsed-time timestamp of the last hit taken — gates the out-of-combat
    /// HP regen, mirroring the player's own recovery.
    var lastDamageTime: Double = -10
    /// Countdown to the next +1 HP regen tick while out of combat.
    var hpRegenTick: Double = 0

    private var activeLoop: String?
    private let handTracker = HandJointTracker()
    private var weaponFollowPosition: SIMD3<Float> = GameConfig.weaponSocketPosition

    init(
        container: Entity,
        animator: GeneratedModelAnimationPlayer,
        home: SIMD3<Float>,
        team: Team,
        weaponSocket: Entity? = nil,
        nameTag: Entity? = nil,
        statsIndex: Int
    ) {
        self.container = container
        self.animator = animator
        self.home = home
        self.team = team
        self.weaponSocket = weaponSocket
        self.nameTag = nameTag
        self.statsIndex = statsIndex
        self.waypoint = home
    }

    /// Glues the bot's blaster to its animated hand joint every frame so the
    /// weapon moves with the run/idle/hit animations instead of floating at
    /// a fixed point.
    func updateWeaponFollow(dt: Float) {
        guard let socket = weaponSocket else { return }
        let target = handTracker.handPosition(in: container)
            .map { $0 + GameConfig.weaponHandOffset } ?? GameConfig.weaponSocketPosition
        weaponFollowPosition += (target - weaponFollowPosition) * min(1, dt * GameConfig.weaponFollowLerpSpeed)
        socket.position = weaponFollowPosition
    }

    /// Swaps between the character body (+ weapon) and the sponge dive form,
    /// mirroring the local player's `applyBodyVisibility`.
    func applyDiveVisibility() {
        bodyRuntime?.isEnabled = !isDiving
        weaponSocket?.isEnabled = !isDiving
        diveForm?.isEnabled = isDiving
    }

    /// Smoothly turns the body toward `direction` with a capped turn rate
    /// (radians/second) instead of snapping instantly. Steering, dodging and
    /// aiming all feed this, so alternating targets between frames reads as
    /// one fluid rotation — no more frantic "looking everywhere at once"
    /// head-jitter.
    func face(_ direction: SIMD3<Float>, dt: Float, turnRate: Float = 8) {
        guard simd_length(SIMD2<Float>(direction.x, direction.z)) > 0.001 else { return }
        let targetYaw = atan2f(direction.x, direction.z)
        let forward = container.orientation.act(SIMD3<Float>(0, 0, 1))
        let currentYaw = atan2f(forward.x, forward.z)
        var delta = targetYaw - currentYaw
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        let step = max(-turnRate * dt, min(turnRate * dt, delta))
        container.orientation = simd_quatf(angle: currentYaw + step, axis: [0, 1, 0])
    }

    /// Sets the looping animation only when it actually changes.
    func setLoop(_ resourceName: String?) {
        guard activeLoop != resourceName else { return }
        activeLoop = resourceName
        animator.setLoop(resourceName)
    }

    /// True when the bot is one hit away from going down.
    var isNearDeath: Bool { hp <= GameConfig.botLowHPThreshold }

    /// Team-appropriate animation resource names.
    var idleAnim: String? { team == .orange ? ModelCatalog.heroArmedIdle ?? ModelCatalog.heroIdle : ModelCatalog.rivalArmedIdle ?? ModelCatalog.rivalIdle }
    var runAnim: String? { team == .orange ? ModelCatalog.heroRun : ModelCatalog.rivalRun }
    var splatAnim: String? { team == .orange ? ModelCatalog.heroSplat : ModelCatalog.rivalSplat }
    var hitAnim: String? { team == .orange ? ModelCatalog.heroHit : ModelCatalog.rivalHit }
    var injuredRunAnim: String? { team == .orange ? ModelCatalog.heroInjuredRun : ModelCatalog.rivalInjuredRun }
}
