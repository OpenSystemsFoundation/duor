import Foundation
import Observation

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

/// Owns door state. Feeds hinge samples to the interpreter and turns events into sound and feedback.
@Observable
final class DoorController {
    /// Latest hinge sample, real or simulated.
    private(set) var reading: HingeReading?
    /// True once the system has delivered a real hinge sample.
    private(set) var hasHardwareHinge = false
    /// The latest thing to feel or see. Views use it as a trigger for haptics and animations.
    private(set) var feedback: DoorFeedback?

    var isClosed: Bool { (reading?.status ?? .closed) == .closed }
    var angle: Double { reading?.degrees ?? 0 }

    @ObservationIgnored private var interpreter = DoorMotionInterpreter()
    @ObservationIgnored private let sounds: any DoorSoundPlaying
    @ObservationIgnored private var creakFadeTask: Task<Void, Never>?
    @ObservationIgnored private var feedbackCount = 0

    init(sounds: any DoorSoundPlaying = DoorAudioEngine()) {
        self.sounds = sounds
    }

    func apply(style: DoorStyle) {
        sounds.apply(style: style)
    }

    /// Input from `onHingeChange`. A nil reading means this device has no hinge.
    func hardwareHingeChanged(_ reading: HingeReading?) {
        guard let reading else { return }
        hasHardwareHinge = true
        ingest(reading)
    }

    /// Input from the on-screen slider on devices without a hinge.
    func simulatedHingeChanged(degrees: Double) {
        guard !hasHardwareHinge else { return }
        ingest(.simulated(degrees: degrees, at: ProcessInfo.processInfo.systemUptime))
    }

    func knock() {
        guard isClosed else { return }
        sounds.play(.knock, volume: Float.random(in: 0.85...1))
        emit(.knock)
    }

    private func ingest(_ reading: HingeReading) {
        self.reading = reading
        for event in interpreter.ingest(reading) {
            handle(event)
        }
    }

    private func handle(_ event: DoorEvent) {
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
