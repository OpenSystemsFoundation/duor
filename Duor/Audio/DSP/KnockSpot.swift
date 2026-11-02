import Foundation

/// Where a knuckle lands on the door, as fractions of the leaf: `x` runs from the hinge edge (0)
/// to the latch edge (1), `y` from the top (0) to the bottom (1).
///
/// A door leaf vibrates like a plate held at its edges. A knock in the middle sets the whole leaf
/// moving: a deeper, rounder "thoom". Near an edge the leaf is stiff, so the same knock is higher,
/// shorter and snappier, and more of it goes into the frame. Each mode is excited in proportion to
/// how much it moves where it's hit, so knocks on different spots also differ in timbre.
nonisolated struct KnockSpot: Sendable, Equatable {
    var x: Float
    var y: Float

    init(x: Float, y: Float) {
        self.x = Self.clamp(x)
        self.y = Self.clamp(y)
    }

    static let center = KnockSpot(x: 0.5, y: 0.5)

    /// 1 in the middle of the leaf, falling to 0 at its edges, where the frame holds it stiff.
    var centerness: Float {
        let across = min(x, 1 - x) * 2
        let down = min(y, 1 - y) * 2
        return (across * down).squareRoot()
    }

    /// The same spot, a little off: nobody hits exactly the same place twice.
    func nudged(by random: inout NoiseSource, spread: Float = 0.03) -> KnockSpot {
        KnockSpot(x: x + spread * random.bipolar(), y: y + spread * random.bipolar())
    }

    /// The knock's modes, weighted for this spot. A profile's knock is tuned as heard in the
    /// middle of the door, so a knock there keeps its tuning, just a little deeper.
    ///
    /// The middle favors the low modes (the whole leaf moving), the edges the high ones (a small,
    /// stiff patch). On top of that each mode is colored by how much its plate mode moves here
    /// compared with the middle, for a door about twice as tall as it is wide, so spots equally far
    /// from the edge still differ. The coloring is gentle: a knuckle covers an area, not a point,
    /// and real doors have rails, panels and grain that blur the nodes.
    func excite(_ modes: ModeSet) -> ModeSet {
        let middle = centerness
        var shaped = modes
        var before: Float = 0
        var after: Float = 0
        for index in shaped.indices {
            let height = Float(index) / Float(max(modes.count - 1, 1))
            let tilt = 1 + 0.2 * middle * (1 - height) + 1.1 * (1 - middle) * height
            let color = powf(Self.motion(index, x: x, y: y) / Self.motion(index, x: 0.5, y: 0.5), 0.6)
            before += modes[index].gain * modes[index].gain
            shaped[index].gain *= tilt * color
            after += shaped[index].gain * shaped[index].gain
        }
        // Keep the energy, so position changes a knock's color more than its loudness.
        let makeUp = after > 0 ? (before / after).squareRoot() : 1
        let loudness = 0.9 + 0.1 * middle
        for index in shaped.indices {
            shaped[index].gain *= makeUp * loudness
        }
        return shaped
    }

    /// Stiffer near the edges: up to 8% higher; the middle a touch lower.
    var pitchScale: Float { 1.08 - 0.1 * centerness }
    /// The middle of the leaf rings longer than the stiff edges.
    var decayScale: Float { 0.7 + 0.45 * centerness }
    /// A stiffer surface pushes back harder, so the knuckle's contact is shorter (brighter).
    var contactScale: Float { 0.7 + 0.35 * centerness }
    /// More knuckle snap on the stiff edges, less on the giving middle.
    var snapScale: Float { 1.5 - 0.7 * centerness }
    /// Near an edge the knock goes straight into the frame: a little more thud.
    var thumpScale: Float { 1.15 - 0.15 * centerness }

    /// How much a knock here rattles the latch bolt in its strike plate: only near the latch edge,
    /// most at handle height.
    var latchRattle: Float {
        let nearEdge = Self.smoothstep(0.7, 0.97, x)
        let nearHandle = max(0, 1 - abs(y - 0.5) * 2.2)
        return nearEdge * nearHandle
    }

    private static let nodeFloor: Float = 0.5

    /// How much a plate mode moves at a spot, never quite zero.
    private static func motion(_ index: Int, x: Float, y: Float) -> Float {
        let shape = plateMode(index)
        let motion = abs(sinf(Float.pi * shape.x * x) * sinf(Float.pi * shape.y * y))
        return nodeFloor + (1 - nodeFloor) * motion
    }

    /// Half-waves across (x) and down (y) for each knock mode, lowest first.
    private static func plateMode(_ index: Int) -> SIMD2<Float> {
        switch index {
        case 0: SIMD2(1, 1)
        case 1: SIMD2(1, 2)
        case 2: SIMD2(1, 3)
        case 3: SIMD2(2, 1)
        case 4: SIMD2(1, 4)
        default: SIMD2(2, 2)
        }
    }

    private static func clamp(_ value: Float) -> Float {
        value.isFinite ? min(max(value, 0), 1) : 0.5
    }

    private static func smoothstep(_ low: Float, _ high: Float, _ value: Float) -> Float {
        let t = min(max((value - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
