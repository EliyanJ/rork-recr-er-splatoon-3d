import AVFoundation

/// Plays bundled music and sound effects for the match.
@MainActor
final class AudioService {
    static let shared = AudioService()

    /// Generic fallback match theme — used only if a map has no dedicated
    /// track loaded (keeps older/experimental maps from playing silence).
    private var music: AVAudioPlayer?
    /// One music track per arena — each map gets its own mood.
    private var mapMusic: [ArenaMap: AVAudioPlayer] = [:]
    private var activeMapMusic: AVAudioPlayer?
    private var ambience: AVAudioPlayer?
    /// Secondary environmental bed — wind through foliage layered under the
    /// city plaza ambience for a richer, less flat soundscape.
    private var windAmbience: AVAudioPlayer?
    /// Soft, light waiting-room loop — deliberately low-energy so it never
    /// competes with the loadout screen or the countdown voice-over.
    private var lobbyMusic: AVAudioPlayer?
    private var splatPool: [AVAudioPlayer] = []
    private var splatIndex = 0
    private var hitPool: [AVAudioPlayer] = []
    private var hitIndex = 0
    private var enemySplat: AVAudioPlayer?
    private var victory: AVAudioPlayer?

    /// One small round-robin pool per weapon so overlapping shots (dual
    /// pistols, rapid fire) never cut a previous shot's tail short.
    private var weaponFirePools: [WeaponType: [AVAudioPlayer]] = [:]
    private var weaponFireIndex: [WeaponType: Int] = [:]
    private var footstepPool: [AVAudioPlayer] = []
    private var footstepIndex = 0
    private var grenadeExplosion: AVAudioPlayer?
    /// Muffled looping swim sound while moving in sponge (dive) form —
    /// started/stopped as the player starts/stops swimming, never re-triggered.
    private var spongeMove: AVAudioPlayer?

    /// Profile setting: silences every player when true.
    var isMuted = false {
        didSet {
            if isMuted {
                music?.stop()
                activeMapMusic?.stop()
                ambience?.stop()
                windAmbience?.stop()
                lobbyMusic?.stop()
                spongeMove?.stop()
            }
        }
    }

    /// Independent volume sliders (0...1) from the settings panel — combined
    /// multiplicatively with each player's base mix level.
    private var masterVolume: Float = 1
    private var musicVolumeSetting: Float = 1
    private var sfxVolumeSetting: Float = 1
    // Slightly lower than before so the action's own sound effects (jets,
    // hits, footsteps) read clearly over the backing track.
    private let musicBaseVolume: Float = 0.34
    private let ambienceBaseVolume: Float = 0.26
    private let windBaseVolume: Float = 0.16
    private let lobbyBaseVolume: Float = 0.4
    private let spongeMoveBaseVolume: Float = 0.3

    private init() {
        // .playback keeps the game audible even with the ring/silent switch
        // muted — the reason the music previously seemed silent on device.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        music = loadPlayer(named: "ink_battle_funky_theme")
        music?.numberOfLoops = -1
        music?.volume = musicBaseVolume

        let mapThemes: [ArenaMap: String] = [
            .nexusDocks: "nexus_docks_theme",
            .templeLost: "temple_lost_theme",
        ]
        for (arena, name) in mapThemes {
            if let player = loadPlayer(named: name) {
                player.numberOfLoops = -1
                player.volume = musicBaseVolume
                mapMusic[arena] = player
            }
        }

        ambience = loadPlayer(named: "city_plaza_ambience")
        ambience?.numberOfLoops = -1
        ambience?.volume = ambienceBaseVolume

        windAmbience = loadPlayer(named: "city_wind_ambience")
        windAmbience?.numberOfLoops = -1
        windAmbience?.volume = windBaseVolume

        // Anticipation loop: calm and light — the lobby is a waiting room,
        // not a hype moment, so it stays well under the match music level.
        lobbyMusic = loadPlayer(named: "lobby_anticipation_loop")
        lobbyMusic?.numberOfLoops = -1
        lobbyMusic?.volume = lobbyBaseVolume

        for _ in 0..<4 {
            if let player = loadPlayer(named: "paint_splat_squish") {
                splatPool.append(player)
            }
        }

        for _ in 0..<3 {
            if let player = loadPlayer(named: "wet_paint_splat_hit") {
                hitPool.append(player)
            }
        }

        enemySplat = loadPlayer(named: "paint_balloon_splash")
        enemySplat?.volume = 0.9

        victory = loadPlayer(named: "arcade_victory_jingle")
        victory?.volume = 0.9

        let weaponSounds: [WeaponType: String] = [
            .blaster: "weapon_blaster_fire",
            .charger: "weapon_charger_fire",
            .rapid: "weapon_rapid_fire",
            .bucket: "weapon_bucket_fire",
            .dual: "weapon_dual_fire",
        ]
        for (weapon, name) in weaponSounds {
            var pool: [AVAudioPlayer] = []
            for _ in 0..<2 {
                if let player = loadPlayer(named: name) {
                    pool.append(player)
                }
            }
            weaponFirePools[weapon] = pool
            weaponFireIndex[weapon] = 0
        }

        for _ in 0..<3 {
            if let player = loadPlayer(named: "footstep_thud") {
                footstepPool.append(player)
            }
        }

        grenadeExplosion = loadPlayer(named: "grenade_explosion_thud")
        grenadeExplosion?.volume = 0.95

        spongeMove = loadPlayer(named: "sponge_swim_loop")
        spongeMove?.numberOfLoops = -1
        spongeMove?.volume = spongeMoveBaseVolume
    }

    private func loadPlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    /// Starts the dedicated theme for `arena`, falling back to the generic
    /// track if that map has no bundled theme yet.
    func playMatchMusic(for arena: ArenaMap) {
        guard !isMuted else { return }
        activeMapMusic?.stop()
        let player = mapMusic[arena] ?? music
        player?.currentTime = 0
        player?.play()
        activeMapMusic = player
    }

    func stopMusic() {
        activeMapMusic?.stop()
        music?.stop()
    }

    /// Looping outdoor bed (wind, distant city) under the match — two layered
    /// tracks (plaza hum + wind/foliage) for a richer environment.
    func playAmbience() {
        guard !isMuted else { return }
        ambience?.currentTime = 0
        ambience?.play()
        windAmbience?.currentTime = 0
        windAmbience?.play()
    }

    func stopAmbience() {
        ambience?.stop()
        windAmbience?.stop()
    }

    /// Waiting-room music for the loading/lobby screen — stops once the
    /// match's own music takes over.
    func playLobbyMusic() {
        guard !isMuted else { return }
        lobbyMusic?.currentTime = 0
        lobbyMusic?.play()
    }

    func stopLobbyMusic() {
        lobbyMusic?.stop()
    }

    /// Applies the settings panel's three independent volume sliders.
    func applyVolumes(master: Double, music musicSetting: Double, sfx sfxSetting: Double) {
        masterVolume = Float(max(0, min(1, master)))
        musicVolumeSetting = Float(max(0, min(1, musicSetting)))
        sfxVolumeSetting = Float(max(0, min(1, sfxSetting)))
        let musicMix = masterVolume * musicVolumeSetting
        music?.volume = musicBaseVolume * musicMix
        for player in mapMusic.values {
            player.volume = musicBaseVolume * musicMix
        }
        lobbyMusic?.volume = lobbyBaseVolume * musicMix
        ambience?.volume = ambienceBaseVolume * masterVolume * sfxVolumeSetting
        windAmbience?.volume = windBaseVolume * masterVolume * sfxVolumeSetting
        spongeMove?.volume = spongeMoveBaseVolume * masterVolume * sfxVolumeSetting
    }

    /// Wet impact thud when a character takes a hit — volume comes from the
    /// caller's distance-based spatial mix.
    func playHit(volume: Float) {
        guard !isMuted, volume > 0.02, !hitPool.isEmpty else { return }
        let player = hitPool[hitIndex]
        hitIndex = (hitIndex + 1) % hitPool.count
        player.volume = volume * masterVolume * sfxVolumeSetting
        player.currentTime = 0
        player.play()
    }

    func playSplat(volume: Float = 0.4) {
        guard !isMuted, volume > 0.02, !splatPool.isEmpty else { return }
        let player = splatPool[splatIndex]
        splatIndex = (splatIndex + 1) % splatPool.count
        player.volume = volume * masterVolume * sfxVolumeSetting
        player.currentTime = 0
        player.play()
    }

    func playEnemySplat(volume: Float = 0.9) {
        guard !isMuted, volume > 0.02 else { return }
        enemySplat?.volume = volume * masterVolume * sfxVolumeSetting
        enemySplat?.currentTime = 0
        enemySplat?.play()
    }

    func playVictory() {
        guard !isMuted else { return }
        victory?.currentTime = 0
        victory?.play()
    }

    /// Weapon-specific firing sound — each loadout gets its own texture
    /// (jet, charged thwomp, rapid rattle, bucket whoomp, pistol pop).
    func playWeaponFire(_ weapon: WeaponType, volume: Float = 0.5) {
        guard !isMuted, volume > 0.02, let pool = weaponFirePools[weapon], !pool.isEmpty else { return }
        let index = weaponFireIndex[weapon] ?? 0
        let player = pool[index]
        weaponFireIndex[weapon] = (index + 1) % pool.count
        player.volume = volume * masterVolume * sfxVolumeSetting
        player.currentTime = 0
        player.play()
    }

    /// Footstep while walking or running on foot (not diving, not swimming).
    func playFootstep(volume: Float = 0.3) {
        guard !isMuted, volume > 0.02, !footstepPool.isEmpty else { return }
        let player = footstepPool[footstepIndex]
        footstepIndex = (footstepIndex + 1) % footstepPool.count
        player.volume = volume * masterVolume * sfxVolumeSetting
        player.currentTime = 0
        player.play()
    }

    /// Dull, muffled explosion for the paint grenade — distinct from the
    /// sharper generic splash used for shield walls and gadget hits.
    func playGrenadeExplosion(volume: Float = 0.95) {
        guard !isMuted, volume > 0.02 else { return }
        grenadeExplosion?.volume = volume * masterVolume * sfxVolumeSetting
        grenadeExplosion?.currentTime = 0
        grenadeExplosion?.play()
    }

    /// Starts the looping muffled swim sound — idempotent, safe to call every
    /// frame while diving and moving.
    func startSpongeMove() {
        guard !isMuted, let player = spongeMove, !player.isPlaying else { return }
        player.volume = spongeMoveBaseVolume * masterVolume * sfxVolumeSetting
        player.play()
    }

    func stopSpongeMove() {
        spongeMove?.stop()
    }
}
