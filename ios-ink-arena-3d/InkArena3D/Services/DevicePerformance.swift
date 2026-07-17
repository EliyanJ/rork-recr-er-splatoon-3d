import Foundation

/// Reads the raw hardware model identifier and maps it to a recommended
/// `GraphicsQuality` preset, computed once and cached. This is only ever the
/// STARTING point before any manual override: the player can force a
/// different preset in Settings, and turning "Ajustement automatique" back on
/// re-applies this recommendation at the next match.
enum DevicePerformance {
    /// Graphics preset the game should default to before any manual override.
    static let recommendedQuality: GraphicsQuality = computeQuality()

    // MARK: - Detection

    private static func computeQuality() -> GraphicsQuality {
        guard let identifier = modelIdentifier() else { return .ultra }
        // Simulator/iPad identifiers don't match the iPhone<major>,<minor>
        // pattern; assume capable hardware rather than degrading the preview.
        guard identifier.hasPrefix("iPhone") else { return .ultra }

        // iPhone<major>,<minor>. The major generation maps (best-effort,
        // no per-model Pro/non-Pro split available from the identifier
        // alone) to a starting preset:
        //   ≤12  → A13 and older (iPhone 11 / SE2 and below)   → lite
        //   13   → A14 (iPhone 12 family)                       → performance
        //   14   → A15 (iPhone 13 / 14 / SE3)                   → standard
        //   ≥15  → A16 and newer (iPhone 14 Pro / 15 / 16+)     → ultra
        let digits = identifier.dropFirst("iPhone".count).prefix { $0.isNumber }
        guard let major = Int(digits) else { return .ultra }
        switch major {
        case ..<13: return .lite
        case 13: return .performance
        case 14: return .standard
        default: return .ultra
        }
    }

    /// Raw hardware model identifier (e.g. "iPhone14,5"). On the simulator this
    /// resolves to the host model identifier when available.
    private static func modelIdentifier() -> String? {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine.isEmpty ? nil : machine
    }
}
