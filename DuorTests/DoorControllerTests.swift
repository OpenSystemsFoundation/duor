import Foundation
import Testing

@testable import Duor

/// A clock that only moves when the test says so. Sleepers wake in order as time is advanced.
private final class ManualClock: DoorClock {
    private(set) var now: TimeInterval = 1000
    private var sleepers: [(wake: TimeInterval, continuation: CheckedContinuation<Void, Never>)] = []

    /// Cancelled sleepers wake at their time anyway; the controller checks for cancellation after.
    func sleep(for duration: Duration) async throws {
        let wake = now + Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        await withCheckedContinuation { sleepers.append((wake, $0)) }
    }

    /// Moves time on by `seconds`, waking every sleeper due on the way and letting it run.
    func advance(by seconds: TimeInterval) async {
        let end = now + seconds
        while true {
            await runPendingTasks()
            guard let index = sleepers.indices.min(by: { sleepers[$0].wake < sleepers[$1].wake }),
                sleepers[index].wake <= end
            else { break }
            let sleeper = sleepers.remove(at: index)
            now = max(now, sleeper.wake)
            sleeper.continuation.resume()
        }
        now = end
        await runPendingTasks()
    }

    private func runPendingTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

/// Records what the controller asks the audio engine to do.
private final class SoundRecorder: DoorSoundPlaying {
    var played: [DoorSound] = []
    var speeds: [Double] = []
    var creak: Double = 0
    var creakAngles: [Double] = []
    var hasCreaked = false

    func apply(profile: SoundProfile) {}
    func play(_ sound: DoorSound, speed: Double) {
        played.append(sound)
        speeds.append(speed)
    }
    func knock(at spot: KnockSpot, volume: Float) {}
    func setSwing(angle: Double, velocity: Double) {
        creak = velocity
        if velocity != 0 {
            hasCreaked = true
            creakAngles.append(angle)
        }
    }
}

@Suite("DoorController")
struct DoorControllerTests {
    private let sounds = SoundRecorder()
    private let clock = ManualClock()
    private let controller: DoorController
    /// A swipe across this much of a 400-point-wide screen is a full swing.
    private let width = 400.0

    init() {
        controller = DoorController(sounds: sounds, clock: clock)
        // A phone without a hinge: one flat screen, and swiping is the only way in.
        controller.screenChanged(to: .single)
    }

    /// Swipes the door from where it is to about `degrees`, and lets go without flinging it.
    private func swipe(to degrees: Double) async {
        let points = (degrees - controller.angle) / 180 * width * DoorSwipe.fullSwing
        controller.swipeChanged(translation: -points / 2, width: width)
        await clock.advance(by: 0.05)
        controller.swipeChanged(translation: -points, width: width)
        await clock.advance(by: 0.05)
        controller.swipeEnded(velocity: 0, width: width)
        await clock.advance(by: 1)
    }

    @Test func swipingOpenUnlatchesAndCreaks() async {
        await swipe(to: 60)
        #expect(sounds.played == [.unlatch])
        #expect(sounds.hasCreaked)
        #expect(!controller.isClosed)
        #expect(abs(controller.angle - 60) < 1)
    }

    @Test func swingSoundFollowsTheDoorAngle() async {
        await swipe(to: 60)
        #expect(!sounds.creakAngles.isEmpty)
        #expect(sounds.creakAngles == sounds.creakAngles.sorted(), "opening: the angle only rises")
        #expect(sounds.creakAngles.allSatisfy { (0...61).contains($0) })
    }

    @Test func harderClosesCarryTheirSpeed() async throws {
        await swipe(to: 90)
        controller.swipeChanged(translation: 20, width: width)
        controller.swipeEnded(velocity: 3000, width: width)
        await clock.advance(by: 1)
        let slamSpeed = try #require(sounds.speeds.last)
        #expect(slamSpeed >= DoorMotionInterpreter.Configuration().slamSpeed)
    }

    @Test func creakFadesOnceTheDoorStops() async {
        await swipe(to: 60)
        #expect(sounds.creak == 0)
    }

    @Test func flingingShutHardSlams() async {
        await swipe(to: 90)
        controller.swipeChanged(translation: 20, width: width)
        controller.swipeEnded(velocity: 3000, width: width)
        await clock.advance(by: 1)
        #expect(sounds.played.last == .slam)
        #expect(controller.isClosed)
        #expect(controller.feedback?.kind == .closed(.slam))
    }

    @Test func flingingOpenHardHitsTheStop() async {
        controller.swipeChanged(translation: -20, width: width)
        controller.swipeEnded(velocity: -3000, width: width)
        await clock.advance(by: 2)
        #expect(sounds.played == [.unlatch, .openStop])
        #expect(controller.angle == 180)
    }

    @Test func aSlowDoorNearlyShutSwingsItselfShut() async {
        await swipe(to: 30)
        controller.swipeChanged(translation: 40, width: width)
        controller.swipeEnded(velocity: 0, width: width)
        await clock.advance(by: 2)
        #expect(controller.isClosed)
        #expect(controller.feedback?.kind == .closed(.gentle))
    }

    @Test(arguments: [45.0, 90.0, 135.0, 180.0])
    func closeDoorActionClosesFromAnyAngle(open degrees: Double) async {
        await swipe(to: degrees)
        #expect(!controller.isClosed)
        controller.swing(open: false)
        await clock.advance(by: 3)
        #expect(controller.isClosed, "stuck at \(controller.angle)°")
        #expect(controller.feedback?.kind == .closed(.gentle))
    }

    @Test func openAndCloseActionsRoundTrip() async {
        controller.swing(open: true)
        await clock.advance(by: 3)
        #expect(!controller.isClosed)
        #expect(controller.angle > 60)
        controller.swing(open: false)
        await clock.advance(by: 3)
        #expect(controller.isClosed)
    }

    @Test func hingeComingToRestNearlyShutLatches() async {
        let controller = DoorController(sounds: sounds, clock: clock)
        controller.hardwareHingeChanged(HingeReading(degrees: 90, status: .partiallyOpen, timestamp: clock.now))
        await clock.advance(by: 0.1)
        controller.hardwareHingeChanged(HingeReading(degrees: 10, status: .closed, timestamp: clock.now))
        #expect(!controller.isClosed, "10° is not shut yet")
        await clock.advance(by: 0.5)
        #expect(controller.isClosed, "still for long enough at 10°: latched")
    }

    @Test func movingToAnotherScreenDoesNotSlam() async {
        let controller = DoorController(sounds: sounds, clock: clock)
        controller.screenChanged(to: .inner)
        controller.hardwareHingeChanged(HingeReading(degrees: 120, status: .partiallyOpen, timestamp: clock.now))
        await clock.advance(by: 0.1)
        // Split View: the door rests shut in its window, without a slam for the jump.
        controller.screenChanged(to: .window)
        await clock.advance(by: 1)
        #expect(controller.angle == 0)
        #expect(!sounds.played.contains(.slam))
        #expect(!sounds.played.contains(.latch))
    }
}
