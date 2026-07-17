import Foundation

/// Skill tier applied to every AI-controlled fighter in a match. Chosen on
/// the match preparation screen (persisted between sessions) and frozen for
/// the whole match — every bot (allies and rivals alike) shares the same
/// tier so a match always feels internally consistent.
///
/// Tunes five axes at once: aim accuracy, reaction/fire cadence, movement
/// speed, tactical dive usage (fast travel, healing retreat, ambush pop-up),
/// and dodge/strafe behaviour while engaging a target.
nonisolated enum BotDifficulty: String, Codable, CaseIterable, Identifiable {
    case facile, normal, difficile

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .facile: "Facile"
        case .normal: "Normal"
        case .difficile: "Difficile"
        }
    }

    var subtitle: String {
        switch self {
        case .facile: "Bots calmes et peu précis — idéal pour apprendre."
        case .normal: "Bots redoutables : visée serrée, plongée tactique, esquives."
        case .difficile: "Bots élite : précision chirurgicale, portée maîtrisée, te vise même en hauteur."
        }
    }

    var iconSystemName: String {
        switch self {
        case .facile: "tortoise.fill"
        case .normal: "figure.walk"
        case .difficile: "bolt.fill"
        }
    }

    // MARK: Movement

    /// Multiplier applied on top of `GameConfig.botSpeed`.
    var moveSpeedMultiplier: Float {
        switch self {
        case .facile: 0.85
        case .normal: 1.12
        case .difficile: 1.18
        }
    }

    // MARK: Aiming & reaction

    /// Half-angle jitter added to the aim direction — lower = more accurate.
    var aimSpread: Float {
        switch self {
        case .facile: 0.24
        case .normal: 0.03
        case .difficile: 0.012
        }
    }

    /// Fraction of perfect target-leading applied when aiming at a moving
    /// opponent — hard bots shoot where you're GOING, not where you are.
    var aimLeadFactor: Float {
        switch self {
        case .facile: 0
        case .normal: 0.85
        case .difficile: 1.0
        }
    }

    /// Cooldown range between two fired jets — lower = faster trigger finger.
    var fireCooldownRange: ClosedRange<Double> {
        switch self {
        case .facile: 0.6...1.0
        case .normal: 0.15...0.28
        case .difficile: 0.11...0.2
        }
    }

    /// Cooldown range between two thrown grenades.
    var grenadeCooldownRange: ClosedRange<Double> {
        switch self {
        case .facile: 13...21
        case .normal: 5...10
        case .difficile: 4...7
        }
    }

    /// Distance at which the bot starts tracking/engaging a target.
    var engageRange: Float {
        switch self {
        case .facile: 9
        case .normal: 17
        case .difficile: 24
        }
    }

    /// Rolled every think-tick before actually pulling the trigger or
    /// lobbing a grenade — easy bots frequently just don't bother.
    var engagementChance: Double {
        switch self {
        case .facile: 0.45
        case .normal: 1.0
        case .difficile: 1.0
        }
    }

    // MARK: Tactical diving

    /// Chance, re-rolled every ~0.5-0.9s while standing on friendly paint,
    /// that the bot dives to travel faster toward its next waypoint.
    var diveTravelChance: Double {
        switch self {
        case .facile: 0.05
        case .normal: 0.7
        case .difficile: 0.75
        }
    }

    /// HP fraction (of max) below which a bot standing on friendly paint
    /// dives to retreat and heal instead of trading further hits.
    var fleeHPThreshold: Double {
        switch self {
        case .facile: 0.2
        case .normal: 0.5
        case .difficile: 0.5
        }
    }

    // MARK: Dodging

    /// Chance per engagement tick that the bot strafes sideways instead of
    /// walking a straight line toward its target — makes it harder to hit.
    var dodgeChance: Double {
        switch self {
        case .facile: 0
        case .normal: 0.7
        case .difficile: 0.85
        }
    }

    // MARK: Weapon-range mastery (Difficile only)

    /// Elite bots aim in FULL 3D: they know their weapon's ballistics, so a
    /// player perched on a platform or tower gets targeted with proper
    /// vertical aim and gravity-drop compensation — no more safe high ground.
    var aimsVertically: Bool {
        switch self {
        case .facile, .normal: false
        case .difficile: true
        }
    }

    // MARK: Sniper bot (the designated charger carrier)

    /// Charge fraction of each sniper shot — at 0.5+ the shot one-shots per
    /// the charger rule, so only elite snipers reliably one-shot.
    var sniperChargeRange: ClosedRange<Float> {
        switch self {
        case .facile: 0.2...0.35
        case .normal: 0.35...0.55
        case .difficile: 0.5...0.75
        }
    }

    /// Seconds between two sniper shots — deliberately slower than the
    /// blaster cadence, it's a picked-shot weapon.
    var sniperFireCooldownRange: ClosedRange<Double> {
        switch self {
        case .facile: 3.2...4.5
        case .normal: 2.2...3.2
        case .difficile: 1.6...2.4
        }
    }
}
