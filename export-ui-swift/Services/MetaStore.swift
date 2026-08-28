import Foundation
import Observation

/// Persisted meta-game snapshot — one Codable blob in UserDefaults so every
/// progression system (currencies, XP, chests, gear, skins, titles, season
/// pass, history) survives between sessions.
nonisolated struct MetaState: Codable {
    var pigments: Int = 400
    var prisms: Int = 80
    var accountXP: Int = 0
    var seasonXP: Int = 0
    var hasPremiumPass: Bool = false
    var grantedFreeTier: Int = 0
    var grantedPremiumTier: Int = 0
    var masteryXP: [String: Int] = [:]
    var chestCounts: [String: Int] = [:]
    var gearInventory: [GearItem] = []
    var equippedGear: [String: UUID] = [:]
    var equippedGadget: String = GadgetType.paintBomb.rawValue
    var ownedSkinIDs: Set<String> = []
    var equippedSkins: [String: String] = [:]
    var ownedTitleIDs: Set<String> = ["recrue"]
    var selectedTitleID: String = "recrue"
    var history: [MatchRecord] = []
    var starterPackOwned: Bool = false
    var purchasedOfferKeys: Set<String> = []
    var totalKills: Int = 0
    var totalDeaths: Int = 0
    var migratedLegacyCoins: Bool = false
}

/// Central meta-game store: two currencies (Pigments free / Prismes
/// premium), account XP + levels, weapon mastery, instant-open chests with
/// published odds, gear with utility perks, gadgets, weapon skins, titles,
/// the season pass and the daily shop rotation.
@MainActor
@Observable
final class MetaStore {
    static let shared = MetaStore()

    private(set) var state: MetaState

    private let defaults = UserDefaults.standard
    private static let storageKey = "meta.state.v1"

    private init() {
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(MetaState.self, from: data) {
            state = decoded
        } else {
            state = MetaState()
        }
        if !state.migratedLegacyCoins {
            // One-time migration: the old single "coins" currency becomes
            // Pigments so nobody loses what they already earned.
            let legacy = defaults.integer(forKey: "profile.coins")
            state.pigments += legacy
            state.migratedLegacyCoins = true
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Devises

    var pigments: Int { state.pigments }
    var prisms: Int { state.prisms }

    @discardableResult
    func spendPigments(_ amount: Int) -> Bool {
        guard state.pigments >= amount else { return false }
        state.pigments -= amount
        save()
        return true
    }

    @discardableResult
    func spendPrisms(_ amount: Int) -> Bool {
        guard state.prisms >= amount else { return false }
        state.prisms -= amount
        save()
        return true
    }

    /// Simulated Prisms top-up — StoreKit is plugged in at publication;
    /// for now the pack is granted directly so the whole economy is testable.
    func grantPrisms(_ amount: Int) {
        state.prisms += amount
        save()
    }

    /// Direct Pigments grant — used by mission/challenge reward claims.
    func grantPigments(_ amount: Int) {
        state.pigments += amount
        save()
    }

    // MARK: - XP & niveaux

    static let maxLevel = 50

    /// XP needed to clear the given level (1-based).
    nonisolated static func xpCost(forLevel level: Int) -> Int {
        100 + (level - 1) * 35
    }

    /// Account level (1...50) derived from lifetime XP.
    nonisolated static func level(forXP xp: Int) -> Int {
        var remaining = xp
        var level = 1
        while level < maxLevel, remaining >= xpCost(forLevel: level) {
            remaining -= xpCost(forLevel: level)
            level += 1
        }
        return level
    }

    /// Progress (0...1) inside the current level.
    nonisolated static func levelProgress(forXP xp: Int) -> Double {
        var remaining = xp
        var level = 1
        while level < maxLevel, remaining >= xpCost(forLevel: level) {
            remaining -= xpCost(forLevel: level)
            level += 1
        }
        guard level < maxLevel else { return 1 }
        return Double(remaining) / Double(xpCost(forLevel: level))
    }

    var accountLevel: Int { Self.level(forXP: state.accountXP) }
    var accountLevelProgress: Double { Self.levelProgress(forXP: state.accountXP) }

    /// Weapon mastery level (0...5) — cosmetic prestige, never a stat bonus.
    func masteryLevel(for weapon: WeaponType) -> Int {
        min(5, (state.masteryXP[weapon.rawValue] ?? 0) / 400)
    }

    func masteryXP(for weapon: WeaponType) -> Int {
        state.masteryXP[weapon.rawValue] ?? 0
    }

    // MARK: - Fin de match

    /// Applies one finished match: XP breakdown (coverage + kills +
    /// objective + win + MVP), currencies, mastery, chest drops, title
    /// unlocks and the match history entry.
    func applyMatch(result: MatchResult, weapon: WeaponType) -> MatchMetaSummary {
        let player = result.standings.first { $0.id == 0 }
        let kills = player?.kills ?? 0
        let deaths = player?.deaths ?? 0
        let topKills = result.standings.map(\.kills).max() ?? 0
        let isMVP = kills > 0 && kills >= topKills

        var lines: [XPLine] = []
        lines.append(XPLine(label: "Couverture", amount: min(120, result.paintedTiles / 4)))
        if kills > 0 { lines.append(XPLine(label: "Éliminations", amount: kills * 12)) }
        lines.append(XPLine(label: "Objectif joué", amount: 20))
        switch result.outcome {
        case .win: lines.append(XPLine(label: "Victoire", amount: 50))
        case .draw: lines.append(XPLine(label: "Égalité", amount: 25))
        case .lose: break
        }
        if isMVP { lines.append(XPLine(label: "MVP", amount: 30)) }

        var total = lines.reduce(0) { $0 + $1.amount }
        let boost = perkModifiers.xpMultiplier
        if boost > 1 {
            let bonus = Int(Double(total) * (boost - 1))
            if bonus > 0 {
                lines.append(XPLine(label: "Boost XP (équipement)", amount: bonus))
                total += bonus
            }
        }

        let levelBefore = accountLevel
        let progressBefore = accountLevelProgress
        state.accountXP += total
        state.seasonXP += total
        state.masteryXP[weapon.rawValue, default: 0] += total / 2
        let levelAfter = accountLevel
        let progressAfter = accountLevelProgress

        let pigmentsEarned = 30 + result.paintedTiles / 6 + (result.outcome == .win ? 20 : 0)
        state.pigments += pigmentsEarned
        state.totalKills += kills
        state.totalDeaths += deaths

        // Chest drops: bronze on a win (or lucky loss), silver on level-up,
        // gold every 5 account levels.
        var chest: ChestType?
        if levelAfter > levelBefore {
            chest = levelAfter % 5 == 0 ? .gold : .silver
        } else if result.outcome == .win || Int.random(in: 0..<10) < 4 {
            chest = .bronze
        }
        if let chest {
            state.chestCounts[chest.rawValue, default: 0] += 1
        }

        state.history.insert(
            MatchRecord(
                id: UUID(),
                date: Date(),
                mapName: GameConfig.currentMap.displayName,
                outcome: {
                    switch result.outcome {
                    case .win: "win"
                    case .lose: "lose"
                    case .draw: "draw"
                    }
                }(),
                orangePercent: result.orangePercent,
                purplePercent: result.purplePercent,
                kills: kills,
                deaths: deaths,
                isMVP: isMVP,
                xpEarned: total
            ),
            at: 0
        )
        if state.history.count > 20 {
            state.history.removeLast(state.history.count - 20)
        }

        let newTitles = unlockEarnedTitles()
        grantSeasonTiers()
        save()

        return MatchMetaSummary(
            xpLines: lines,
            totalXP: total,
            pigmentsEarned: pigmentsEarned,
            levelBefore: levelBefore,
            levelAfter: levelAfter,
            progressBefore: progressBefore,
            progressAfter: progressAfter,
            chestEarned: chest,
            newTitles: newTitles
        )
    }

    // MARK: - Coffres

    func chestCount(_ type: ChestType) -> Int {
        state.chestCounts[type.rawValue] ?? 0
    }

    var totalChestsReady: Int {
        ChestType.allCases.reduce(0) { $0 + chestCount($1) }
    }

    /// First chest type with at least one waiting copy — bronze first.
    var nextReadyChest: ChestType? {
        ChestType.allCases.first { chestCount($0) > 0 }
    }

    func addChest(_ type: ChestType) {
        state.chestCounts[type.rawValue, default: 0] += 1
        save()
    }

    /// Opens one chest instantly (no timers) and returns its rewards.
    func openChest(_ type: ChestType) -> [ChestReward] {
        guard chestCount(type) > 0 else { return [] }
        state.chestCounts[type.rawValue] = chestCount(type) - 1
        var rewards: [ChestReward] = []
        for _ in 0..<type.rewardCount {
            rewards.append(rollReward(rarity: rollRarity(odds: type.odds)))
        }
        save()
        return rewards
    }

    private func rollRarity(odds: [(rarity: Rarity, percent: Int)]) -> Rarity {
        let roll = Int.random(in: 0..<100)
        var cursor = 0
        for entry in odds {
            cursor += entry.percent
            if roll < cursor { return entry.rarity }
        }
        return odds.last?.rarity ?? .common
    }

    private func rollReward(rarity: Rarity) -> ChestReward {
        // Reward type mix: gear and skins carry the excitement, currencies
        // fill the rest so no chest ever feels empty.
        let roll = Int.random(in: 0..<100)
        if roll < 32 {
            let item = Self.generateGearItem(rarity: rarity)
            state.gearInventory.append(item)
            return ChestReward(kind: .gear(item), rarity: rarity)
        }
        if roll < 55, rarity >= .rare {
            let unowned = WeaponSkinCatalog.all.filter {
                $0.rarity == rarity && !state.ownedSkinIDs.contains($0.id)
            }
            if let skin = unowned.randomElement() {
                state.ownedSkinIDs.insert(skin.id)
                return ChestReward(kind: .weaponSkin(skin), rarity: rarity)
            }
        }
        if roll < 62, rarity >= .epic {
            let locked = TitleCatalog.all.filter { !state.ownedTitleIDs.contains($0.id) }
            if let title = locked.randomElement() {
                state.ownedTitleIDs.insert(title.id)
                return ChestReward(kind: .title(title), rarity: rarity)
            }
        }
        if roll < 78, rarity >= .rare {
            let amount = rarity == .legendary ? 60 : (rarity == .epic ? 30 : 15)
            state.prisms += amount
            return ChestReward(kind: .prisms(amount), rarity: rarity)
        }
        let amount = 40 + rarity.sortOrder * 45 + Int.random(in: 0..<30)
        state.pigments += amount
        return ChestReward(kind: .pigments(amount), rarity: rarity)
    }

    /// Procedural gear piece: guaranteed main perk + rarity-scaled random
    /// secondary perks, named after the Crews of Chroma City.
    nonisolated static func generateGearItem(rarity: Rarity) -> GearItem {
        let slot = GearSlot.allCases.randomElement() ?? .head
        let mainPerk = GearPerk.allCases.randomElement() ?? .inkRegen
        let secondaryCount = rarity.sortOrder
        let secondaries = Array(
            GearPerk.allCases.filter { $0 != mainPerk }.shuffled().prefix(secondaryCount)
        )
        let crews = ["du Vandal", "Circuit", "Solar", "des Ferals", "Pigmenta", "des Docks"]
        let base: [GearSlot: [String]] = [
            .head: ["Casquette", "Bandana", "Casque", "Lunettes"],
            .body: ["Veste", "Combinaison", "Hoodie", "Gilet"],
            .feet: ["Baskets", "Bottes", "Crampons", "Sandales"],
        ]
        let name = "\(base[slot]?.randomElement() ?? "Pièce") \(crews.randomElement() ?? "")"
        return GearItem(
            id: UUID(),
            name: name,
            slot: slot,
            rarity: rarity,
            mainPerk: mainPerk,
            secondaryPerks: secondaries
        )
    }

    // MARK: - Équipement (gear)

    func gearItems(slot: GearSlot) -> [GearItem] {
        state.gearInventory
            .filter { $0.slot == slot }
            .sorted { $0.rarity.sortOrder > $1.rarity.sortOrder }
    }

    func equippedGear(slot: GearSlot) -> GearItem? {
        guard let id = state.equippedGear[slot.rawValue] else { return nil }
        return state.gearInventory.first { $0.id == id }
    }

    func equipGear(_ item: GearItem) {
        state.equippedGear[item.slot.rawValue] = item.id
        save()
    }

    func unequipGear(slot: GearSlot) {
        state.equippedGear[slot.rawValue] = nil
        save()
    }

    /// Stacked utility modifiers from the equipped gear set — main perk
    /// counts full strength, each secondary counts a third.
    var perkModifiers: PerkModifiers {
        var mods = PerkModifiers()
        for slot in GearSlot.allCases {
            guard let item = equippedGear(slot: slot) else { continue }
            apply(perk: item.mainPerk, weight: 1, to: &mods)
            for perk in item.secondaryPerks {
                apply(perk: perk, weight: 0.34, to: &mods)
            }
        }
        return mods
    }

    private func apply(perk: GearPerk, weight: Double, to mods: inout PerkModifiers) {
        switch perk {
        case .inkRegen: mods.inkRegenMultiplier += Float(0.25 * weight)
        case .swimBoost: mods.swimBoostMultiplier += Float(0.12 * weight)
        case .splashResist: mods.splashDamageReduction += weight >= 1 ? 1 : 0
        case .fastRespawn: mods.respawnMultiplier -= 0.2 * weight
        case .fastRecovery: mods.hpRegenMultiplier -= 0.3 * weight
        case .xpBoost: mods.xpMultiplier += 0.15 * weight
        }
    }

    // MARK: - Gadgets

    var equippedGadget: GadgetType {
        GadgetType(rawValue: state.equippedGadget) ?? .paintBomb
    }

    func equipGadget(_ gadget: GadgetType) {
        state.equippedGadget = gadget.rawValue
        save()
    }

    // MARK: - Skins d'armes

    func ownsSkin(_ skin: WeaponSkin) -> Bool {
        state.ownedSkinIDs.contains(skin.id)
    }

    func equippedSkin(for weapon: WeaponType) -> WeaponSkin? {
        guard let id = state.equippedSkins[weapon.rawValue] else { return nil }
        return WeaponSkinCatalog.skin(id: id)
    }

    func equipSkin(_ skin: WeaponSkin) {
        guard ownsSkin(skin) else { return }
        state.equippedSkins[skin.weapon.rawValue] = skin.id
        save()
    }

    func unequipSkin(for weapon: WeaponType) {
        state.equippedSkins[weapon.rawValue] = nil
        save()
    }

    /// Tint hex applied to the in-match weapon model, nil = default look.
    func equippedSkinColorHex(for weapon: WeaponType) -> String? {
        equippedSkin(for: weapon)?.colorHex
    }

    // MARK: - Titres

    var ownedTitles: [PlayerTitle] {
        TitleCatalog.all.filter { state.ownedTitleIDs.contains($0.id) }
    }

    var selectedTitle: PlayerTitle {
        TitleCatalog.title(id: state.selectedTitleID)
            ?? TitleCatalog.all[0]
    }

    func selectTitle(_ title: PlayerTitle) {
        guard state.ownedTitleIDs.contains(title.id) else { return }
        state.selectedTitleID = title.id
        save()
    }

    /// Checks every achievement gate and unlocks freshly earned titles.
    private func unlockEarnedTitles() -> [PlayerTitle] {
        var earned: [PlayerTitle] = []
        func unlock(_ id: String, when condition: Bool) {
            guard condition, !state.ownedTitleIDs.contains(id),
                  let title = TitleCatalog.title(id: id) else { return }
            state.ownedTitleIDs.insert(id)
            earned.append(title)
        }
        let profile = ProfileStore.shared
        unlock("veteran", when: profile.matchesPlayed >= 10)
        unlock("champion", when: profile.wins >= 10)
        unlock("roi_territoire", when: profile.tilesPainted >= 5000)
        unlock("machine", when: state.totalKills >= 50)
        unlock("sniper_fantome", when: masteryLevel(for: .charger) >= 3)
        unlock("legende", when: accountLevel >= 25)
        return earned
    }

    // MARK: - Carnet de Saison

    static let seasonTierCount = 50
    static let seasonXPPerTier = 80
    static let premiumPassPrice = 950

    var seasonTier: Int {
        min(Self.seasonTierCount, state.seasonXP / Self.seasonXPPerTier)
    }

    var seasonTierProgress: Double {
        guard seasonTier < Self.seasonTierCount else { return 1 }
        let into = state.seasonXP - seasonTier * Self.seasonXPPerTier
        return Double(into) / Double(Self.seasonXPPerTier)
    }

    var hasPremiumPass: Bool { state.hasPremiumPass }

    @discardableResult
    func buyPremiumPass() -> Bool {
        guard !state.hasPremiumPass, spendPrisms(Self.premiumPassPrice) else { return false }
        state.hasPremiumPass = true
        grantSeasonTiers()
        save()
        return true
    }

    /// Deterministic season track — free row every tier, premium row richer.
    nonisolated static func freeReward(tier: Int) -> SeasonReward {
        if tier % 10 == 0 { return .chest(.silver) }
        if tier % 5 == 0 { return .chest(.bronze) }
        return .pigments(40 + tier * 4)
    }

    nonisolated static func premiumReward(tier: Int) -> SeasonReward {
        if tier == seasonTierCount { return .chest(.legendary) }
        if tier % 10 == 0,
           let skin = WeaponSkinCatalog.all.first(where: { $0.rarity == .epic })
            .map({ _ in WeaponSkinCatalog.all[(tier / 10 - 1) % WeaponSkinCatalog.all.count] }) {
            return .weaponSkin(skin)
        }
        if tier % 5 == 0 { return .chest(.gold) }
        if tier % 3 == 0 { return .prisms(20) }
        return .pigments(70 + tier * 5)
    }

    /// Grants every newly reached tier (free track, plus premium if owned).
    private func grantSeasonTiers() {
        let tier = seasonTier
        while state.grantedFreeTier < tier {
            state.grantedFreeTier += 1
            grant(Self.freeReward(tier: state.grantedFreeTier))
        }
        if state.hasPremiumPass {
            while state.grantedPremiumTier < tier {
                state.grantedPremiumTier += 1
                grant(Self.premiumReward(tier: state.grantedPremiumTier))
            }
        }
        save()
    }

    private func grant(_ reward: SeasonReward) {
        switch reward {
        case .pigments(let amount): state.pigments += amount
        case .prisms(let amount): state.prisms += amount
        case .chest(let chest): state.chestCounts[chest.rawValue, default: 0] += 1
        case .weaponSkin(let skin): state.ownedSkinIDs.insert(skin.id)
        case .title(let title): state.ownedTitleIDs.insert(title.id)
        }
    }

    // MARK: - Boutique

    /// Daily rotation — deterministic from the calendar day so everyone
    /// sees the same shop until midnight, no server needed.
    var dailyOffers: [ShopOffer] {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var generator = SeededGenerator(seed: UInt64(day))
        var offers: [ShopOffer] = []

        let skins = WeaponSkinCatalog.all.shuffled(using: &generator)
        for (index, skin) in skins.prefix(2).enumerated() {
            let priceByRarity = [Rarity.common: 300, .rare: 550, .epic: 900, .legendary: 1500]
            offers.append(ShopOffer(
                id: "d\(day)_skin\(index)_\(skin.id)",
                payload: .weaponSkin(skin),
                price: index == 0 ? (priceByRarity[skin.rarity] ?? 500) : skin.rarity.sortOrder * 30 + 40,
                currency: index == 0 ? .pigments : .prisms
            ))
        }

        var dayGenerator = SeededGenerator(seed: UInt64(day) &+ 99)
        let rarities: [Rarity] = [.rare, .epic]
        let gearRarity = rarities.randomElement(using: &dayGenerator) ?? .rare
        var itemGenerator = SeededGenerator(seed: UInt64(day) &+ 7)
        let slot = GearSlot.allCases.randomElement(using: &itemGenerator) ?? .body
        let perk = GearPerk.allCases.randomElement(using: &itemGenerator) ?? .swimBoost
        let names = ["Veste Circuit", "Casque Solar", "Baskets du Vandal", "Bandana Feral"]
        let gear = GearItem(
            id: Self.stableUUID(day: day),
            name: names[day % names.count],
            slot: slot,
            rarity: gearRarity,
            mainPerk: perk,
            secondaryPerks: Array(GearPerk.allCases.filter { $0 != perk }.prefix(gearRarity.sortOrder))
        )
        offers.append(ShopOffer(
            id: "d\(day)_gear",
            payload: .gear(gear),
            price: gearRarity == .epic ? 120 : 70,
            currency: .prisms
        ))

        offers.append(ShopOffer(
            id: "d\(day)_chest",
            payload: .chest(.gold),
            price: 110,
            currency: .prisms
        ))
        return offers
    }

    /// Same gear UUID for the whole day so re-buying is impossible.
    nonisolated private static func stableUUID(day: Int) -> UUID {
        let hex = String(format: "%012d", day)
        return UUID(uuidString: "00000000-0000-4000-8000-\(hex)") ?? UUID()
    }

    func hasPurchased(_ offer: ShopOffer) -> Bool {
        if case .chest = offer.payload { return false }
        if case .weaponSkin(let skin) = offer.payload, ownsSkin(skin) { return true }
        return state.purchasedOfferKeys.contains(offer.id)
    }

    @discardableResult
    func buy(_ offer: ShopOffer) -> Bool {
        guard !hasPurchased(offer) else { return false }
        let paid = offer.currency == .pigments
            ? spendPigments(offer.price)
            : spendPrisms(offer.price)
        guard paid else { return false }
        switch offer.payload {
        case .weaponSkin(let skin):
            state.ownedSkinIDs.insert(skin.id)
        case .gear(let item):
            state.gearInventory.append(item)
        case .chest(let chest):
            state.chestCounts[chest.rawValue, default: 0] += 1
        }
        state.purchasedOfferKeys.insert(offer.id)
        save()
        return true
    }

    // MARK: - Starter pack

    var starterPackOwned: Bool { state.starterPackOwned }

    /// Simulated real-money purchase (StoreKit at publication): 500 Prismes
    /// + one epic skin per Crew color.
    func buyStarterPack() {
        guard !state.starterPackOwned else { return }
        state.starterPackOwned = true
        state.prisms += 500
        for skin in WeaponSkinCatalog.all.filter({ $0.rarity == .epic }).prefix(3) {
            state.ownedSkinIDs.insert(skin.id)
        }
        save()
    }

    // MARK: - Historique

    var matchHistory: [MatchRecord] { state.history }
    var totalKills: Int { state.totalKills }
    var totalDeaths: Int { state.totalDeaths }
}

/// Deterministic RNG for the daily shop rotation.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var seed: UInt64

    init(seed: UInt64) {
        self.seed = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return seed
    }
}
