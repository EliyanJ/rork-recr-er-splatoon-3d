import Foundation

/// Player camera perspectives — close over-the-shoulder or true first person.
enum CameraMode: String, Codable, CaseIterable, Identifiable {
    case thirdPerson
    case firstPerson

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thirdPerson: "Épaule"
        case .firstPerson: "1re pers."
        }
    }

    var iconSystemName: String {
        switch self {
        case .thirdPerson: "person.fill.viewfinder"
        case .firstPerson: "eye.fill"
        }
    }

    var toggled: CameraMode {
        self == .thirdPerson ? .firstPerson : .thirdPerson
    }
}
