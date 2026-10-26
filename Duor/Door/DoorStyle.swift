import SwiftUI

/// A visual and audio theme for the door. The MVP ships one style.
/// New styles (barn door, castle gate, window, fridge…) are added as new cases.
enum DoorStyle: String, CaseIterable, Identifiable, Sendable {
    case oakWithIronHinges

    static let storageKey = "doorStyle"

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .oakWithIronHinges: "Oak door, iron hinges"
        }
    }

    /// Materials and tuning for the synthesized sounds.
    var soundProfile: SoundProfile {
        switch self {
        case .oakWithIronHinges: .oak
        }
    }

    var palette: DoorPalette {
        switch self {
        case .oakWithIronHinges:
            DoorPalette(
                wood: Color(red: 0.55, green: 0.33, blue: 0.18),
                woodShade: Color(red: 0.38, green: 0.21, blue: 0.10),
                metal: Color(white: 0.22),
                frame: Color(red: 0.92, green: 0.89, blue: 0.84)
            )
        }
    }
}

struct DoorPalette: Sendable {
    var wood: Color
    var woodShade: Color
    var metal: Color
    var frame: Color
}
