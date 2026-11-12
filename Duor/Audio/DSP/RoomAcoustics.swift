/// One early reflection: the sound again, `time` seconds later, off a nearby surface. `gain` is
/// against the sound sent into the room.
nonisolated struct Reflection: Sendable, Equatable {
    var time: Float
    var gain: Float

    init(_ time: Float, _ gain: Float) {
        self.time = time
        self.gain = gain
    }

    static let none = Reflection(0, 0)
}

/// The space a door stands in, as `RoomReverb` plays it.
nonisolated struct RoomAcoustics: Sendable, Equatable {
    /// How big the space is: scales the time sound takes to cross it. 1 is a room a few metres
    /// across, 0.5 a cupboard, 2.5 a hall.
    var size: Float
    /// Seconds for the low and middle of the tail to fall 60 dB.
    var decay: Float
    /// How much sooner the highs die than the lows: at 4 kHz the tail lasts `1 - damping` of
    /// `decay` (0 = bare steel, 0.3 = stone, 0.7 = carpet and curtains).
    var damping: Float
    /// How smeared the tail starts (0 = separate echoes, 0.7 = a wash straight away).
    var diffusion: Float = 0.5
    /// Seconds before the tail starts: the distance to the walls.
    var preDelay: Float = 0.004
    /// Up to four separate first reflections (unused ones `.none`).
    var early = EarlyPattern(repeating: .none)
    /// Loudness of the tail next to the early reflections. At 1 the tail of a short hit carries as
    /// much energy as the hit sent in, whatever the size and decay.
    var tail: Float = 1

    typealias EarlyPattern = InlineArray<4, Reflection>

    static func == (first: RoomAcoustics, second: RoomAcoustics) -> Bool {
        for index in first.early.indices where first.early[index] != second.early[index] { return false }
        return first.size == second.size && first.decay == second.decay && first.damping == second.damping
            && first.diffusion == second.diffusion && first.preDelay == second.preDelay && first.tail == second.tail
    }
}

// MARK: - Where each door stands

nonisolated extension RoomAcoustics {
    /// A carpeted hallway in a house: close walls, soft floor, gone in under half a second.
    static let hallway = RoomAcoustics(
        size: 0.75, decay: 0.4, damping: 0.6, diffusion: 0.55, preDelay: 0.003,
        early: [Reflection(0.007, 0.7), Reflection(0.012, 0.5), Reflection(0.019, 0.3), .none], tail: 0.6)

    /// A small furnished cottage room: low ceiling, rugs and curtains. Small and dry.
    static let cottage = RoomAcoustics(
        size: 0.5, decay: 0.25, damping: 0.7, diffusion: 0.6, preDelay: 0.002,
        early: [Reflection(0.005, 0.7), Reflection(0.009, 0.45), .none, .none], tail: 0.4)

    /// A big timber barn: wide, but hay, gaps and rough boards soak it up. Short and diffuse.
    static let barn = RoomAcoustics(
        size: 2, decay: 0.6, damping: 0.5, diffusion: 0.7, preDelay: 0.012,
        early: [Reflection(0.021, 0.5), Reflection(0.034, 0.4), Reflection(0.047, 0.25), .none], tail: 0.8)

    /// A stone hall: a long, bright tail, and the far wall answering late.
    static let stoneHall = RoomAcoustics(
        size: 2.7, decay: 1.8, damping: 0.33, diffusion: 0.5, preDelay: 0.018,
        early: [Reflection(0.026, 0.5), Reflection(0.043, 0.4), Reflection(0.071, 0.3), Reflection(0.118, 0.7)],
        tail: 1)

    /// A small metal airlock: hard walls a step away. Bright, tight, a little ringy.
    static let airlock = RoomAcoustics(
        size: 0.42, decay: 0.35, damping: 0.35, diffusion: 0.25, preDelay: 0.001,
        early: [Reflection(0.003, 0.8), Reflection(0.0055, 0.65), Reflection(0.008, 0.45), .none], tail: 0.9)

    /// A concrete stairwell: hard and tall, with over a second of echo.
    static let stairwell = RoomAcoustics(
        size: 1.7, decay: 1.2, damping: 0.45, diffusion: 0.4, preDelay: 0.008,
        early: [Reflection(0.011, 0.65), Reflection(0.019, 0.5), Reflection(0.032, 0.4), Reflection(0.052, 0.3)],
        tail: 1.1)

    /// A space that sends nothing back.
    static let open = RoomAcoustics(size: 1, decay: 0.1, damping: 0.5, tail: 0)
}

/// What is on the other side of the door, as a second space that opens up as the door does.
///
/// Shut, the door is heard in its own room only. As it swings open, sound gets through the
/// doorway: part of it comes back from the space beyond, and where there is nothing beyond to
/// send it back (a beach, a forest, open space) part of it is simply gone, so the door's own room
/// gets quieter.
nonisolated struct SceneAcoustics: Sendable, Equatable {
    /// The space beyond the doorway.
    var room: RoomAcoustics
    /// How much of the door's sound comes back from beyond when fully open, like
    /// `SoundProfile.room` for the door's own room (0 = nothing comes back).
    var level: Float
    /// Share of the door's own room that is lost through the doorway when fully open (0...1).
    var roomLoss: Float

    /// How far the doorway has opened acoustically, 0 (shut) ... 1, for a hinge angle in degrees.
    /// A gap lets most of the sound through long before the door stands square.
    static func openness(angle: Float) -> Float {
        let turn = min(max(angle / 90, 0), 1)
        return turn * (2 - turn)
    }

    /// Soft furniture, a rug, curtains: a short, warm answer.
    static let livingRoom = SceneAcoustics(
        room: RoomAcoustics(
            size: 0.9, decay: 0.3, damping: 0.75, diffusion: 0.65, preDelay: 0.006,
            early: [Reflection(0.009, 0.6), Reflection(0.015, 0.4), .none, .none], tail: 0.5),
        level: 0.1, roomLoss: 0.2)

    /// A great hall beyond the door: a long tail blooms as it opens.
    static let greatHall = SceneAcoustics(
        room: RoomAcoustics(
            size: 2.9, decay: 2.3, damping: 0.4, diffusion: 0.55, preDelay: 0.025,
            early: [Reflection(0.034, 0.4), Reflection(0.058, 0.35), Reflection(0.097, 0.4), .none], tail: 1),
        level: 0.3, roomLoss: 0.15)

    /// Outdoors: nothing to reflect off, and more than half the room escapes.
    static let beach = SceneAcoustics(room: .open, level: 0, roomLoss: 0.6)
    /// Trees scatter a little but send nothing back worth hearing.
    static let forest = SceneAcoustics(room: .open, level: 0, roomLoss: 0.5)
    /// Open space: whatever goes through the hatch never comes back.
    static let space = SceneAcoustics(room: .open, level: 0, roomLoss: 0.7)

    /// A brick wall right behind the door: a hard slap from an arm's length away, next to no tail.
    static let brickWall = SceneAcoustics(
        room: RoomAcoustics(
            size: 0.3, decay: 0.12, damping: 0.35, diffusion: 0.1, preDelay: 0.001,
            early: [Reflection(0.006, 1), Reflection(0.0125, 0.45), Reflection(0.019, 0.2), .none], tail: 0.2),
        level: 0.35, roomLoss: 0)
}
