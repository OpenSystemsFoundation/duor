import SwiftUI

/// The kind of door: how it's built, what it's made of, and how it sounds.
enum DoorStyle: String, CaseIterable, Identifiable, Sendable {
    case oak
    case cottage
    case barn
    case castle
    case modern

    static let storageKey = "doorStyle"

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .oak: "Oak"
        case .cottage: "Cottage"
        case .barn: "Barn"
        case .castle: "Castle"
        case .modern: "Modern"
        }
    }

    /// How the leaf is built.
    var design: DoorDesign {
        switch self {
        case .oak: .fourPanel
        case .cottage: .glazed
        case .barn: .planks
        case .castle: .studded
        case .modern: .slab
        }
    }

    /// The hardware it comes with. Picking a door resets the hardware to this.
    var defaultHardware: HardwareFinish {
        switch self {
        case .oak: .iron
        case .cottage: .brass
        case .barn: .iron
        case .castle: .bronze
        case .modern: .chrome
        }
    }

    /// What's behind it. Picking a door resets the scene to this.
    var defaultScene: InsideScene {
        switch self {
        case .oak: .livingRoom
        case .cottage: .beach
        case .barn: .forest
        case .castle: .greatHall
        case .modern: .space
        }
    }

    /// Wood (or paint) and the color of the frame around it.
    var surface: (wood: Color, shade: Color, frame: Color, isPainted: Bool) {
        switch self {
        case .oak:
            (
                Color(red: 0.55, green: 0.33, blue: 0.18), Color(red: 0.38, green: 0.21, blue: 0.10),
                Color(red: 0.92, green: 0.89, blue: 0.84), false
            )
        case .cottage:
            (
                Color(red: 0.45, green: 0.58, blue: 0.48), Color(red: 0.30, green: 0.42, blue: 0.34),
                Color(red: 0.96, green: 0.94, blue: 0.90), true
            )
        case .barn:
            (
                Color(red: 0.55, green: 0.44, blue: 0.34), Color(red: 0.33, green: 0.25, blue: 0.19),
                Color(red: 0.42, green: 0.33, blue: 0.26), false
            )
        case .castle:
            (
                Color(red: 0.34, green: 0.22, blue: 0.13), Color(red: 0.18, green: 0.11, blue: 0.06),
                Color(red: 0.55, green: 0.53, blue: 0.50), false
            )
        case .modern:
            (
                Color(red: 0.88, green: 0.83, blue: 0.74), Color(red: 0.74, green: 0.67, blue: 0.56),
                Color(red: 0.97, green: 0.97, blue: 0.96), false
            )
        }
    }

    /// The wood's sound, before hardware.
    var baseSound: SoundProfile {
        switch self {
        case .oak: .oak
        case .cottage: .pine
        case .barn: .barn
        case .castle: .castle
        case .modern: .modern
        }
    }
}

/// How a door leaf is put together.
enum DoorDesign: Sendable {
    /// Four raised panels, knob, peephole.
    case fourPanel
    /// Painted, a four-pane window on top, two panels below.
    case glazed
    /// Vertical boards with a Z brace and strap hinges.
    case planks
    /// Heavy boards with iron bands, studs and a ring pull.
    case studded
    /// A flat slab with a long bar handle.
    case slab
}

/// The metal of the hinges, handle and strike plate.
enum HardwareFinish: String, CaseIterable, Identifiable, Sendable {
    case iron
    case brass
    case chrome
    case copper
    case bronze

    static let storageKey = "hardware"

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .iron: "Iron"
        case .brass: "Brass"
        case .chrome: "Chrome"
        case .copper: "Copper"
        case .bronze: "Bronze"
        }
    }

    var color: Color {
        switch self {
        case .iron: Color(white: 0.22)
        case .brass: Color(red: 0.78, green: 0.62, blue: 0.30)
        case .chrome: Color(red: 0.72, green: 0.74, blue: 0.78)
        case .copper: Color(red: 0.72, green: 0.43, blue: 0.27)
        case .bronze: Color(red: 0.36, green: 0.27, blue: 0.19)
        }
    }

    /// How bright the highlights get: polished metals shine, iron barely does.
    var shine: Double {
        switch self {
        case .iron: 0.25
        case .brass: 0.5
        case .chrome: 0.75
        case .copper: 0.45
        case .bronze: 0.3
        }
    }

    var tone: MetalTone {
        switch self {
        case .iron: .iron
        case .brass: .brass
        case .chrome: .chrome
        case .copper: .copper
        case .bronze: .bronze
        }
    }
}

/// What you see through the open door.
enum InsideScene: String, CaseIterable, Identifiable, Sendable {
    case livingRoom
    case greatHall
    case beach
    case forest
    case space
    case brickWall

    static let storageKey = "insideScene"

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .livingRoom: "Living room"
        case .greatHall: "Great hall"
        case .beach: "Beach"
        case .forest: "Forest"
        case .space: "Outer space"
        case .brickWall: "Brick wall"
        }
    }
}

/// Everything the user picked, in one value the views and the synth can share.
struct DoorLook: Equatable, Sendable {
    var style: DoorStyle
    var hardware: HardwareFinish
    var scene: InsideScene

    var palette: DoorPalette {
        let surface = style.surface
        return DoorPalette(
            wood: surface.wood, woodShade: surface.shade, metal: hardware.color, metalShine: hardware.shine,
            frame: surface.frame, isPainted: surface.isPainted)
    }

    var soundProfile: SoundProfile {
        style.baseSound.with(metal: hardware.tone)
    }
}

struct DoorPalette: Sendable {
    var wood: Color
    var woodShade: Color
    var metal: Color
    /// 0...1: how strongly highlights show on the metal.
    var metalShine: Double
    var frame: Color
    /// Paint hides most of the grain.
    var isPainted: Bool
}
