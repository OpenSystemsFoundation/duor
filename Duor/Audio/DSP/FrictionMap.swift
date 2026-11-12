import Foundation

/// One tight spot on a hinge: where along the swing it grips, how wide, and how hard.
nonisolated struct FrictionSpot: Sendable, Equatable {
    /// Hinge angle in degrees.
    var angle: Float
    /// Half width in degrees (the spot fades out over about twice this).
    var width: Float
    /// Extra grip at the centre of the spot, on top of the map's floor (0...1).
    var strength: Float
}

/// How a door's hinge grips along its swing: a low floor with a few tight spots.
///
/// A real door creaks in patches, at the same few angles every time, and a little differently
/// opening and closing. The creak follows this map, so it comes and goes at fixed places instead of
/// sounding for the whole swing. Generated from a seed, so each door and hardware combination has
/// its own, and the same one every launch.
nonisolated struct FrictionMap: Sendable, Equatable {
    var spots: InlineArray<4, FrictionSpot>
    var count: Int
    /// Grip everywhere else (0...1).
    var floor: Float
    /// Closing passes the spots shifted by this many degrees, and a little weaker.
    var closingShift: Float = 4
    var closingStrength: Float = 0.8

    /// How the spots of a door are drawn: how many, how wide and how strong.
    struct Recipe: Sendable, Equatable {
        var count: Int
        var width: ClosedRange<Float>
        var strength: ClosedRange<Float>
        var floor: Float
        /// Where along the swing spots may sit (degrees).
        var span: ClosedRange<Float> = 12...150
    }

    /// A map with no spots: the same grip everywhere.
    static func uniform(_ floor: Float) -> FrictionMap {
        FrictionMap(
            spots: InlineArray(repeating: FrictionSpot(angle: 0, width: 1, strength: 0)), count: 0, floor: floor)
    }

    /// Draws `recipe.count` spots (at most four) spread over the span, so they never pile up in one place.
    init(recipe: Recipe, seed: UInt32) {
        var random = NoiseSource(seed: seed)
        let count = min(max(recipe.count, 0), 4)
        var spots = InlineArray<4, FrictionSpot>(repeating: FrictionSpot(angle: 0, width: 1, strength: 0))
        let span = recipe.span.upperBound - recipe.span.lowerBound
        for index in 0..<count {
            // One spot per equal slice of the span, somewhere in the middle of its slice.
            let slice = span / Float(count)
            let position = recipe.span.lowerBound + slice * (Float(index) + random.value(in: 0.2...0.8))
            spots[index] = FrictionSpot(
                angle: position, width: random.value(in: recipe.width), strength: random.value(in: recipe.strength))
        }
        self.init(spots: spots, count: count, floor: recipe.floor)
    }

    init(spots: InlineArray<4, FrictionSpot>, count: Int, floor: Float) {
        self.spots = spots
        self.count = min(max(count, 0), 4)
        self.floor = floor
    }

    static func == (first: FrictionMap, second: FrictionMap) -> Bool {
        guard first.count == second.count, first.floor == second.floor, first.closingShift == second.closingShift,
            first.closingStrength == second.closingStrength
        else { return false }
        for index in 0..<first.count where first.spots[index] != second.spots[index] { return false }
        return true
    }

    /// Grip at `angle` (0...1). Real-time safe.
    func grip(at angle: Float, closing: Bool) -> Float {
        var grip = floor
        let shift = closing ? closingShift : 0
        let scale = closing ? closingStrength : 1
        for index in 0..<count {
            let spot = spots[index]
            let distance = (angle - spot.angle - shift) / max(spot.width, 0.5)
            // A smooth bump, zero beyond twice the width: cheap and with no long tails.
            let x = min(abs(distance) * 0.5, 1)
            let bump = (1 - x * x) * (1 - x * x)
            grip = max(grip, floor + spot.strength * scale * bump)
        }
        return min(grip, 1)
    }

    /// The same map with every spot moved by up to `degrees`, for the same door with other hardware.
    func shuffled(seed: UInt32, by degrees: Float) -> FrictionMap {
        var copy = self
        var random = NoiseSource(seed: seed)
        for index in 0..<count {
            copy.spots[index].angle += random.bipolar() * degrees
        }
        return copy
    }
}
