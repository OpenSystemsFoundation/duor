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
    @ObservationIgnored private var creakFadeTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var flingTask: Task<Void, Never>?
    /// The door angle when the current swipe began, while the user is swiping.
    @ObservationIgnored private var swipeStart: Double?
    @ObservationIgnored private var feedbackCount = 0

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Duor", category: "hinge")

    init(sounds: any DoorSoundPlaying = DoorAudioEngine()) {
        self.sounds = sounds
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
        ingest(drive.isSwiped ? .simulated(degrees: drive.degrees, at: reading.timestamp) : reading)
    }

    /// Which screen the door is on. On a phone without a hinge, always the single screen.
    func screenChanged(isInnerDisplay: Bool) {
        let screen: DoorScreen = isInnerDisplay ? .inner : .single
        guard screen != drive.screen else { return }
        stopFling()
        swipeStart = nil
        guard drive.move(to: screen) else { return }
        // A different screen, a different door: no creak or slam for the jump.
        sounds.setCreak(velocity: 0)
        interpreter.restart()
        ingest(hinge ?? .simulated(degrees: drive.degrees, at: now))
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
        fling(velocity: open ? 240 : -120)
    }

    func knock() {
        guard isClosed else { return }
        sounds.play(.knock, volume: Float.random(in: 0.85...1))
        emit(.knock)
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var isSwiping: Bool { swipeStart != nil || flingTask != nil }

    private func fling(velocity: Double) {
        var fling = DoorFling(degrees: drive.degrees, velocity: velocity, range: drive.range)
        flingTask = Task { [weak self] in
            var last = ProcessInfo.processInfo.systemUptime
            while !fling.isDone {
                try? await Task.sleep(for: .milliseconds(16))
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
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            for event in interpreter.settle(at: ProcessInfo.processInfo.systemUptime) {
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
        creakFadeTask = Task { [sounds] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            sounds.setCreak(velocity: 0)
        }
    }
}
