import Foundation
import QuartzCore
import UIKit

/// A timed slice of the per-frame simulation. Each case wraps one subsystem
/// call in `GameController.update(deltaTime:)` so a recording can say which
/// part of the CPU frame actually costs milliseconds.
nonisolated enum PerfSection: Int, CaseIterable {
    case player
    case bots
    case projectiles
    case paint
    case camera
    case weapons
    case vfx
    case nameTags
    case lod
    case scoring
    case network
    case hud
    case animation

    var label: String {
        switch self {
        case .player: "Joueur"
        case .bots: "Bots (IA)"
        case .projectiles: "Projectiles"
        case .paint: "Peinture"
        case .camera: "Caméra"
        case .weapons: "Armes / visée"
        case .vfx: "VFX"
        case .nameTags: "Étiquettes"
        case .lod: "LOD personnages"
        case .scoring: "Score / zones"
        case .network: "Réseau (duel)"
        case .hud: "Interface (SwiftUI)"
        case .animation: "Animations (clips)"
        }
    }
}

/// Static description of the run being measured — everything needed to make
/// sense of the numbers without asking the player follow-up questions.
nonisolated struct PerfRunContext: Sendable {
    let device: String
    let systemVersion: String
    let appVersion: String
    let quality: String
    let autoQuality: Bool
    let targetFPS: Int
    let displayMaxFPS: Int
    let map: String
    let mode: String
    let weapon: String
    let texturePaint: Bool
    let botCount: Int
    let isLocalDuel: Bool
    let isTraining: Bool
}

/// Records a full performance trace of a match — per-frame time, per-subsystem
/// CPU cost, process CPU/RAM — then renders it as a plain-text report the
/// player can copy out of a TestFlight build (where console logs are
/// unreachable).
///
/// Cost when idle is a single boolean check per measured section; nothing is
/// sampled and nothing is allocated unless a recording is armed and running.
@MainActor
@Observable
final class PerfRecorder {
    static let shared = PerfRecorder()

    private(set) var isRecording = false
    /// Latest finished report, persisted so it survives leaving the match.
    private(set) var lastReport: String?

    // MARK: - Accumulators

    private var context: PerfRunContext?
    private var startedAt: CFTimeInterval = 0
    /// Frame durations in seconds, capped so a long session can't grow
    /// without bound (12 000 frames ≈ 3 min at 60 FPS).
    private var frameTimes: [Double] = []
    private static let maxFrames = 12_000
    private var droppedFrameSamples = 0
    /// Frames ignored at the start of a trace. The first images of a match
    /// pay for lazy Metal pipeline compilation, texture residency and the
    /// first animation clip binding — one-off costs that used to dominate the
    /// "worst frame" column and hide the real steady-state behaviour.
    private static let warmupFrames = 60
    private var warmupRemaining = PerfRecorder.warmupFrames
    private var isWarm: Bool { warmupRemaining == 0 }

    private var sectionTotals = [Double](repeating: 0, count: PerfSection.allCases.count)
    private var sectionWorst = [Double](repeating: 0, count: PerfSection.allCases.count)
    private var sectionCalls = [Int](repeating: 0, count: PerfSection.allCases.count)

    private var cpuSamples: [Double] = []
    private var memorySamples: [Int] = []
    private var lastSystemSample: CFTimeInterval = 0

    private var maxProjectiles = 0
    private var maxBots = 0
    private var maxVFX = 0
    private var maxPaintTiles = 0
    private var paintUploads = 0
    private var paintStamps = 0

    /// Static-geometry batching result. Recorded at scene setup, i.e. before
    /// a trace is armed, so it lives outside the `isRecording` guard.
    private var batchAbsorbed = 0
    private var batchProduced = 0
    private var batchKept = 0

    private let defaults = UserDefaults.standard
    private let reportKey = "perf.lastReport"

    private init() {
        lastReport = defaults.string(forKey: reportKey)
    }

    // MARK: - Lifecycle

    /// Starts a trace. Ignored if one is already running.
    func start(context: PerfRunContext) {
        guard !isRecording else { return }
        self.context = context
        startedAt = CACurrentMediaTime()
        frameTimes.removeAll(keepingCapacity: true)
        frameTimes.reserveCapacity(Self.maxFrames)
        droppedFrameSamples = 0
        warmupRemaining = Self.warmupFrames
        for i in sectionTotals.indices {
            sectionTotals[i] = 0
            sectionWorst[i] = 0
            sectionCalls[i] = 0
        }
        cpuSamples.removeAll(keepingCapacity: true)
        memorySamples.removeAll(keepingCapacity: true)
        lastSystemSample = 0
        maxProjectiles = 0
        maxBots = 0
        maxVFX = 0
        maxPaintTiles = 0
        paintUploads = 0
        paintStamps = 0
        isRecording = true
    }

    /// Ends the trace and renders the report. Safe to call when not recording.
    func finish() {
        guard isRecording else { return }
        isRecording = false
        guard frameTimes.count > 30, let context else { return }
        let report = buildReport(context: context)
        lastReport = report
        defaults.set(report, forKey: reportKey)
    }

    func clearReport() {
        lastReport = nil
        defaults.removeObject(forKey: reportKey)
    }

    // MARK: - Sampling

    /// Times `body` against a subsystem. Transparent when not recording.
    @inline(__always)
    @discardableResult
    func measure<T>(_ section: PerfSection, _ body: () -> T) -> T {
        guard isRecording, isWarm else { return body() }
        let start = CACurrentMediaTime()
        let result = body()
        let cost = CACurrentMediaTime() - start
        let i = section.rawValue
        sectionTotals[i] += cost
        sectionCalls[i] += 1
        if cost > sectionWorst[i] { sectionWorst[i] = cost }
        return result
    }

    /// Records one displayed frame plus, at 1 Hz, a process CPU/RAM sample.
    func noteFrame(rawDt: Float) {
        guard isRecording else { return }
        guard isWarm else {
            warmupRemaining -= 1
            return
        }
        if frameTimes.count < Self.maxFrames {
            frameTimes.append(Double(rawDt))
        } else {
            droppedFrameSamples += 1
        }
        let now = CACurrentMediaTime()
        guard now - lastSystemSample >= 1 else { return }
        lastSystemSample = now
        cpuSamples.append(PerfSampler.cpuUsagePercent())
        memorySamples.append(PerfSampler.memoryFootprintMB())
    }

    /// Records what the static batcher did to the arena at setup. Always
    /// stored (a trace is usually armed after the scene is built) and read
    /// back into whichever report comes next.
    func noteBatching(absorbed: Int, produced: Int, keptAsIs: Int) {
        batchAbsorbed = absorbed
        batchProduced = produced
        batchKept = keptAsIs
    }

    /// Tracks the peak scene load so the report can correlate cost with what
    /// was actually on screen.
    func noteCounts(projectiles: Int, bots: Int, vfx: Int, paintTiles: Int, uploads: Int, stamps: Int) {
        guard isRecording else { return }
        if projectiles > maxProjectiles { maxProjectiles = projectiles }
        if bots > maxBots { maxBots = bots }
        if vfx > maxVFX { maxVFX = vfx }
        if paintTiles > maxPaintTiles { maxPaintTiles = paintTiles }
        paintUploads = uploads
        paintStamps = stamps
    }

    // MARK: - Report

    private func buildReport(context ctx: PerfRunContext) -> String {
        let duration = CACurrentMediaTime() - startedAt
        let sorted = frameTimes.sorted()
        let count = Double(sorted.count)
        let total = sorted.reduce(0, +)
        let avg = total / count
        func percentile(_ p: Double) -> Double {
            let idx = min(sorted.count - 1, max(0, Int((p * count).rounded(.down))))
            return sorted[idx]
        }
        func ms(_ seconds: Double) -> String { String(format: "%.2f", seconds * 1000) }
        func pct(_ value: Double) -> String { String(format: "%.1f", value) }

        let over20 = Double(sorted.filter { $0 > 1.0 / 50 }.count) / count * 100
        let over33 = Double(sorted.filter { $0 > 1.0 / 30 }.count) / count * 100

        var lines: [String] = []
        lines.append("=== RAPPORT PERF SPLASH ===")
        lines.append("Appareil: \(ctx.device) · iOS \(ctx.systemVersion) · app \(ctx.appVersion)")
        lines.append("Preset: \(ctx.quality)\(ctx.autoQuality ? " (auto)" : " (manuel)") · cible \(ctx.targetFPS) FPS · écran \(ctx.displayMaxFPS) Hz")
        lines.append("Carte: \(ctx.map) · mode: \(ctx.mode) · arme: \(ctx.weapon)")
        lines.append("Peinture texturée: \(ctx.texturePaint ? "oui" : "non") · bots: \(ctx.botCount) · duel local: \(ctx.isLocalDuel ? "oui" : "non") · entraînement: \(ctx.isTraining ? "oui" : "non")")
        lines.append("")
        lines.append("-- IMAGES --")
        lines.append("Durée mesurée: \(String(format: "%.0f", duration)) s · \(sorted.count) images\(droppedFrameSamples > 0 ? " (+\(droppedFrameSamples) non échantillonnées)" : "")")
        lines.append("(\(Self.warmupFrames) images de chauffe exclues — compilation shaders, chargement textures)")
        lines.append("FPS moyen: \(String(format: "%.1f", 1 / avg))")
        lines.append("Temps/image  moy \(ms(avg)) ms · médiane \(ms(percentile(0.5))) ms · p95 \(ms(percentile(0.95))) ms · p99 \(ms(percentile(0.99))) ms · pire \(ms(sorted[sorted.count - 1])) ms")
        lines.append("Images > 20 ms (sous 50 FPS): \(pct(over20)) %")
        lines.append("Images > 33 ms (sous 30 FPS): \(pct(over33)) %")
        lines.append("")
        lines.append("-- CPU / MÉMOIRE --")
        if cpuSamples.isEmpty {
            lines.append("(aucun échantillon)")
        } else {
            let cpuAvg = cpuSamples.reduce(0, +) / Double(cpuSamples.count)
            let cpuMax = cpuSamples.max() ?? 0
            let memAvg = memorySamples.reduce(0, +) / max(memorySamples.count, 1)
            let memMax = memorySamples.max() ?? 0
            lines.append("CPU processus: moy \(pct(cpuAvg)) % · max \(pct(cpuMax)) % (100 % = 1 cœur)")
            lines.append("Mémoire: moy \(memAvg) Mo · max \(memMax) Mo")
        }
        lines.append("")
        lines.append("-- COÛT CPU PAR SOUS-SYSTÈME (par image) --")
        let simTotal = sectionTotals.reduce(0, +)
        let ranked = PerfSection.allCases
            .map { ($0, sectionTotals[$0.rawValue], sectionCalls[$0.rawValue], sectionWorst[$0.rawValue]) }
            .filter { $0.2 > 0 }
            .sorted { $0.1 > $1.1 }
        for (section, seconds, calls, worst) in ranked {
            let perFrame = seconds / count
            let share = simTotal > 0 ? seconds / simTotal * 100 : 0
            lines.append("\(section.label.padded(to: 16)) \(ms(perFrame).padded(to: 7)) ms/img · \(pct(share).padded(to: 5)) % du CPU jeu · pire \(ms(worst)) ms · \(calls) appels")
        }
        let simPerFrame = simTotal / count
        lines.append("")
        lines.append("TOTAL CPU mesuré (jeu + interface): \(ms(simPerFrame)) ms/img (\(pct(simPerFrame / avg * 100)) % du temps image)")
        lines.append("Reste (rendu RealityKit + attente GPU): \(ms(max(0, avg - simPerFrame))) ms/img (\(pct(max(0, avg - simPerFrame) / avg * 100)) %)")
        lines.append("→ Si ce 'reste' domine, le goulot est le rendu/GPU, pas la logique de jeu.")
        lines.append("")
        lines.append("-- CHARGE DE SCÈNE (pics) --")
        lines.append("Projectiles max: \(maxProjectiles) · bots max: \(maxBots) · VFX simultanés max: \(maxVFX)")
        if batchAbsorbed > 0 || batchKept > 0 {
            let saved = max(0, batchAbsorbed - batchProduced)
            lines.append("Arène fusionnée: \(batchAbsorbed) objets → \(batchProduced) meshes (\(saved) draw calls en moins/img) · \(batchKept) non fusionnables")
        }
        lines.append("Peinture: \(paintStamps) taches · \(paintUploads) uploads texture · \(maxPaintTiles) dalles peintes")
        lines.append("=== FIN ===")
        return lines.joined(separator: "\n")
    }
}

private extension String {
    /// Right-pads with spaces so the report's columns line up in a monospaced
    /// paste — plain text is the only format that survives a copy from
    /// TestFlight into a chat window.
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
