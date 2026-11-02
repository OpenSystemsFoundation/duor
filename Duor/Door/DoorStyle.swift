import SwiftUI

/// The kind of door: how it's built, what it's made of, and how it sounds.
enum DoorStyle: String, CaseIterable, Identifiable, Sendable {
    case oak
    case cottage
    case barn
    case castle
    case spaceship
    case metal

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .oak: "Oak"
        case .cottage: "Cottage"
        case .barn: "Barn"
        case .castle: "Castle"
        case .spaceship: "Spaceship"
        case .metal: "Metal"
        }
    }

    /// How the leaf is built.
    var design: DoorDesign {
        switch self {
        case .oak: .fourPanel
        case .cottage: .glazed
        case .barn: .planks
        case .castle: .studded
        case .spaceship: .hatch
        case .metal: .steel
        }
    }

    /// The hardware it comes with. Picking a door resets the hardware to this.
    var defaultHardware: HardwareFinish {
        switch self {
        case .oak: .iron
        case .cottage: .brass
        case .barn: .iron
        case .castle: .bronze
        case .spaceship: .chrome
        case .metal: .iron
        }
    }

    /// What's behind it. Picking a door resets the scene to this.
    var defaultScene: InsideScene {
        switch self {
        case .oak: .livingRoom
        case .cottage: .beach
        case .barn: .forest
        case .castle: .greatHall
        case .spaceship: .space
        case .metal: .brickWall
        }
    }

    /// What the leaf is made of, and the color of the frame around it.
    var surface: DoorSurface {
        switch self {
        case .oak:
            DoorSurface(
                main: Color(red: 0.55, green: 0.33, blue: 0.18), shade: Color(red: 0.38, green: 0.21, blue: 0.10),
                frame: Color(red: 0.92, green: 0.89, blue: 0.84), finish: .wood)
        case .cottage:
            DoorSurface(
                main: Color(red: 0.45, green: 0.58, blue: 0.48), shade: Color(red: 0.30, green: 0.42, blue: 0.34),
                frame: Color(red: 0.96, green: 0.94, blue: 0.90), finish: .paint)
        case .barn:
            DoorSurface(
                main: Color(red: 0.55, green: 0.44, blue: 0.34), shade: Color(red: 0.33, green: 0.25, blue: 0.19),
                frame: Color(red: 0.42, green: 0.33, blue: 0.26), finish: .wood)
        case .castle:
            DoorSurface(
                main: Color(red: 0.34, green: 0.22, blue: 0.13), shade: Color(red: 0.18, green: 0.11, blue: 0.06),
                frame: Color(red: 0.55, green: 0.53, blue: 0.50), finish: .wood)
        case .spaceship:
            DoorSurface(
                main: Color(red: 0.86, green: 0.88, blue: 0.92), shade: Color(red: 0.58, green: 0.62, blue: 0.69),
                frame: Color(red: 0.28, green: 0.31, blue: 0.36), finish: .paint,
                accent: Color(red: 0.3, green: 0.9, blue: 1))
        case .metal:
            DoorSurface(
                main: Color(red: 0.56, green: 0.59, blue: 0.62), shade: Color(red: 0.33, green: 0.35, blue: 0.38),
                frame: Color(red: 0.42, green: 0.43, blue: 0.44), finish: .metal)
        }
    }

    /// The door's sound, before hardware.
    var baseSound: SoundProfile {
        switch self {
        case .oak: .oak
        case .cottage: .pine
        case .barn: .barn
        case .castle: .castle
        case .spaceship: .spaceship
        case .metal: .steel
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
    /// A spaceship hatch: hull panels, a porthole, light strips and a control pad.
    case hatch
    /// A riveted steel door with a vent and a lever handle.
    case steel
}

/// What a door's surface is.
enum SurfaceFinish: Sendable {
    /// Grain shows.
    case wood
    /// Paint hides most of the grain.
    case paint
    /// Brushed metal instead of grain.
    case metal
}

struct DoorSurface: Sendable {
    var main: Color
    var shade: Color
    var frame: Color
    var finish: SurfaceFinish
    /// Glowing trim (light strips), if the door has any.
    var accent: Color?
}

/// The metal of the hinges, handle and strike plate.
enum HardwareFinish: String, CaseIterable, Identifiable, Sendable {
    case iron
    case brass
    case chrome
    case copper
    case bronze

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
            wood: surface.main, woodShade: surface.shade, metal: hardware.color, metalShine: hardware.shine,
            frame: surface.frame, finish: surface.finish, accent: surface.accent)
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
    var finish: SurfaceFinish
    /// Glowing trim, if any.
    var accent: Color?

    /// How much wood grain shows.
    var grainStrength: Double {
        switch finish {
        case .wood: 1
        case .paint: 0.25
        case .metal: 0
        }
    }
}
