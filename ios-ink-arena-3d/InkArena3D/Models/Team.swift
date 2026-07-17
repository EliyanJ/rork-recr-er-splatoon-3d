import SwiftUI
import UIKit

/// The two ink teams fighting for turf coverage.
enum Team: Hashable {
    case orange
    case purple

    var opponent: Team {
        self == .orange ? .purple : .orange
    }

    var uiColor: UIColor {
        switch self {
        case .orange: UIColor(red: 1.0, green: 0.47, blue: 0.02, alpha: 1)
        case .purple: UIColor(red: 0.58, green: 0.15, blue: 1.0, alpha: 1)
        }
    }

    var color: Color {
        Color(uiColor: uiColor)
    }
}

extension Color {
    /// Builds a color from a "RRGGBB" hex string — used for the player's
    /// customizable accent color, persisted as plain text in the profile.
    init(hex: String) {
        var value = UInt64()
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

/// Preset accent colors offered in the locker room — distinct, saturated
/// hues that read well against the arena's cool palette.
enum AccentPreset: String, CaseIterable, Identifiable {
    case blaze = "FF7A1A"
    case neon = "1AF0C4"
    case violet = "9A3DF5"
    case crimson = "F5304B"
    case gold = "F5C518"
    case ice = "3DB8F5"

    var id: String { rawValue }
    var color: Color { Color(hex: rawValue) }
}
