import Foundation

/// The screen the door is drawn on, as far as swiping is concerned.
enum DoorScreen: Equatable, Sendable {
    /// The iPhone Duo's inner display. One half of the phone is the door leaf, so a swipe can
    /// close the door further than the phone is folded, but can't open it past the phone half.
    case inner
    /// One flat screen: the cover display, or a phone without a hinge. The whole swing is drawn,
    /// so a swipe can take the door anywhere from shut to flat open.
    case single
}

/// Whether the door can be swiped (Settings, "Swipe mode").
///
/// On a device with a hinge (the iPhone Duo, or any other foldable) the hinge opens the door, so
/// swiping is off until the user turns it on. Without a hinge, swiping is the only way in, so it is
/// always on. A choice the user has saved always wins on a hinge device.
enum SwipeMode {
    static let storageKey = "swipeMode"

    /// What the setting shows before the user has touched it.
    static func isOnByDefault(hasHinge: Bool) -> Bool { !hasHinge }

    /// Whether swiping moves the door. `saved` is nil until the user changes the setting.
    static func isOn(saved: Bool?, hasHinge: Bool) -> Bool {
        guard hasHinge else { return true }
        return saved ?? isOnByDefault(hasHinge: hasHinge)
    }
}

/// Where the door is, when it can be moved by the hinge or by a swipe.
///
/// The hinge moves the door until the user swipes. From then on the swipe does, until the two
/// agree again (see `settle()`) or the door moves to another screen.
struct DoorDrive: Equatable, Sendable {
    /// How close (degrees) the swipe and the hinge must be to agree.
    static let tolerance = 1.5

    var screen: DoorScreen = .single
    /// The physical hinge angle; 0 on phones without a hinge.
    var hinge: Double = 0
    /// The swiped angle, while a swipe is in charge.
    private(set) var swiped: Double?

    var isSwiped: Bool { swiped != nil }

    /// The door angle: 0 shut, 180 flat open.
    var degrees: Double {
        guard let swiped else { return hinge }
        return screen == .inner ? min(swiped, hinge) : swiped
    }

    /// How far a swipe can move the door.
    var range: ClosedRange<Double> {
        screen == .inner ? 0...min(max(hinge, 0), 180) : 0...180
    }

    mutating func swipe(to degrees: Double) {
        swiped = min(max(degrees, range.lowerBound), range.upperBound)
    }

    /// Hands the door back to the hinge if they agree: on the inner display once the door is as
    /// open as the phone (swiped open, or the phone folded down to meet it); on a single screen
    /// once the door is back where the hinge has it (shut, on a folded phone). Call this whenever
    /// the user isn't swiping.
    mutating func settle() {
        guard let swiped else { return }
        let agrees =
            switch screen {
            case .inner: swiped >= hinge - Self.tolerance
            case .single: swiped <= hinge + Self.tolerance
            }
        if agrees { self.swiped = nil }
    }

    /// The door moved to another screen: the hinge is in charge again.
    /// - Returns: Whether the door angle jumped (so the jump shouldn't sound like a swing).
    mutating func move(to screen: DoorScreen) -> Bool {
        let before = degrees
        self.screen = screen
        swiped = nil
        return abs(degrees - before) > Self.tolerance
    }

    /// Hands the door back to the hinge, wherever the swipe left it (swiping was turned off).
    /// - Returns: Whether the door angle jumped.
    mutating func release() -> Bool {
        move(to: screen)
    }
}

/// How a horizontal swipe turns the door: swiping left opens it, swiping right closes it, the
/// way the door's free edge moves in both views. A swipe across `fullSwing` of the screen width
/// is a full swing.
enum DoorSwipe {
    static let fullSwing = 0.85

    static func degrees(from start: Double, translation: Double, width: Double) -> Double {
        start + degreesPerPoint(width: width) * -translation
    }

    /// Swipe speed (points per second) as door speed (degrees per second).
    static func velocity(_ pointsPerSecond: Double, width: Double) -> Double {
        degreesPerPoint(width: width) * -pointsPerSecond
    }

    private static func degreesPerPoint(width: Double) -> Double {
        180 / (max(width, 1) * fullSwing)
    }
}

/// The door after the user lets go: it keeps the swipe's speed, slowed by friction, until it
/// stops, hits the open stop, or bangs shut. A slow door that's nearly shut swings itself shut.
struct DoorFling: Equatable, Sendable {
    /// Speed lost per second, as a rate (speed × e^(−friction·t)).
    static let friction = 2.6
    /// Below this speed (degrees per second) the door has stopped.
    static let restSpeed = 6.0
    /// Within this many degrees of shut, a slow door swings itself shut...
    static let latchPull = 10.0
    /// ...at this speed (degrees per second): a gentle close.
    static let latchSpeed = 50.0

    private(set) var degrees: Double
    private(set) var velocity: Double
    let range: ClosedRange<Double>
    private(set) var isDone = false

    init(degrees: Double, velocity: Double, range: ClosedRange<Double>) {
        self.range = range
        self.degrees = min(max(degrees, range.lowerBound), range.upperBound)
        self.velocity = velocity
    }

    mutating func step(_ dt: Double) {
        guard !isDone, dt > 0 else { return }
        let nearlyShut = degrees < range.lowerBound + Self.latchPull
        if nearlyShut, velocity > -Self.latchSpeed, velocity < Self.latchSpeed {
            velocity = -Self.latchSpeed
        } else {
            velocity *= exp(-Self.friction * dt)
        }
        degrees += velocity * dt
        if degrees <= range.lowerBound {
            stop(at: range.lowerBound)
        } else if degrees >= range.upperBound {
            stop(at: range.upperBound)
        } else if abs(velocity) < Self.restSpeed {
            stop(at: degrees)
        }
    }

    private mutating func stop(at degrees: Double) {
        self.degrees = degrees
        velocity = 0
        isDone = true
    }
}
