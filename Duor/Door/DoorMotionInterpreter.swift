import Foundation

/// Something the door did that should be heard or felt.
enum DoorEvent: Equatable, Sendable {
    /// The door left the closed position (latch releases).
    case unlatched
    /// The door is swinging. Positive velocity opens, negative closes (degrees per second).
    case swing(velocity: Double)
    /// The door reached the closed position.
    case closed(CloseKind)
    /// The door hit its fully open stop.
    case hitOpenStop(speed: Double)
}

/// How hard the door was closed.
enum CloseKind: Equatable, Sendable {
    case gentle
    case firm
    case slam
}

/// Turns raw hinge samples into door events.
///
/// The system decides how often hinge samples arrive, so this never assumes a fixed rate.
/// Real hinge readings jitter by a fraction of a degree, and the status can flicker at the
/// closed and fully-open points. So:
/// - Movement only counts once the angle has moved `jitterTolerance` from the last accepted
///   position (slow, real motion still gets through, just a few samples later).
/// - Latch, unlatch and the open stop are latched states with hysteresis: each fires once per
///   real open or close, never on a flicker.
struct DoorMotionInterpreter {
    struct Configuration: Sendable {
        /// Below this speed (degrees per second) the door makes no creak.
        var creakThreshold: Double = 6
        /// At or above this closing speed the door is a firm close.
        var firmCloseSpeed: Double = 90
        /// At or above this closing speed the door slams.
        var slamSpeed: Double = 260
        /// Angle changes smaller than this (degrees) are sensor jitter, not movement.
        var jitterTolerance: Double = 1.5
        /// Degrees the door must open past the latched angle before it counts as unlatched.
        var unlatchTravel: Double = 3
        /// Degrees the door must swing back from the open stop before it can hit it again.
        var stopRearmTravel: Double = 8
        /// Shortest and longest time between accepted positions used for velocity.
        /// The cap keeps a jump after a long pause from looking infinitely fast.
        var sampleGap: ClosedRange<TimeInterval> = (1.0 / 240)...0.5
        /// Without accepted movement for this long, the door is considered still.
        var stillAfter: TimeInterval = 0.3
        /// Smoothing for velocity (0...1, higher reacts faster).
        var smoothing: Double = 0.5
    }

    var configuration = Configuration()
    /// Smoothed angular velocity in degrees per second.
    private(set) var velocity: Double = 0
    /// The last position that counted as movement.
    private var anchor: HingeReading?
    private var isLatched = false
    private var latchedAngle: Double = 0
    private var isStopArmed = true
    private var stopAngle: Double = 180

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func ingest(_ reading: HingeReading) -> [DoorEvent] {
        guard let anchor else {
            // The first sample is the starting state, not a movement.
            self.anchor = reading
            isLatched = reading.status == .closed
            latchedAngle = reading.degrees
            isStopArmed = reading.status != .fullyOpen
            stopAngle = reading.degrees
            return []
        }

        // Motion, measured from the last accepted position.
        var instant: Double = 0
        let moved = reading.degrees - anchor.degrees
        if abs(moved) >= configuration.jitterTolerance {
            let gap = min(
                max(reading.timestamp - anchor.timestamp, configuration.sampleGap.lowerBound),
                configuration.sampleGap.upperBound)
            instant = moved / gap
            velocity += (instant - velocity) * configuration.smoothing
            self.anchor = reading
        } else if reading.timestamp - anchor.timestamp > configuration.stillAfter {
            velocity = 0
        }
        // Use the faster of instant and smoothed speed so a single big jump still counts.
        let impactSpeed = max(abs(instant), abs(velocity))

        var events: [DoorEvent] = []
        if isLatched, reading.status != .closed, reading.degrees - latchedAngle >= configuration.unlatchTravel {
            isLatched = false
            events.append(.unlatched)
        }
        if !isLatched, reading.status != .closed, instant != 0, abs(velocity) >= configuration.creakThreshold {
            events.append(.swing(velocity: velocity))
        }
        if !isStopArmed, reading.degrees <= stopAngle - configuration.stopRearmTravel {
            isStopArmed = true
        }
        if isStopArmed, reading.status == .fullyOpen {
            isStopArmed = false
            stopAngle = reading.degrees
            events.append(.hitOpenStop(speed: impactSpeed))
        }
        if reading.status == .closed {
            if !isLatched {
                isLatched = true
                events.append(.closed(classifyClose(speed: impactSpeed)))
                velocity = 0
            }
            latchedAngle = reading.degrees
        }
        return events
    }

    func classifyClose(speed: Double) -> CloseKind {
        if speed >= configuration.slamSpeed { return .slam }
        if speed >= configuration.firmCloseSpeed { return .firm }
        return .gentle
    }
}
