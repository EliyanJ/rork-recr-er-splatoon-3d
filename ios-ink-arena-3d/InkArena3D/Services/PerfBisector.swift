import Foundation
import QuartzCore
import RealityKit
import UIKit

/// Finds what the GPU is actually spending the frame on, by subtraction.
///
/// WHY — iOS refuses to tell an app how busy the GPU is, and our own CPU
/// timings only account for a fifth of the frame. Everything else is a black
/// box: RealityKit submitting draw calls and the GPU shading pixels. Guessing
/// which layer is responsible has already cost one build (merging the arena's
/// static geometry removed 100 draw calls and changed nothing measurable), so
/// this stops guessing and measures.
///
/// HOW — during a single live match it hides one visual layer at a time for a
/// few seconds each and records the frame time of every phase. A layer that
/// costs nothing leaves the frame time flat; the layer that IS the bottleneck
/// makes it collapse. The sequence opens and closes on a full-scene reference
/// phase, so drift (a fight getting busier, thermal throttling) is visible
/// instead of being mistaken for a result.
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

    private struct Phase {
        let label: String
        let layer: Layer?
    }

    private(set) var isRunning = false
    /// Short label for the on-screen badge, e.g. "sans décor".
    private(set) var currentPhaseLabel: String?

    /// Seconds each phase is measured for.
    private static let measureDuration: Double = 6
    /// Seconds discarded right after a switch — detaching meshes makes
    /// RealityKit re-cook its render list for an image or two.
    private static let settleDuration: Double = 1.5

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
        phases = [Phase(label: "Référence (début)", layer: nil)]
        phases.append(contentsOf: layers.map { Phase(label: "Sans \($0.label)", layer: $0) })
        phases.append(Phase(label: "Référence (fin)", layer: nil))
        samples = Array(repeating: [], count: phases.count)
        phaseIndex = 0
        phaseClock = 0
        isRunning = true
        currentPhaseLabel = phases[0].label
    }

    /// Advances the sweep by one displayed frame.
    func tick(rawDt: Float) {
        guard isRunning else { return }
        phaseClock += Double(rawDt)
        if phaseClock > Self.settleDuration {
            samples[phaseIndex].append(Double(rawDt))
        }
        guard phaseClock >= Self.settleDuration + Self.measureDuration else { return }
        advance()
    }

    /// Restores every hidden layer and drops the run. Called when the match
    /// ends early so the scene can never be left with missing geometry.
    func cancel() {
        guard isRunning else { return }
        restoreAll()
        isRunning = false
        currentPhaseLabel = nil
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
        if let layer = phase.layer {
            for root in layer.roots() { detachMeshes(root) }
        }
    }

    private func finish() {
        isRunning = false
        currentPhaseLabel = nil
        guard let context else { return }
        PerfRecorder.shared.storeBisection(buildReport(context: context))
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

    // MARK: - Report

    private func buildReport(context ctx: PerfRunContext) -> String {
        func ms(_ seconds: Double) -> String { String(format: "%.2f", seconds * 1000) }
        func average(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }

        let averages = samples.map(average)
        // Both reference phases average out slow drift across the sweep.
        let referenceIndices = phases.indices.filter { phases[$0].layer == nil }
        let reference = average(referenceIndices.map { averages[$0] }.filter { $0 > 0 })

        var lines: [String] = []
        lines.append("=== TEST GPU PAR SOUSTRACTION ===")
        lines.append("Appareil: \(ctx.device) · iOS \(ctx.systemVersion) · app \(ctx.appVersion)")
        lines.append("Preset: \(ctx.quality)\(ctx.autoQuality ? " (auto)" : " (manuel)") · carte: \(ctx.map) · bots: \(ctx.botCount)")
        lines.append("Peinture texturée: \(ctx.texturePaint ? "oui" : "non")")
        lines.append("Chaque couche est masquée \(Int(Self.measureDuration)) s (rendu seul — collisions, bots et tirs continuent).")
        lines.append("")
        lines.append("-- TEMPS PAR IMAGE --")
        if reference > 0 {
            lines.append("Référence (scène complète): \(ms(reference)) ms/img · \(String(format: "%.1f", 1 / reference)) FPS")
            lines.append("")
        }
        for (index, phase) in phases.enumerated() {
            let value = averages[index]
            guard value > 0 else { continue }
            let frames = samples[index].count
            if phase.layer == nil {
                lines.append("\(phase.label.padded(to: 30)) \(ms(value).padded(to: 7)) ms/img · \(frames) img")
            } else {
                let saved = reference - value
                let share = reference > 0 ? saved / reference * 100 : 0
                let sign = saved >= 0 ? "-" : "+"
                lines.append("\(phase.label.padded(to: 30)) \(ms(value).padded(to: 7)) ms/img · \(sign)\(ms(abs(saved))) ms (\(String(format: "%.0f", abs(share))) %) · \(frames) img")
            }
        }
        lines.append("")
        let costs = phases.indices
            .filter { phases[$0].layer != nil && averages[$0] > 0 }
            .map { (phases[$0].label, reference - averages[$0]) }
            .sorted { $0.1 > $1.1 }
        if let worst = costs.first, worst.1 > 0 {
            lines.append("→ Couche la plus coûteuse: \(worst.0.replacingOccurrences(of: "Sans ", with: "")) (\(ms(worst.1)) ms/img)")
        }
        lines.append("→ Une couche dont le retrait ne change rien n'est PAS le goulot.")
        lines.append("=== FIN ===")
        return lines.joined(separator: "\n")
    }
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
