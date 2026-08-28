import Foundation

/// Playable arenas. Each map carries its own footprint, art direction and
/// texture set; the selection is made on the loadout screen before launch.
/// Only Nexus Docks and Temple Lost remain in the launch pool — the other
/// experimental maps have been removed from selection because they were
/// unstable in the current build.
enum ArenaMap: String, CaseIterable, Identifiable {
    /// Paint-factory docks at sunset — the original arena.
    case nexusDocks
    /// Lost jungle temple — mossy stone, water channels and glowing ruins.
    case templeLost

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nexusDocks: "Nexus Docks"
        case .templeLost: "Temple Lost"
        }
    }

    var tagline: String {
        switch self {
        case .nexusDocks: "Docks industriels au coucher de soleil — conteneurs, tyroliennes et néons."
        case .templeLost: "Temple englouti par la jungle — pierre moussue, canaux d'eau et cristaux."
        }
    }

    var iconSystemName: String {
        switch self {
        case .nexusDocks: "shippingbox.fill"
        case .templeLost: "leaf.fill"
        }
    }

    /// Arena footprint in meters.
    var width: Float {
        switch self {
        case .nexusDocks: 56
        case .templeLost: 72
        }
    }

    var depth: Float {
        switch self {
        case .nexusDocks: 36
        case .templeLost: 44
        }
    }
}
