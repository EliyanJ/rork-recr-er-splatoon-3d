import Foundation
import Observation
import SwiftUI

/// Identifiers of the draggable HUD buttons the settings panel lets players
/// reposition on mobile.
enum HUDControlID: String, CaseIterable {
    case joystick, dive, fire, grenade, jump
}

/// Cosmetic accessory worn by the player character — purely visual, tinted
/// with the chosen accent color, shown both in the locker room and in-match.
enum PlayerAccessory: String, CaseIterable, Identifiable {
    case none, band, cape, visor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "Aucun"
        case .band: "Bandeau"
        case .cape: "Écharpe"
        case .visor: "Visière"
        }
    }
}

/// Trophies and coins earned by one finished match — shown on the results
/// screen and added to the lifetime profile totals.
struct MatchRewards {
    let trophies: Int
    let coins: Int
}

/// Persistent player profile: name, lifetime stats, and gameplay settings.
/// Backed by UserDefaults so everything survives between sessions.
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    var playerName: String {
        didSet { defaults.set(playerName, forKey: Keys.name) }
    }

    private(set) var matchesPlayed: Int {
        didSet { defaults.set(matchesPlayed, forKey: Keys.matches) }
    }

    private(set) var wins: Int {
        didSet { defaults.set(wins, forKey: Keys.wins) }
    }

    /// Lifetime tiles of turf covered by the player's team.
    private(set) var tilesPainted: Int {
        didSet { defaults.set(tilesPainted, forKey: Keys.tiles) }
    }

    // MARK: Economy (MVP: trophies + a single coin currency)

    private(set) var trophies: Int {
        didSet { defaults.set(trophies, forKey: Keys.trophies) }
    }

    private(set) var coins: Int {
        didSet { defaults.set(coins, forKey: Keys.coins) }
    }

    // MARK: Onboarding milestones

    /// True once the terms/privacy consent screen has been accepted.
    var hasAcceptedTerms: Bool {
        didSet { defaults.set(hasAcceptedTerms, forKey: Keys.acceptedTerms) }
    }

    /// True once the player picked their name on the first victory screen.
    var hasSetName: Bool {
        didSet { defaults.set(hasSetName, forKey: Keys.hasSetName) }
    }

    /// True once the first real match has been completed — gates the
    /// in-match tutorial overlay to the very first game.
    var hasPlayedFirstMatch: Bool {
        didSet { defaults.set(hasPlayedFirstMatch, forKey: Keys.firstMatch) }
    }

    /// Camera drag sensitivity multiplier (0.5x ... 1.6x).
    var cameraSensitivity: Double {
        didSet { defaults.set(cameraSensitivity, forKey: Keys.sensitivity) }
    }

    var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: Keys.sound)
            AudioService.shared.isMuted = !soundEnabled
        }
    }

    var selectedWeapon: WeaponType {
        didSet { defaults.set(selectedWeapon.rawValue, forKey: Keys.weapon) }
    }

    /// Arena chosen on the loadout screen — applied at match launch.
    var selectedMap: ArenaMap {
        didSet { defaults.set(selectedMap.rawValue, forKey: Keys.map) }
    }

    /// Skill tier of every AI bot in the next match — chosen on the match
    /// preparation screen. Defaults to Difficile so bots are competitive out
    /// of the box; the player can dial it down from the picker any time.
    var botDifficulty: BotDifficulty {
        didSet { defaults.set(botDifficulty.rawValue, forKey: Keys.botDifficulty) }
    }

    /// Partie personnalisée: AI bots added to each team of a local duel
    /// (0–2) — chosen by the host in the local-match lobby.
    var duelBotsPerTeam: Int {
        didSet { defaults.set(duelBotsPerTeam, forKey: Keys.duelBotsPerTeam) }
    }

    /// Win-condition variant of the next match — chosen on the match
    /// preparation screen, alongside the arena and bot difficulty.
    var matchMode: MatchMode {
        didSet { defaults.set(matchMode.rawValue, forKey: Keys.matchMode) }
    }

    /// Preferred camera perspective — close over-the-shoulder or first person.
    var cameraMode: CameraMode {
        didSet { defaults.set(cameraMode.rawValue, forKey: Keys.cameraMode) }
    }

    // MARK: Settings panel

    var masterVolume: Double {
        didSet {
            defaults.set(masterVolume, forKey: Keys.masterVolume)
            applyVolumes()
        }
    }

    var musicVolume: Double {
        didSet {
            defaults.set(musicVolume, forKey: Keys.musicVolume)
            applyVolumes()
        }
    }

    var sfxVolume: Double {
        didSet {
            defaults.set(sfxVolume, forKey: Keys.sfxVolume)
            applyVolumes()
        }
    }

    /// Manual quality override, only used when `autoGraphicsQuality` is off.
    var graphicsQuality: GraphicsQuality {
        didSet { defaults.set(graphicsQuality.rawValue, forKey: Keys.graphicsQuality) }
    }

    /// When true (default), the active preset always tracks the detected
    /// device tier instead of a manual choice — the Settings picker shows
    /// "Auto (Niveau)" and is greyed out. Turning this off lets the player
    /// force a specific preset (e.g. Lite on a device that auto-detects
    /// Standard, if they still see lag).
    var autoGraphicsQuality: Bool {
        didSet { defaults.set(autoGraphicsQuality, forKey: Keys.autoGraphicsQuality) }
    }

    /// The preset actually applied at the next match: the detected
    /// recommendation while auto is on, otherwise the manual choice.
    var effectiveGraphicsQuality: GraphicsQuality {
        autoGraphicsQuality ? DevicePerformance.recommendedQuality : graphicsQuality
    }

    /// Real target framerate of the game simulation (30 / 60 / 120). The
    /// game loop paces itself to this rate — it is not a cosmetic setting.
    var targetFPS: Int {
        didSet { defaults.set(targetFPS, forKey: Keys.targetFPS) }
    }

    /// Per-button HUD offsets from their default anchor, in points — persisted
    /// as a flat dictionary so `@Observable` sees direct mutations.
    var hudOffsets: [String: CGSize] {
        didSet {
            let encoded = hudOffsets.mapValues { [$0.width, $0.height] }
            if let data = try? JSONEncoder().encode(encoded) {
                defaults.set(data, forKey: Keys.hudOffsets)
            }
        }
    }

    // MARK: Personalization

    var accentColorHex: String {
        didSet { defaults.set(accentColorHex, forKey: Keys.accentColor) }
    }

    var accentColor: Color { Color(hex: accentColorHex) }

    var selectedAccessory: PlayerAccessory {
        didSet { defaults.set(selectedAccessory.rawValue, forKey: Keys.accessory) }
    }

    var selectedSkin: ModelCatalog.PlayerSkin {
        didSet { defaults.set(selectedSkin.rawValue, forKey: Keys.skin) }
    }

    /// SF Symbol shown in the profile avatar bubble — purely cosmetic,
    /// picked from a small curated set.
    var avatarIcon: String {
        didSet { defaults.set(avatarIcon, forKey: Keys.avatarIcon) }
    }

    private func applyVolumes() {
        AudioService.shared.applyVolumes(master: masterVolume, music: musicVolume, sfx: sfxVolume)
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let name = "profile.name"
        static let matches = "profile.matches"
        static let wins = "profile.wins"
        static let tiles = "profile.tiles"
        static let sensitivity = "profile.sensitivity"
        static let sound = "profile.sound"
        static let weapon = "profile.weapon"
        static let map = "profile.map"
        static let botDifficulty = "profile.botDifficulty"
        static let duelBotsPerTeam = "profile.duelBotsPerTeam"
        static let matchMode = "profile.matchMode"
        static let cameraMode = "profile.cameraMode"
        static let masterVolume = "profile.masterVolume"
        static let musicVolume = "profile.musicVolume"
        static let sfxVolume = "profile.sfxVolume"
        static let graphicsQuality = "profile.graphicsQuality"
        static let autoGraphicsQuality = "profile.autoGraphicsQuality"
        static let targetFPS = "profile.targetFPS"
        static let trophies = "profile.trophies"
        static let coins = "profile.coins"
        static let acceptedTerms = "profile.acceptedTerms"
        static let hasSetName = "profile.hasSetName"
        static let firstMatch = "profile.firstMatch"
        static let hudOffsets = "profile.hudOffsets"
        static let accentColor = "profile.accentColor"
        static let accessory = "profile.accessory"
        static let skin = "profile.skin"
        static let avatarIcon = "profile.avatarIcon"
    }

    private init() {
        playerName = defaults.string(forKey: Keys.name) ?? "Inkling"
        matchesPlayed = defaults.integer(forKey: Keys.matches)
        wins = defaults.integer(forKey: Keys.wins)
        tilesPainted = defaults.integer(forKey: Keys.tiles)
        let storedSensitivity = defaults.double(forKey: Keys.sensitivity)
        cameraSensitivity = storedSensitivity == 0 ? 1.0 : storedSensitivity
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        selectedWeapon = WeaponType(rawValue: defaults.string(forKey: Keys.weapon) ?? "") ?? .blaster
        selectedMap = ArenaMap(rawValue: defaults.string(forKey: Keys.map) ?? "") ?? .nexusDocks
        botDifficulty = BotDifficulty(rawValue: defaults.string(forKey: Keys.botDifficulty) ?? "") ?? .difficile
        duelBotsPerTeam = max(0, min(defaults.integer(forKey: Keys.duelBotsPerTeam), 2))
        matchMode = MatchMode(rawValue: defaults.string(forKey: Keys.matchMode) ?? "") ?? .turfWar
        cameraMode = CameraMode(rawValue: defaults.string(forKey: Keys.cameraMode) ?? "") ?? .thirdPerson

        masterVolume = defaults.object(forKey: Keys.masterVolume) as? Double ?? 1
        musicVolume = defaults.object(forKey: Keys.musicVolume) as? Double ?? 0.8
        sfxVolume = defaults.object(forKey: Keys.sfxVolume) as? Double ?? 1
        // Honor an explicit stored manual choice; otherwise start the picker
        // aligned with the device-aware recommendation.
        if let storedQuality = defaults.string(forKey: Keys.graphicsQuality),
           let quality = GraphicsQuality(rawValue: storedQuality) {
            graphicsQuality = quality
        } else {
            graphicsQuality = DevicePerformance.recommendedQuality
        }
        autoGraphicsQuality = defaults.object(forKey: Keys.autoGraphicsQuality) as? Bool ?? true
        let storedFPS = defaults.integer(forKey: Keys.targetFPS)
        targetFPS = [30, 60, 120].contains(storedFPS) ? storedFPS : 60
        trophies = defaults.integer(forKey: Keys.trophies)
        coins = defaults.integer(forKey: Keys.coins)
        hasAcceptedTerms = defaults.bool(forKey: Keys.acceptedTerms)
        hasSetName = defaults.bool(forKey: Keys.hasSetName)
        hasPlayedFirstMatch = defaults.bool(forKey: Keys.firstMatch)
        if let data = defaults.data(forKey: Keys.hudOffsets),
           let decoded = try? JSONDecoder().decode([String: [CGFloat]].self, from: data) {
            hudOffsets = decoded.compactMapValues { values in
                values.count == 2 ? CGSize(width: values[0], height: values[1]) : nil
            }
        } else {
            hudOffsets = [:]
        }
        accentColorHex = defaults.string(forKey: Keys.accentColor) ?? "FF7A1A"
        selectedAccessory = PlayerAccessory(rawValue: defaults.string(forKey: Keys.accessory) ?? "") ?? .none
        selectedSkin = ModelCatalog.PlayerSkin(rawValue: defaults.string(forKey: Keys.skin) ?? "") ?? .classic
        avatarIcon = defaults.string(forKey: Keys.avatarIcon) ?? AvatarIconCatalog.defaultIcon

        AudioService.shared.isMuted = !soundEnabled
        AudioService.shared.applyVolumes(master: masterVolume, music: musicVolume, sfx: sfxVolume)
    }

    /// Resets every HUD button to its default anchored position.
    func resetHUDLayout() {
        hudOffsets = [:]
    }

    /// Records a finished match, awards trophies + coins, and returns the
    /// earned rewards for the results screen.
    @discardableResult
    func recordMatch(result: MatchResult) -> MatchRewards {
        matchesPlayed += 1
        if result.outcome == .win { wins += 1 }
        tilesPainted += result.paintedTiles
        hasPlayedFirstMatch = true

        let earnedTrophies: Int
        switch result.outcome {
        case .win: earnedTrophies = 10
        case .draw: earnedTrophies = 4
        case .lose: earnedTrophies = 1
        }
        let earnedCoins = max(5, result.paintedTiles / 8)
        trophies += earnedTrophies
        coins += earnedCoins
        return MatchRewards(trophies: earnedTrophies, coins: earnedCoins)
    }
}
