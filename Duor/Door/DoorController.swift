import Foundation
import Observation
import os

/// Something the user should feel (haptics) or see (a shake), with an id so repeats still trigger.
struct DoorFeedback: Equatable {
    enum Kind: Equatable {
        case knock
        case unlatch
        case openStop
        case closed(CloseKind)
    }

    var kind: Kind
    var id: Int
}

/// Time as `DoorController` sees it: the system clock in the app, a hand-wound one in tests.
protocol DoorClock: AnyObject {
    /// Monotonic seconds, on the same scale as hinge reading timestamps (system uptime).
    var now: TimeInterval { get }
    func sleep(for duration: Duration) async throws
}

final class SystemDoorClock: DoorClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Owns door state. The door is moved by the hinge or by swiping (see `DoorDrive`); its angle is
/// fed to the interpreter, whose events become sound and feedback.
@Observable
final class DoorController {
    /// Latest sample from the real hinge.
    private(set) var hinge: HingeReading?
    /// True once the system has delivered a real hinge sample.
    private(set) var hasHardwareHinge = false
    /// The latest thing to feel or see. Views use it as a trigger for haptics and animations.
    private(set) var feedback: DoorFeedback?

    /// Shut and latched. Decided by the door angle, not the system's hinge status.
    private(set) var isClosed = true
    /// The door angle: the hinge angle, unless a swipe has moved the door.
    var angle: Double { drive.degrees }
    /// Whether a swipe, not the hinge, has the door.
    var isSwiped: Bool { drive.isSwiped }

    private var drive = DoorDrive()
    @ObservationIgnored private var interpreter = DoorMotionInterpreter()
    @ObservationIgnored private let sounds: any DoorSoundPlaying
    @ObservationIgnored private let clock: any DoorClock
    @ObservationIgnored private var creakFadeTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var flingTask: Task<Void, Never>?
    /// The door angle when the current swipe began, while the user is swiping.
    @ObservationIgnored private var swipeStart: Double?
    @ObservationIgnored private var feedbackCount = 0

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Duor", category: "hinge")

    /// How often a flung door moves.
    static let flingStep = Duration.milliseconds(16)
    /// How long the hinge must be still before a nearly shut door latches by itself.
    static let settleDelay = Duration.milliseconds(350)
    /// How long the creak keeps going after the last movement.
    static let creakFadeDelay = Duration.milliseconds(150)
    /// How fast the door swings open when asked to (accessibility): about halfway open.
    static let swingOpenSpeed = 240.0

    init(sounds: any DoorSoundPlaying = DoorAudioEngine(), clock: any DoorClock = SystemDoorClock()) {
        self.sounds = sounds
        self.clock = clock
    }

    func apply(sound profile: SoundProfile) {
        sounds.apply(profile: profile)
    }

    /// Input from `onHingeChange`. A nil reading means this device has no hinge.
    func hardwareHingeChanged(_ reading: HingeReading?) {
        guard let reading else { return }
        hasHardwareHinge = true
        hinge = reading
        drive.hinge = reading.degrees
        if !isSwiping { drive.settle() }
        ingest(drive.followsHinge ? reading : .simulated(degrees: drive.degrees, at: reading.timestamp))
    }

    /// Which screen the door is on. On a phone without a hinge, always the single screen.
    func screenChanged(to screen: DoorScreen) {
        guard screen != drive.screen else { return }
        stopFling()
        swipeStart = nil
        if drive.move(to: screen) { restartAfterJump() }
    }

    /// Swiping was turned off: the hinge has the door again, wherever the swipe left it.
    func stopSwiping() {
        stopFling()
        swipeStart = nil
        if drive.release() { restartAfterJump() }
    }

    /// The door jumped to the hinge angle without swinging: no creak or slam for that.
    private func restartAfterJump() {
        sounds.setCreak(velocity: 0)
        interpreter.restart()
        if let hinge, drive.followsHinge {
            ingest(hinge)
        } else {
            ingest(.simulated(degrees: drive.degrees, at: now))
        }
    }

    // MARK: Swiping

    /// The user is swiping: `translation` is how far, along the door's width (points).
    func swipeChanged(translation: Double, width: Double) {
        if swipeStart == nil {
            stopFling()
            startInterpreterIfNeeded()
            swipeStart = drive.degrees
        }
        drive.swipe(to: DoorSwipe.degrees(from: swipeStart ?? 0, translation: translation, width: width))
        ingest(.simulated(degrees: drive.degrees, at: now))
    }

    /// The user let go: the door swings on with the swipe's speed (points per second).
    func swipeEnded(velocity: Double, width: Double) {
        guard swipeStart != nil else { return }
        swipeStart = nil
        fling(velocity: DoorSwipe.velocity(velocity, width: width))
    }

    /// Swings the door open or shut on its own (accessibility actions).
    func swing(open: Bool) {
        guard swipeStart == nil else { return }
        stopFling()
        startInterpreterIfNeeded()
        fling(velocity: open ? Self.swingOpenSpeed : -DoorFling.speed(toTravel: drive.degrees))
    }

    /// A knock on `spot` of the door's outside face. Where it lands changes how it sounds.
    func knock(at spot: KnockSpot = .center) {
        guard isClosed else { return }
        sounds.knock(at: spot, volume: Float.random(in: 0.85...1))
        emit(.knock)
    }

    private var now: TimeInterval { clock.now }

    private var isSwiping: Bool { swipeStart != nil || flingTask != nil }

    private func fling(velocity: Double) {
        var fling = DoorFling(degrees: drive.degrees, velocity: velocity, range: drive.range)
        flingTask = Task { [weak self, clock] in
            var last = clock.now
            while !fling.isDone {
                try? await clock.sleep(for: Self.flingStep)
                guard !Task.isCancelled, let self else { return }
                let time = now
                fling.step(time - last)
                last = time
                drive.swipe(to: fling.degrees)
                ingest(.simulated(degrees: drive.degrees, at: time))
            }
            self?.flingTask = nil
            self?.drive.settle()
        }
    }

    private func stopFling() {
        flingTask?.cancel()
        flingTask = nil
    }

    /// The first sample is the door's starting state. A phone without a hinge has had none yet.
    private func startInterpreterIfNeeded() {
        guard !interpreter.hasStarted else { return }
        ingest(hinge ?? .simulated(degrees: drive.degrees, at: now))
    }

    private func ingest(_ reading: HingeReading) {
        Self.logger.debug(
            "door \(reading.degrees, format: .fixed(precision: 1))° \(String(describing: reading.status))")
        for event in interpreter.ingest(reading) {
            handle(event)
        }
        isClosed = interpreter.isLatched
        scheduleSettle()
    }

    /// Hinge samples stop when the hinge stops. If it stopped almost shut, give the interpreter a
    /// chance to latch it after a moment of stillness.
    private func scheduleSettle() {
        settleTask?.cancel()
        guard !interpreter.isLatched else { return }
        settleTask = Task { [weak self, clock] in
            try? await clock.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            for event in interpreter.settle(at: clock.now) {
                handle(event)
            }
            isClosed = interpreter.isLatched
        }
    }

    private func handle(_ event: DoorEvent) {
        if case .swing = event {
        } else {
            Self.logger.debug("event \(String(describing: event)) at \(self.angle, format: .fixed(precision: 1))°")
        }
        switch event {
        case .unlatched:
            sounds.play(.unlatch, volume: 1)
            emit(.unlatch)
        case .swing(let velocity):
            sounds.setCreak(velocity: velocity)
            scheduleCreakFade()
        case .hitOpenStop(let speed):
            sounds.setCreak(velocity: 0)
            sounds.play(.openStop, volume: Float(min(speed / 200, 1)))
            emit(.openStop)
        case .closed(let kind):
            sounds.setCreak(velocity: 0)
            switch kind {
            case .gentle: sounds.play(.latch, volume: 0.6)
            case .firm: sounds.play(.latch, volume: 1)
            case .slam: sounds.play(.slam, volume: 1)
            }
            emit(.closed(kind))
        }
    }

    private func emit(_ kind: DoorFeedback.Kind) {
        feedbackCount += 1
        feedback = DoorFeedback(kind: kind, id: feedbackCount)
    }

    /// Hinge updates stop arriving when the door stops moving, so fade the creak on a timer.
    private func scheduleCreakFade() {
        creakFadeTask?.cancel()
        creakFadeTask = Task { [sounds, clock] in
            try? await clock.sleep(for: Self.creakFadeDelay)
            guard !Task.isCancelled else { return }
            sounds.setCreak(velocity: 0)
        }
    }
}
