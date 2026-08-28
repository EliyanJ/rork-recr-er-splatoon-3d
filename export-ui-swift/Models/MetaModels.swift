import Foundation
import SwiftUI

// MARK: - Rareté

/// Rarity tiers shared by gear, weapon skins and chest drops.
nonisolated enum Rarity: String, Codable, CaseIterable, Comparable {
    case common, rare, epic, legendary

    var displayName: String {
        switch self {
        case .common: "Commun"
        case .rare: "Rare"
        case .epic: "Épique"
        case .legendary: "Légendaire"
        }
    }

    var colorHex: String {
        switch self {
        case .common: "9BA3B5"
        case .rare: "3DB8F5"
        case .epic: "9A3DF5"
        case .legendary: "F5C518"
        }
    }

    var sortOrder: Int {
        switch self {
        case .common: 0
        case .rare: 1
        case .epic: 2
        case .legendary: 3
        }
    }

    nonisolated static func < (lhs: Rarity, rhs: Rarity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

extension Rarity {
    var color: Color { Color(hex: colorHex) }
}

// MARK: - Coffres

/// Chest tiers — instant opening (no timers), each with its own published
/// drop-rate table (shown on the odds screen, App Store guideline 3.1.1).
nonisolated enum ChestType: String, Codable, CaseIterable, Identifiable {
    case bronze, silver, gold, legendary

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bronze: "Coffre Bronze"
        case .silver: "Coffre Argent"
        case .gold: "Coffre Or"
        case .legendary: "Coffre Légendaire"
        }
    }

    var iconSystemName: String { "shippingbox.fill" }

    var tintHex: String {
        switch self {
        case .bronze: "C8763A"
        case .silver: "B9C4D6"
        case .gold: "F5C518"
        case .legendary: "9A3DF5"
        }
    }

    /// Published drop probabilities (percent) per rarity — the exact table
    /// the odds screen displays and the opening logic uses.
    var odds: [(rarity: Rarity, percent: Int)] {
        switch self {
        case .bronze: [(.common, 70), (.rare, 25), (.epic, 5), (.legendary, 0)]
        case .silver: [(.common, 50), (.rare, 35), (.epic, 13), (.legendary, 2)]
        case .gold: [(.common, 30), (.rare, 40), (.epic, 24), (.legendary, 6)]
        case .legendary: [(.common, 0), (.rare, 30), (.epic, 50), (.legendary, 20)]
        }
    }

    /// Number of rewards inside one chest.
    var rewardCount: Int {
        switch self {
        case .bronze: 2
        case .silver: 2
        case .gold: 3
        case .legendary: 3
        }
    }
}

extension ChestType {
    var tint: Color { Color(hex: tintHex) }
}

// MARK: - Gadgets

/// Fourth loadout slot, independent from the main weapon. One gadget
/// equipped at a time; its cooldown is displayed on the in-match HUD.
/// Only the two stable gadgets remain — detector and jet dash were removed
/// because they were not functioning correctly.
nonisolated enum GadgetType: String, Codable, CaseIterable, Identifiable {
    /// Zone paint bomb — bounces, fixed fuse (the original grenade).
    case paintBomb
    /// Temporary ink wall — blocks shots and paths for a few seconds.
    case inkWall

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paintBomb: "Bombe à Peinture"
        case .inkWall: "Mur d'Encre"
        }
    }

    var iconSystemName: String {
        switch self {
        case .paintBomb: "burst.fill"
        case .inkWall: "rectangle.portrait.fill"
        }
    }

    var effectDescription: String {
        switch self {
        case .paintBomb: "Rebondit puis explose après 1,9 s — grosse zone de peinture + dégâts."
        case .inkWall: "Dresse un mur d'encre devant toi pendant 4 s — bloque tirs et passages."
        }
    }

    var cooldown: Double {
        switch self {
        case .paintBomb: 5
        case .inkWall: 9
        }
    }

    var inkCost: Float {
        switch self {
        case .paintBomb: 40
        case .inkWall: 30
        }
    }
}

// MARK: - Gear (équipement)

/// The three gear slots, Splatoon-style.
nonisolated enum GearSlot: String, Codable, CaseIterable, Identifiable {
    case head, body, feet

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .head: "Tête"
        case .body: "Corps"
        case .feet: "Pieds"
        }
    }

    var iconSystemName: String {
        switch self {
        case .head: "graduationcap.fill"
        case .body: "tshirt.fill"
        case .feet: "shoe.2.fill"
        }
    }
}

/// Launch catalog of gear perks — 6 perks max at launch (per design doc),
/// all utility-flavored. NO perk ever raises raw combat damage.
nonisolated enum GearPerk: String, Codable, CaseIterable, Identifiable {
    case inkRegen
    case swimBoost
    case splashResist
    case fastRespawn
    case fastRecovery
    case xpBoost

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inkRegen: "Régé d'encre rapide"
        case .swimBoost: "Nage boostée"
        case .splashResist: "Résistance aux éclaboussures"
        case .fastRespawn: "Respawn accéléré"
        case .fastRecovery: "Récup santé accélérée"
        case .xpBoost: "Boost XP fin de match"
        }
    }

    var iconSystemName: String {
        switch self {
        case .inkRegen: "drop.fill"
        case .swimBoost: "water.waves"
        case .splashResist: "shield.fill"
        case .fastRespawn: "arrow.clockwise"
        case .fastRecovery: "heart.fill"
        case .xpBoost: "star.fill"
        }
    }

    var shortDescription: String {
        switch self {
        case .inkRegen: "La jauge d'encre se remplit plus vite."
        case .swimBoost: "Vitesse augmentée dans ta propre encre."
        case .splashResist: "Réduit les dégâts de zone ennemis."
        case .fastRespawn: "Réduit le temps avant de rejouer."
        case .fastRecovery: "La vie remonte plus vite hors combat."
        case .xpBoost: "Plus d'XP à la fin du match."
        }
    }
}

/// One piece of gear: a guaranteed main perk plus 0-3 random secondary
/// perks (more secondaries = rarer piece).
nonisolated struct GearItem: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let slot: GearSlot
    let rarity: Rarity
    let mainPerk: GearPerk
    let secondaryPerks: [GearPerk]
}

/// Combat/utility modifiers computed from the equipped gear set — applied
/// once at match launch by the GameController.
nonisolated struct PerkModifiers {
    var inkRegenMultiplier: Float = 1
    var swimBoostMultiplier: Float = 1
    var splashDamageReduction: Int = 0
    var respawnMultiplier: Double = 1
    var hpRegenMultiplier: Double = 1
    var xpMultiplier: Double = 1
}

// MARK: - Skins d'armes

/// Cosmetic weapon reskin — pure tint variant, zero stat impact.
nonisolated struct WeaponSkin: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let weapon: WeaponType
    let rarity: Rarity
    let colorHex: String
}

/// Full launch catalog of weapon skins (3 per weapon), themed after the
/// four Crews of Chroma City.
nonisolated enum WeaponSkinCatalog {
    static let all: [WeaponSkin] = WeaponType.allCases.flatMap { weapon -> [WeaponSkin] in
        [
            WeaponSkin(id: "\(weapon.rawValue)_vandal", name: "Vandal Magenta", weapon: weapon, rarity: .rare, colorHex: "E8348C"),
            WeaponSkin(id: "\(weapon.rawValue)_circuit", name: "Néon Circuit", weapon: weapon, rarity: .epic, colorHex: "1AF0C4"),
            WeaponSkin(id: "\(weapon.rawValue)_solar", name: "Solar Gold", weapon: weapon, rarity: .legendary, colorHex: "F5C518"),
        ]
    }

    static func skins(for weapon: WeaponType) -> [WeaponSkin] {
        all.filter { $0.weapon == weapon }
    }

    static func skin(id: String) -> WeaponSkin? {
        all.first { $0.id == id }
    }
}

// MARK: - Titres

/// Achievement-gated profile title.
nonisolated struct PlayerTitle: Identifiable, Equatable {
    let id: String
    let name: String
    let requirement: String
}

nonisolated enum TitleCatalog {
    static let all: [PlayerTitle] = [
        PlayerTitle(id: "recrue", name: "Recrue", requirement: "Titre de départ"),
        PlayerTitle(id: "veteran", name: "Vétéran des Docks", requirement: "Jouer 10 parties"),
        PlayerTitle(id: "champion", name: "Champion de Crew", requirement: "Gagner 10 parties"),
        PlayerTitle(id: "roi_territoire", name: "Roi du Territoire", requirement: "Étaler 5 000 m² d'encre"),
        PlayerTitle(id: "machine", name: "Machine à Splat", requirement: "50 éliminations au total"),
        PlayerTitle(id: "sniper_fantome", name: "Sniper Fantôme", requirement: "Maîtrise Sniper niveau 3"),
        PlayerTitle(id: "legende", name: "Légende de Chroma City", requirement: "Atteindre le niveau 25"),
    ]

    static func title(id: String) -> PlayerTitle? {
        all.first { $0.id == id }
    }
}

// MARK: - Historique de matchs

/// One finished match, kept in a local ~20-entry history.
nonisolated struct MatchRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let mapName: String
    let outcome: String
    let orangePercent: Int
    let purplePercent: Int
    let kills: Int
    let deaths: Int
    let isMVP: Bool
    let xpEarned: Int

    var isWin: Bool { outcome == "win" }
    var outcomeLabel: String {
        switch outcome {
        case "win": "Victoire"
        case "lose": "Défaite"
        default: "Égalité"
        }
    }
}

// MARK: - Récompenses de coffre

/// One reward revealed by the chest-opening screen.
nonisolated struct ChestReward: Identifiable {
    nonisolated enum Kind {
        case pigments(Int)
        case prisms(Int)
        case gear(GearItem)
        case weaponSkin(WeaponSkin)
        case title(PlayerTitle)
    }

    let id = UUID()
    let kind: Kind
    let rarity: Rarity

    var displayName: String {
        switch kind {
        case .pigments(let amount): "\(amount) Pigments"
        case .prisms(let amount): "\(amount) Prismes"
        case .gear(let item): item.name
        case .weaponSkin(let skin): "Skin « \(skin.name) »"
        case .title(let title): "Titre « \(title.name) »"
        }
    }

    var subtitle: String {
        switch kind {
        case .pigments: "Devise gratuite"
        case .prisms: "Devise premium"
        case .gear(let item): "\(item.slot.displayName) · \(item.mainPerk.displayName)"
        case .weaponSkin(let skin): skin.weapon.displayName
        case .title: "Affichable sur ton profil"
        }
    }

    var iconSystemName: String {
        switch kind {
        case .pigments: "paintpalette.fill"
        case .prisms: "diamond.fill"
        case .gear(let item): item.slot.iconSystemName
        case .weaponSkin(let skin): skin.weapon.iconSystemName
        case .title: "textformat"
        }
    }
}

// MARK: - Boutique

/// One purchasable entry of the daily shop rotation.
nonisolated struct ShopOffer: Identifiable {
    nonisolated enum Payload {
        case weaponSkin(WeaponSkin)
        case gear(GearItem)
        case chest(ChestType)
    }

    nonisolated enum Currency {
        case pigments, prisms
    }

    let id: String
    let payload: Payload
    let price: Int
    let currency: Currency

    var displayName: String {
        switch payload {
        case .weaponSkin(let skin): "Skin « \(skin.name) »"
        case .gear(let item): item.name
        case .chest(let chest): chest.displayName
        }
    }

    var subtitle: String {
        switch payload {
        case .weaponSkin(let skin): skin.weapon.displayName
        case .gear(let item): "\(item.slot.displayName) · \(item.mainPerk.displayName)"
        case .chest: "Ouverture instantanée"
        }
    }

    var rarity: Rarity {
        switch payload {
        case .weaponSkin(let skin): skin.rarity
        case .gear(let item): item.rarity
        case .chest(let chest):
            switch chest {
            case .bronze: .common
            case .silver: .rare
            case .gold: .epic
            case .legendary: .legendary
            }
        }
    }

    var iconSystemName: String {
        switch payload {
        case .weaponSkin(let skin): skin.weapon.iconSystemName
        case .gear(let item): item.slot.iconSystemName
        case .chest: "shippingbox.fill"
        }
    }
}

// MARK: - Carnet de Saison

/// One reward of the season pass (free or premium track).
nonisolated enum SeasonReward {
    case pigments(Int)
    case prisms(Int)
    case chest(ChestType)
    case weaponSkin(WeaponSkin)
    case title(PlayerTitle)

    var displayName: String {
        switch self {
        case .pigments(let amount): "\(amount) 🎨"
        case .prisms(let amount): "\(amount) 💎"
        case .chest(let chest): chest.displayName
        case .weaponSkin(let skin): skin.name
        case .title(let title): title.name
        }
    }

    var iconSystemName: String {
        switch self {
        case .pigments: "paintpalette.fill"
        case .prisms: "diamond.fill"
        case .chest: "shippingbox.fill"
        case .weaponSkin: "paintbrush.fill"
        case .title: "textformat"
        }
    }
}

// MARK: - Résumé méta de fin de match

/// One line of the animated end-of-match XP breakdown.
nonisolated struct XPLine: Identifiable {
    let id = UUID()
    let label: String
    let amount: Int
}

/// Everything the results screen animates: XP breakdown, level progress
/// before/after, currencies and the possibly-earned chest.
nonisolated struct MatchMetaSummary {
    let xpLines: [XPLine]
    let totalXP: Int
    let pigmentsEarned: Int
    let levelBefore: Int
    let levelAfter: Int
    let progressBefore: Double
    let progressAfter: Double
    let chestEarned: ChestType?
    let newTitles: [PlayerTitle]
}

// MARK: - Actus de l'Accueil

/// Static news cards of the home carousel — Chroma City season lore.
nonisolated struct NewsItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String
    let tintHex: String
}

nonisolated enum NewsCatalog {
    static let items: [NewsItem] = [
        NewsItem(
            id: "cycle1",
            title: "Cycle 1 : l'Entrepôt Sud",
            subtitle: "Les Crews se disputent l'ancienne usine Pigmenta — grimpe dans le Carnet de Saison !",
            iconSystemName: "flag.checkered",
            tintHex: "FF7A1A"
        ),
        NewsItem(
            id: "templeLost",
            title: "Nouvelle arène : Temple Lost",
            subtitle: "Un temple englouti par la jungle s'ouvre aux duels de territoire.",
            iconSystemName: "leaf.fill",
            tintHex: "35C46A"
        ),
        NewsItem(
            id: "boutique",
            title: "La Boutique est ouverte",
            subtitle: "Skins d'armes, équipement et coffres — rotation quotidienne.",
            iconSystemName: "storefront.fill",
            tintHex: "9A3DF5"
        ),
    ]
}
