import Foundation

/// Playable weapon loadouts, each with a distinct range/rate/impact/mobility
/// tradeoff.
enum WeaponType: String, CaseIterable, Codable, Identifiable {
    /// Balanced default blaster ("Standard").
    case blaster
    /// Long range, charge-and-release sniper ("Sniper").
    case charger
    /// Machine gun: continuous fire until it overheats, then a forced
    /// cool-down before firing again.
    case rapid
    /// Bucket launcher: lobs a huge paint blob in a high arc that splashes
    /// a wide area on landing — burst fire, not hold-to-spray.
    case bucket
    /// Dual pistols: staggered left/right shots, maximum mobility.
    case dual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blaster: "Standard"
        case .charger: "Sniper"
        case .rapid: "Mitrailleuse"
        case .bucket: "Lance-Seau"
        case .dual: "Double Pistolets"
        }
    }

    var tagline: String {
        switch self {
        case .blaster: "Équilibré — le classique"
        case .charger: "Charge le tir, relâche pour sniper"
        case .rapid: "Tir continu — gare à la surchauffe"
        case .bucket: "Bombe de peinture en cloche, zone énorme"
        case .dual: "Tirs jumelés décalés, mobilité max"
        }
    }

    var iconSystemName: String {
        switch self {
        case .blaster: "drop.fill"
        case .charger: "scope"
        case .rapid: "wind"
        case .bucket: "cylinder.split.1x2.fill"
        case .dual: "square.split.2x1.fill"
        }
    }

    /// Seconds between two jet ticks.
    var fireInterval: Double {
        switch self {
        case .blaster: 0.0605
        case .charger: 0.3
        case .rapid: 0.034
        case .bucket: GameConfig.bucketFireInterval
        case .dual: GameConfig.dualFireInterval
        }
    }

    var projectileSpeed: Float {
        switch self {
        // Paint-jet weapons: +35% muzzle speed for a punchier, snappier
        // stream that reaches its target with less visible lag.
        case .blaster: 27
        case .charger: 30
        case .rapid: 20.3
        case .bucket: 16.9
        case .dual: 29.7
        }
    }

    var projectileGravity: Float {
        switch self {
        case .blaster: 8
        case .charger: 4.5
        case .rapid: 11
        case .bucket: 10
        case .dual: 7.5
        }
    }

    var inkCostPerShot: Float {
        switch self {
        case .blaster: 1.76
        case .charger: 7
        case .rapid: 1.0
        case .bucket: GameConfig.bucketInkCost
        case .dual: 2.4
        }
    }

    /// Damage dealt by one drop that hits a character.
    var damagePerHit: Int {
        switch self {
        case .blaster: 1
        case .charger: 3
        case .rapid: 1
        case .bucket: 4
        case .dual: 1
        }
    }

    /// Ground splat radius of a landing drop.
    var paintRadius: Float {
        switch self {
        case .blaster: 0.85
        case .charger: 1.15
        case .rapid: 0.65
        case .bucket: 3.0
        case .dual: 0.7
        }
    }

    /// Random aim jitter applied per drop.
    var spread: Float {
        switch self {
        case .blaster: 0.025
        case .charger: 0.006
        case .rapid: 0.055
        case .bucket: 0.015
        case .dual: 0.03
        }
    }

    /// Movement speed multiplier while carrying this weapon — every weapon
    /// has its own mobility class so loadouts feel genuinely distinct.
    var moveSpeedMultiplier: Float {
        switch self {
        case .blaster: 1.0
        case .charger: 0.88
        case .rapid: 0.92
        case .bucket: 0.85
        case .dual: 1.18
        }
    }

    // MARK: Loadout card stat bars (0...1)

    var rangeStat: Double {
        switch self {
        case .blaster: 0.6
        case .charger: 1.0
        case .rapid: 0.35
        case .bucket: 0.55
        case .dual: 0.5
        }
    }

    var rateStat: Double {
        switch self {
        case .blaster: 0.65
        case .charger: 0.2
        case .rapid: 1.0
        case .bucket: 0.15
        case .dual: 0.8
        }
    }

    var powerStat: Double {
        switch self {
        case .blaster: 0.45
        case .charger: 0.95
        case .rapid: 0.3
        case .bucket: 0.85
        case .dual: 0.5
        }
    }

    var mobilityStat: Double {
        switch self {
        case .blaster: 0.6
        case .charger: 0.35
        case .rapid: 0.45
        case .bucket: 0.3
        case .dual: 1.0
        }
    }

    // MARK: Radar chart (8 axes) — the 4 extra axes are reworded, normalized
    // reads of stats that already drive gameplay (spread, ink cost, paint
    // radius, projectile gravity), not new made-up numbers.

    /// Steadiness of the aim — the inverse of the shot's random jitter.
    var precisionStat: Double {
        let minSpread: Float = 0.006
        let maxSpread: Float = 0.055
        let t = (spread - minSpread) / (maxSpread - minSpread)
        return Double(1 - min(max(t, 0), 1))
    }

    /// How many shots the ink tank holds — the inverse of the per-shot cost.
    var inkCapacityStat: Double {
        let minCost: Float = 1.0
        let maxCost: Float = 7.0
        let t = (inkCostPerShot - minCost) / (maxCost - minCost)
        return Double(1 - min(max(t, 0), 1))
    }

    /// Ground coverage of one landing drop — reads straight off the splat radius.
    var areaStat: Double {
        let minRadius: Float = 0.65
        let maxRadius: Float = 3.0
        let t = (paintRadius - minRadius) / (maxRadius - minRadius)
        return Double(min(max(t, 0), 1))
    }

    /// Trajectory stability — the inverse of the projectile's gravity, so a
    /// flatter, more predictable arc scores higher.
    var controlStat: Double {
        let minGravity: Float = 4.5
        let maxGravity: Float = 11.0
        let t = (projectileGravity - minGravity) / (maxGravity - minGravity)
        return Double(1 - min(max(t, 0), 1))
    }

    /// The 8 labeled axes shown on the loadout radar chart, in clockwise order.
    var radarAxes: [(label: String, value: Double)] {
        [
            ("Portée", rangeStat),
            ("Cadence", rateStat),
            ("Dégâts", powerStat),
            ("Précision", precisionStat),
            ("Mobilité", mobilityStat),
            ("Contrôle", controlStat),
            ("Zone", areaStat),
            ("Encre", inkCapacityStat),
        ]
    }
}
