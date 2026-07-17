import Foundation

/// Win-condition & scoring variant selected on the match preparation screen.
/// Chosen before launch (persisted between sessions) and frozen for the
/// whole match, mirroring `BotDifficulty` — every fighter and every screen
/// (HUD, results) reads the same frozen value for the match's lifetime.
nonisolated enum MatchMode: String, Codable, CaseIterable, Identifiable {
    /// The original mode: cover the most turf before the clock runs out.
    case turfWar
    /// Team kill race — most eliminations when the clock hits zero wins.
    case deathmatch
    /// Hold the two neutral zones to bank points — first to the target
    /// score wins outright, otherwise the leader when time runs out.
    case zoneControl

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turfWar: "Guerre de Peinture"
        case .deathmatch: "Duel Mortel"
        case .zoneControl: "Contrôle de Zones"
        }
    }

    var subtitle: String {
        switch self {
        case .turfWar: "Couvrez le plus de terrain avant la fin du chrono."
        case .deathmatch: "Le plus d'éliminations à la fin du chrono gagne."
        case .zoneControl: "Tenez les zones pour marquer — 100 points ou le meilleur score au chrono."
        }
    }

    var iconSystemName: String {
        switch self {
        case .turfWar: "paintbrush.pointed.fill"
        case .deathmatch: "burst.fill"
        case .zoneControl: "hexagon.fill"
        }
    }
}
