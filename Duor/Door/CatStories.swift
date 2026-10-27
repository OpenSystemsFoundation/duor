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

    /// Where the mouse hides: right behind the spot the cat leaps from (fraction of the width).
    static let mouseSpot = 0.2

    static let pounceDuration = 9.0
    /// When the cat leaves the ground, and when it lands.
    static let pounceTakeoff = 4.1
    static let pounceLanding = 4.9
    /// When the mouse makes a run for it, once the cat has landed.
    static let mouseBolts = 5.2

    /// The cat walks along the wall, has a good look around, wiggles, and pounces on something
    /// across the way. The mouse was right behind it all along: the leap uncovers it, it freezes,
    /// and once the cat lands it runs off the way the cat came. The cat looks back, then walks
    /// off with as much dignity as it has left.
    static func pounce(at t: Double) -> CatFrame? {
        let margin = 0.3
        let speed = 1.0 / 3
        let takeoffSpot = 0.28
        let landingSpot = 0.68
        guard t >= 0 else { return nil }
        let walkIn = (takeoffSpot + margin) / speed
        switch t {
        case ..<walkIn:
            return CatFrame(across: -margin + t * speed, pose: .walk)
        case ..<2.2:
            return CatFrame(across: takeoffSpot, pose: .stand)
        case ..<2.9:
            return CatFrame(across: takeoffSpot, pose: .stand, looksBack: true)
        case ..<3.3:
            return CatFrame(across: takeoffSpot, pose: .stand)
        case ..<pounceTakeoff:
            return CatFrame(across: takeoffSpot, pose: .wiggle)
        case ..<pounceLanding:
            let u = (t - pounceTakeoff) / (pounceLanding - pounceTakeoff)
            return CatFrame(
                across: takeoffSpot + (landingSpot - takeoffSpot) * u, pose: .leap, lift: sin(u * .pi) * 1.1)
        case ..<5.4:
            return CatFrame(across: landingSpot, pose: .crouch)
        case ..<6.8:
            return CatFrame(across: landingSpot, pose: .stand, looksBack: true)
        default:
            let across = landingSpot + (t - 6.8) * speed
            return across < 1 + margin ? CatFrame(across: across, pose: .walk) : nil
        }
    }

    /// Where the mouse is (same measure as `CatFrame.across`). It only shows once the cat leaps
    /// off it (before that the cat hides it), sits frozen while the cat is in the air, then runs
    /// away off the edge the cat came from.
    static func mouse(at t: Double) -> Double? {
        guard t >= pounceTakeoff else { return nil }
        let across = mouseSpot - max(t - mouseBolts, 0) * 0.15
        return across > -0.15 ? across : nil
    }
}
