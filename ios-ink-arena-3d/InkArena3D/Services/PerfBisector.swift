import Foundation
import QuartzCore
import RealityKit
import UIKit

/// Finds what the frame is actually spent on, by subtraction.
///
/// WHY — iOS refuses to tell an app how busy the GPU is, and our own CPU
/// timings only account for a fifth of the frame. Guessing which layer is
/// responsible has already cost one build (merging the arena's static geometry
/// removed 100 draw calls and changed nothing measurable), so this measures.
///
/// WHY v2 — the first version measured each layer once, for six seconds, with
/// a single reference at each end of the sweep. Those two references came out
/// 7.4 ms apart on identical scenes, i.e. the drift of a live match (fights
/// getting busier, thermals, streaming) was larger than every effect being
/// looked for. It duly reported that hiding the arena and the sky made the
/// game *slower*, which cannot happen. The redesign attacks that directly:
///
/// - every layer phase is bracketed by its OWN reference phases, so it is
///   compared against the match as it was seconds earlier, not minutes;
/// - each layer is measured over several passes, and the spread between those
///   passes is printed — a result narrower than the spread is not a result;
/// - phases are summarised by median, not mean, so one 200 ms hitch cannot
///   invent a difference;
/// - the sweep includes a "hide everything" control. If hiding the entire
///   picture does not recover the frame, no amount of geometry work will, and
///   the whole rendering theory dies on the spot.
///
/// SAFETY — a layer is hidden by detaching its `ModelComponent`s only, never
/// by disabling entities. Colliders, physics, animations and every gameplay
/// system keep running exactly as before: the match stays honest, only the
/// picture changes. Components are stashed and put back verbatim.
@MainActor
@Observable
final class PerfBisector {
    static let shared = PerfBisector()

    /// One switchable slice of the picture.
    struct Layer {
        let label: String
        /// Resolved at phase start — bots and VFX come and go mid-match.
        let roots: () -> [Entity]
    }

    private enum Kind {
        case reference
        /// Index into `layers`.
        case layer(Int)
        /// Every registered layer at once — the decisive control.
        case everything
    }

    private struct Phase {
        let kind: Kind
        let label: String
        let pass: Int
    }

    private(set) var isRunning = false
    /// Short label for the on-screen badge, e.g. "sans décor".
    private(set) var currentPhaseLabel: String?

    /// How many times each layer is measured. Two passes are enough to expose
    /// a fluke; more would outlast a match.
    private static let passes = 2
    /// Seconds measured per layer phase.
    private static let layerMeasure: Double = 4
    /// Reference phases are shorter — there are twice as many of them.
    private static let referenceMeasure: Double = 2.5
    /// Seconds discarded right after a switch: detaching meshes makes
    /// RealityKit re-cook its render list for an image or two.
    private static let settleDuration: Double = 1

    private var layers: [Layer] = []
    private var phases: [Phase] = []
    private var phaseIndex = 0
    private var phaseClock: Double = 0
    private var samples: [[Double]] = []
    private var context: PerfRunContext?
    private var stashed: [ObjectIdentifier: ModelComponent] = [:]

    private init() {}

    // MARK: - Setup

    /// Registers the switchable layers for the match about to start.
    func configure(layers: [Layer]) {
        guard !isRunning else { return }
        self.layers = layers
    }

    /// Begins the sweep. Ignored when already running or unconfigured.
    func start(context: PerfRunContext) {
        guard !isRunning, !layers.isEmpty else { return }
        self.context = context
        phases = buildPhases()
        samples = Array(repeating: [], count: phases.count)
        phaseIndex = 0
        phaseClock = 0
        isRunning = true
        currentPhaseLabel = phases[0].label
    }

    /// Interleaves a reference before and after every measurement, so each
    /// layer is judged against its immediate neighbourhood in the match.
    private func buildPhases() -> [Phase] {
        var result: [Phase] = [Phase(kind: .reference, label: "Référence", pass: 0)]
        for pass in 0..<Self.passes {
            for (index, layer) in layers.enumerated() {
                result.append(Phase(kind: .layer(index), label: "Sans \(layer.label)", pass: pass))
                result.append(Phase(kind: .reference, label: "Référence", pass: pass))
            }
            result.append(Phase(kind: .everything, label: "Tout masqué", pass: pass))
            result.append(Phase(kind: .reference, label: "Référence", pass: pass))
        }
        return result
    }

    /// Advances the sweep by one displayed frame.
    func tick(rawDt: Float) {
        guard isRunning else { return }
        phaseClock += Double(rawDt)
        if phaseClock > Self.settleDuration {
            samples[phaseIndex].append(Double(rawDt))
        }
        guard phaseClock >= Self.settleDuration + measureDuration(phases[phaseIndex]) else { return }
        advance()
    }

    private func measureDuration(_ phase: Phase) -> Double {
        switch phase.kind {
        case .reference: return Self.referenceMeasure
        case .layer, .everything: return Self.layerMeasure
        }
    }

    /// Restores every hidden layer and drops the run. Called when the match
    /// ends early so the scene can never be left with missing geometry.
    ///
    /// A sweep cut short still reports: a partial table with honest error bars
    /// beats no data, and the match timer is not always generous.
    func cancel() {
        guard isRunning else { return }
        restoreAll()
        isRunning = false
        currentPhaseLabel = nil
        if let context, samples.contains(where: { $0.count > 30 }) {
            PerfRecorder.shared.storeBisection(buildReport(context: context, truncated: true))
        }
    }

    // MARK: - Phase machine

    private func advance() {
        restoreAll()
        phaseIndex += 1
        phaseClock = 0
        guard phaseIndex < phases.count else {
            finish()
            return
        }
        let phase = phases[phaseIndex]
        currentPhaseLabel = phase.label
        switch phase.kind {
        case .reference:
            break
        case .layer(let index):
            guard layers.indices.contains(index) else { break }
            for root in layers[index].roots() { detachMeshes(root) }
        case .everything:
            for layer in layers {
                for root in layer.roots() { detachMeshes(root) }
            }
        }
    }

    private func finish() {
        isRunning = false
        currentPhaseLabel = nil
        guard let context else { return }
        PerfRecorder.shared.storeBisection(buildReport(context: context, truncated: false))
    }

    // MARK: - Hiding

    /// Removes (and remembers) every `ModelComponent` in a subtree. Leaves
    /// colliders, physics and animation components untouched.
    private func detachMeshes(_ entity: Entity) {
        if let model = entity.components[ModelComponent.self] {
            stashed[ObjectIdentifier(entity)] = model
            entity.components.remove(ModelComponent.self)
        }
        for child in entity.children {
            detachMeshes(child)
        }
    }

    private func restoreAll() {
        guard !stashed.isEmpty else { return }
        // The entity map is rebuilt from the live scene rather than kept as
        // strong references, so an entity destroyed mid-phase (a bot that
        // died) simply drops out instead of being resurrected.
        for layer in layers {
            for root in layer.roots() { reattachMeshes(root) }
        }
        stashed.removeAll(keepingCapacity: true)
    }

    private func reattachMeshes(_ entity: Entity) {
        if let model = stashed[ObjectIdentifier(entity)] {
            entity.components.set(model)
        }
        for child in entity.children {
            reattachMeshes(child)
        }
    }

    // MARK: - Statistics

    /// Median frame time, or 0 for a phase with too few samples to trust.
    private func median(_ index: Int) -> Double {
        let values = samples[index].sorted()
        guard values.count >= 30 else { return 0 }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }

    /// Mean of the reference phases directly before and after `index`, so a
    /// layer is compared with the match as it was seconds away, not minutes.
    private func localBaseline(for index: Int) -> Double {
        var found: [Double] = []
        for step in stride(from: index - 1, through: 0, by: -1) where isReference(step) {
            let value = median(step)
            if value > 0 { found.append(value) }
            break
        }
        for step in (index + 1)..<phases.count where isReference(step) {
            let value = median(step)
            if value > 0 { found.append(value) }
            break
        }
        guard !found.isEmpty else { return 0 }
        return found.reduce(0, +) / Double(found.count)
    }

    private func isReference(_ index: Int) -> Bool {
        if case .reference = phases[index].kind { return true }
        return false
    }

    /// Share of frames that made the 60 Hz deadline.
    private func onTimeShare(_ index: Int) -> Double {
        let values = samples[index]
        guard !values.isEmpty else { return 0 }
        let onTime = values.filter { $0 <= 1.0 / 58.0 }.count
        return Double(onTime) / Double(values.count) * 100
    }

    // MARK: - Report

    private func buildReport(context ctx: PerfRunContext, truncated: Bool) -> String {
        func ms(_ seconds: Double) -> String { String(format: "%.2f", seconds * 1000) }
        func signed(_ seconds: Double) -> String {
            (seconds >= 0 ? "-" : "+") + ms(abs(seconds))
        }

        let referenceValues = phases.indices.filter { isReference($0) }.map { median($0) }.filter { $0 > 0 }
        let referenceMean = referenceValues.isEmpty ? 0 : referenceValues.reduce(0, +) / Double(referenceValues.count)
        // The honest noise floor: how much the untouched scene wandered on its
        // own across the sweep. Any "gain" smaller than this is not a gain.
        let drift = (referenceValues.max() ?? 0) - (referenceValues.min() ?? 0)

        /// Per-layer gains, one entry per pass, against the local baseline.
        var gains: [String: [Double]] = [:]
        var order: [String] = []
        for index in phases.indices {
            let value = median(index)
            guard value > 0 else { continue }
            let label: String
            switch phases[index].kind {
            case .reference: continue
            case .layer(let layerIndex):
                guard layers.indices.contains(layerIndex) else { continue }
                label = layers[layerIndex].label
            case .everything:
                label = "TOUT (contrôle)"
            }
            let baseline = localBaseline(for: index)
            guard baseline > 0 else { continue }
            if gains[label] == nil { order.append(label) }
            gains[label, default: []].append(baseline - value)
        }

        var lines: [String] = []
        lines.append("=== TEST GPU PAR SOUSTRACTION (v2) ===")
        lines.append("Appareil: \(ctx.device) · iOS \(ctx.systemVersion) · app \(ctx.appVersion)")
        lines.append("Preset: \(ctx.quality)\(ctx.autoQuality ? " (auto)" : " (manuel)") · carte: \(ctx.map) · bots: \(ctx.botCount)")
        lines.append("Peinture texturée: \(ctx.texturePaint ? "oui" : "non")")
        if truncated {
            lines.append("⚠︎ Partie terminée avant la fin du test — tableau partiel.")
        }
        lines.append("Méthode: chaque couche est masquée \(Self.passes) fois, encadrée à chaque fois")
        lines.append("par une mesure de la scène complète. Médianes (insensibles aux à-coups).")
        lines.append("")

        lines.append("-- FIABILITÉ DE LA MESURE --")
        if referenceMean > 0 {
            lines.append("Scène complète: \(ms(referenceMean)) ms/img · \(String(format: "%.1f", 1 / referenceMean)) FPS · \(referenceValues.count) mesures")
        }
        lines.append("Dérive de la scène complète: \(ms(drift)) ms")
        lines.append("→ SEUIL DE CRÉDIBILITÉ: un gain sous \(ms(drift)) ms est du bruit, pas un résultat.")
        lines.append("")

        lines.append("-- GAIN EN MASQUANT CHAQUE COUCHE --")
        lines.append("(gain positif = l'image devient plus rapide sans la couche)")
        for label in order {
            guard let values = gains[label], !values.isEmpty else { continue }
            let mean = values.reduce(0, +) / Double(values.count)
            let spread = (values.max() ?? 0) - (values.min() ?? 0)
            let detail = values.map { signed($0) }.joined(separator: " / ")
            let verdict = mean > drift ? "RÉEL" : "bruit"
            lines.append("\(label.padded(to: 18)) \(signed(mean).padded(to: 8)) ms · passes: \(detail.padded(to: 18)) · écart \(ms(spread)) ms · \(verdict)")
        }
        lines.append("")

        lines.append("-- RESPECT DU 60 Hz --")
        lines.append("Un écran 60 Hz n'affiche qu'à 16.67 ms. Rater ce budget d'un cheveu")
        lines.append("fait retomber l'image sur le battement suivant, à 33.3 ms.")
        let referenceOnTime = phases.indices.filter { isReference($0) }.map { onTimeShare($0) }
        if !referenceOnTime.isEmpty {
            let share = referenceOnTime.reduce(0, +) / Double(referenceOnTime.count)
            lines.append("Images dans les temps (scène complète): \(String(format: "%.1f", share)) %")
        }
        for index in phases.indices {
            guard case .everything = phases[index].kind, samples[index].count >= 30 else { continue }
            lines.append("Images dans les temps (tout masqué): \(String(format: "%.1f", onTimeShare(index))) %")
            break
        }
        lines.append("")

        lines.append("-- LECTURE --")
        let control = gains["TOUT (contrôle)"].map { $0.reduce(0, +) / Double($0.count) } ?? 0
        if control <= drift {
            lines.append("Masquer TOUTE l'image ne rend rien: le coût n'est pas dans le rendu.")
            lines.append("Il faut chercher côté moteur (mise à jour de scène, animations, upload")
            lines.append("de la texture de peinture) plutôt que côté géométrie ou pixels.")
        } else {
            let real = order
                .filter { $0 != "TOUT (contrôle)" }
                .compactMap { label -> (String, Double)? in
                    guard let values = gains[label], !values.isEmpty else { return nil }
                    let mean = values.reduce(0, +) / Double(values.count)
                    return mean > drift ? (label, mean) : nil
                }
                .sorted { $0.1 > $1.1 }
            if let best = real.first {
                lines.append("Couche réellement coûteuse: \(best.0) (\(ms(best.1)) ms/img).")
                lines.append("Tout masquer rend \(ms(control)) ms: c'est le plafond du gain possible.")
            } else {
                lines.append("Tout masquer rend \(ms(control)) ms, mais aucune couche seule ne dépasse")
                lines.append("le bruit: le coût est réparti, pas concentré sur une couche.")
            }
        }
        lines.append("=== FIN ===")
        return lines.joined(separator: "\n")
    }
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
