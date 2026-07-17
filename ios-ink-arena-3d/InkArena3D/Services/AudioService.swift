import AVFoundation

/// Plays bundled music and sound effects for the match.
@MainActor
final class AudioService {
    static let shared = AudioService()

    private var music: AVAudioPlayer?
    private var ambience: AVAudioPlayer?
    /// Secondary environmental bed — wind through foliage layered under the
    /// city plaza ambience for a richer, less flat soundscape.
    private var windAmbience: AVAudioPlayer?
    private var lobbyMusic: AVAudioPlayer?
    private var splatPool: [AVAudioPlayer] = []
    private var splatIndex = 0
    private var hitPool: [AVAudioPlayer] = []
    private var hitIndex = 0
    private var enemySplat: AVAudioPlayer?
    private var victory: AVAudioPlayer?

    /// Profile setting: silences every player when true.
    var isMuted = false {
        didSet {
            if isMuted {
                music?.stop()
                ambience?.stop()
                windAmbience?.stop()
                lobbyMusic?.stop()
            }
        }
    }

    /// Independent volume sliders (0...1) from the settings panel — combined
    /// multiplicatively with each player's base mix level.
    private var masterVolume: Float = 1
    private var musicVolumeSetting: Float = 1
    private var sfxVolumeSetting: Float = 1
    private let musicBaseVolume: Float = 0.5
    private let ambienceBaseVolume: Float = 0.26
    private let windBaseVolume: Float = 0.16

    private init() {
        // .playback keeps the game audible even with the ring/silent switch
        // muted — the reason the music previously seemed silent on device.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        music = loadPlayer(named: "ink_battle_funky_theme")
        music?.numberOfLoops = -1
        music?.volume = 0.5

        ambience = loadPlayer(named: "city_plaza_ambience")
        ambience?.numberOfLoops = -1
        ambience?.volume = 0.26

        windAmbience = loadPlayer(named: "city_wind_ambience")
        windAmbience?.numberOfLoops = -1
        windAmbience?.volume = windBaseVolume

        lobbyMusic = loadPlayer(named: "lobby_anticipation_loop")
        lobbyMusic?.numberOfLoops = -1
        lobbyMusic?.volume = 0.45

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
    }

    private func loadPlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    func playMusic() {
        guard !isMuted else { return }
        music?.currentTime = 0
        music?.play()
    }

    func stopMusic() {
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
        lobbyMusic?.volume = 0.45 * musicMix
        ambience?.volume = ambienceBaseVolume * masterVolume * sfxVolumeSetting
        windAmbience?.volume = windBaseVolume * masterVolume * sfxVolumeSetting
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
}
