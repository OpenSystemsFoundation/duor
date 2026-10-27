import Foundation

/// What a cat is doing in one frame of cat lovers mode.
enum CatPose: Equatable, Sendable {
    case walk
    case stand
    /// Low to the ground, creeping slowly.
    case stalk
    /// Crouched and still: just landed a pounce.
    case crouch
    /// Crouched, rear end wiggling: about to pounce.
    case wiggle
    case sprint
    /// Mid-air, front paws reaching out.
    case leap
    /// Weightless, paws paddling.
    case float
    /// Lying on its back in the sun, paws in the air.
    case sunbathe
}

/// Where a cat is in one frame.
struct CatFrame: Equatable, Sendable {
    /// How far across the scene, as a fraction of its width, measured from the side the visit
    /// starts on: 0 at that edge, 1 at the other. Outside 0...1 is off screen.
    var across: Double
    var pose: CatPose
    /// Looking back over its shoulder, the way it came.
    var looksBack = false
    /// Height off the ground, as a fraction of the cat's size.
    var lift: Double = 0
}

/// The little stories of cat lovers mode, as pure functions of seconds since a visit started.
/// The drawing in `SceneLife` follows these, so the timing can be tested on its own.
enum CatStory {
    // MARK: Beach

    /// How far across the sand the sunbather walks before lying down: somewhere near the middle.
    static func sunbathingSpot(lane: Double) -> Double { 0.3 + 0.3 * lane }

    /// Long enough for the slowest sunbather (the spot furthest from either edge).
    static let sunbatherDuration = 19.0

    /// The beach cat strolls in, rolls onto its back for a long sunbathe, then gets up and
    /// strolls off the other side.
    static func sunbather(at t: Double, spot: Double) -> CatFrame? {
        let speed = 0.2
        let margin = 0.25
        let lounge = 10.0
        let walkIn = (spot + margin) / speed
        let walkOut = (1 + margin - spot) / speed
        guard t >= 0 else { return nil }
        if t < walkIn { return CatFrame(across: -margin + t * speed, pose: .walk) }
        if t < walkIn + lounge { return CatFrame(across: spot, pose: .sunbathe) }
        let out = t - walkIn - lounge
        guard out < walkOut else { return nil }
        return CatFrame(across: spot + out * speed, pose: .walk)
    }

    // MARK: Forest

    /// The rabbit and the cat after it, in one frame of the chase.
    struct Chase: Equatable, Sendable {
        /// Where the rabbit is (same measure as `CatFrame.across`), if it's in the scene.
        var rabbit: Double?
        /// How fast the rabbit hops: 0 sitting still, 1 hopping along, more when fleeing.
        var rabbitHop: Double
        var cat: CatFrame?
    }

    static let chaseDuration = 8.0
    /// When the cat stops creeping and starts wiggling, ready to pounce.
    static let chaseWiggle = 5.3
    /// When the cat goes for it, and the rabbit bolts.
    static let chasePounce = 6.0

    /// The rabbit hops in and stops to nibble the grass. The cat creeps in behind it, very
    /// slowly, low to the ground, wiggles, and goes for it. The rabbit bolts and the cat chases
    /// it out of the scene, never quite catching it.
    static func chase(at t: Double) -> Chase {
        let rabbitMargin = 0.15
        let catMargin = 0.25
        let nibbleSpot = 0.55
        let hopIn = 1.5
        let rabbitBolt = 0.8
        let catCreep = 0.12
        let catSprint = 0.9
        let catEnters = 2.0

        var chase = Chase(rabbit: nil, rabbitHop: 0, cat: nil)
        if t >= 0, t < hopIn {
            chase.rabbit = -rabbitMargin + (nibbleSpot + rabbitMargin) * t / hopIn
            chase.rabbitHop = 1
        } else if t >= hopIn, t < chasePounce {
            chase.rabbit = nibbleSpot
        } else if t >= chasePounce {
            let fled = nibbleSpot + (t - chasePounce) * rabbitBolt
            if fled < 1 + rabbitMargin {
                chase.rabbit = fled
                chase.rabbitHop = 1.8
            }
        }

        let crouchSpot = -catMargin + (chaseWiggle - catEnters) * catCreep
        if t >= catEnters, t < chaseWiggle {
            chase.cat = CatFrame(across: -catMargin + (t - catEnters) * catCreep, pose: .stalk)
        } else if t >= chaseWiggle, t < chasePounce {
            chase.cat = CatFrame(across: crouchSpot, pose: .wiggle)
        } else if t >= chasePounce {
            let ran = crouchSpot + (t - chasePounce) * catSprint
            if ran < 1 + catMargin { chase.cat = CatFrame(across: ran, pose: .sprint) }
        }
        return chase
    }

    // MARK: Brick wall

    static let pounceDuration = 11.0
    /// The cat's two leaps: when it leaves the ground, and when it lands.
    static let firstPounce = 4.3...4.9
    static let secondPounce = 6.6...7.2

    /// Where the mouse stops to sniff, and where it dodges to (fractions of the width).
    private static let sniffSpot = 0.42
    private static let dodgeSpot = 0.72

    /// A cartoon chase. The cat sneaks up on the mouse, wiggles, and pounces. The mouse jumps
    /// out of its skin, scoots ahead and turns round to hop up and down at the cat. The cat lands on nothing, collects itself and pounces again, and the
    /// mouse runs straight back underneath it and away. The cat looks back, then walks off
    /// with as much dignity as it has left.
    static func pounce(at t: Double) -> CatFrame? {
        let margin = 0.3
        let creep = 0.17
        let walk = 1.0 / 3
        let start = 1.0
        let crouchSpot = 0.12
        let arrives = start + (crouchSpot + margin) / creep
        func leap(_ jump: ClosedRange<Double>, from: Double, to: Double, height: Double) -> CatFrame {
            let u = (t - jump.lowerBound) / (jump.upperBound - jump.lowerBound)
            return CatFrame(across: from + (to - from) * u, pose: .leap, lift: sin(u * .pi) * height)
        }
        switch t {
        case ..<start:
            return nil
        case ..<arrives:
            return CatFrame(across: -margin + (t - start) * creep, pose: .stalk)
        case ..<firstPounce.lowerBound:
            return CatFrame(across: crouchSpot, pose: .wiggle)
        case ..<firstPounce.upperBound:
            return leap(firstPounce, from: crouchSpot, to: sniffSpot, height: 0.8)
        case ..<5.6:
            return CatFrame(across: sniffSpot, pose: .crouch)
        case ..<6.0:
            return CatFrame(across: sniffSpot, pose: .stand)
        case ..<secondPounce.lowerBound:
            return CatFrame(across: sniffSpot, pose: .wiggle)
        case ..<secondPounce.upperBound:
            return leap(secondPounce, from: sniffSpot, to: dodgeSpot, height: 1.1)
        case ..<7.7:
            return CatFrame(across: dodgeSpot, pose: .crouch)
        case ..<9.0:
            return CatFrame(across: dodgeSpot, pose: .stand, looksBack: true)
        default:
            let across = dodgeSpot + (t - 9.0) * walk
            return across < 1 + margin ? CatFrame(across: across, pose: .walk) : nil
        }
    }

    /// Where the mouse is (same measure as `CatFrame.across`). It runs in ahead of the cat,
    /// stops to sniff, dodges the first pounce, taunts the cat, and runs off under the second.
    static func mouse(at t: Double) -> MouseFrame? {
        let runIn = 0.4
        let dash = (dodgeSpot - sniffSpot) / 0.35
        let flee = 0.55
        let hop = 0.25
        switch t {
        case ..<0:
            return nil
        case ..<((sniffSpot + 0.1) / runIn):
            return MouseFrame(across: -0.1 + t * runIn, running: true)
        case ..<firstPounce.lowerBound:
            return MouseFrame(across: sniffSpot)
        case ..<(firstPounce.lowerBound + hop):
            // Jumps out of its skin.
            let u = (t - firstPounce.lowerBound) / hop
            return MouseFrame(across: sniffSpot, lift: sin(u * .pi) * 0.9)
        case ..<(firstPounce.lowerBound + hop + 0.35):
            return MouseFrame(across: sniffSpot + (t - firstPounce.lowerBound - hop) * dash, running: true)
        case ..<5.1:
            return MouseFrame(across: dodgeSpot)
        case ..<6.3:
            // Turns round and hops up and down at the cat.
            return MouseFrame(across: dodgeSpot, facesBack: true, lift: abs(sin((t - 5.1) * 8)) * 0.35)
        case ..<secondPounce.lowerBound:
            return MouseFrame(across: dodgeSpot, facesBack: true)
        default:
            let across = dodgeSpot - (t - secondPounce.lowerBound) * flee
            return across > -0.15 ? MouseFrame(across: across, running: true, facesBack: true) : nil
        }
    }
}

/// Where the mouse at the brick wall is in one frame.
struct MouseFrame: Equatable, Sendable {
    /// Same measure as `CatFrame.across`.
    var across: Double
    var running = false
    /// Facing back the way it came (towards the cat, until the cat is behind it).
    var facesBack = false
    /// Height off the ground, as a fraction of the mouse's size.
    var lift: Double = 0
}
