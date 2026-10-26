import Testing

@testable import Duor

@Suite("DoorMotionInterpreter")
struct DoorMotionInterpreterTests {
    private func reading(_ degrees: Double, at t: Double) -> HingeReading {
        .simulated(degrees: degrees, at: t)
    }

    @Test func firstReadingProducesNoEvents() {
        var interpreter = DoorMotionInterpreter()
        #expect(interpreter.ingest(reading(90, at: 0)).isEmpty)
    }

    @Test func leavingClosedUnlatches() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(0, at: 0))
        let events = interpreter.ingest(reading(10, at: 0.1))
        #expect(events.first == .unlatched)
    }

    @Test func openingSwingHasPositiveVelocity() throws {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(30, at: 0))
        let events = interpreter.ingest(reading(60, at: 0.1))
        let velocity = try #require(events.compactMap { if case .swing(let v) = $0 { v } else { nil } }.first)
        #expect(velocity > 0)
    }

    @Test func tinyMovementDoesNotCreak() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(90, at: 0))
        #expect(interpreter.ingest(reading(90.1, at: 0.1)).isEmpty)
    }

    @Test(arguments: [
        (from: 20.0, duration: 0.5, expected: CloseKind.gentle),
        (from: 40.0, duration: 0.25, expected: CloseKind.firm),
        (from: 90.0, duration: 0.1, expected: CloseKind.slam),
    ])
    func closingSpeedPicksCloseKind(from: Double, duration: Double, expected: CloseKind) {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(from, at: 0))
        let events = interpreter.ingest(reading(0, at: duration))
        #expect(events.contains(.closed(expected)))
    }

    @Test func longPauseIsNotASlam() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(30, at: 0))
        // 30° after 5 seconds of silence is capped at the max sample gap (30 / 0.25 = 120°/s).
        let events = interpreter.ingest(reading(0, at: 5))
        #expect(!events.contains(.closed(.slam)))
    }

    @Test func reachingFlatHitsOpenStop() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(150, at: 0))
        let events = interpreter.ingest(reading(180, at: 0.1))
        #expect(events.contains { if case .hitOpenStop = $0 { true } else { false } })
    }

    @Test func jitterAtFullyOpenIsSilent() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(140, at: 0))
        _ = interpreter.ingest(reading(180, at: 0.2))
        // The sensor wobbles around flat; status flickers between fully and partially open.
        var events: [DoorEvent] = []
        for (index, degrees) in [179.2, 180, 178.9, 179.6, 180, 178.7, 179.9].enumerated() {
            events += interpreter.ingest(reading(degrees, at: 0.3 + Double(index) / 60))
        }
        #expect(events.isEmpty)
    }

    @Test func flickerAtClosedIsSilent() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(0, at: 0))
        var events: [DoorEvent] = []
        for (index, degrees) in [1.4, 0, 2.1, 0.5, 0, 1.8].enumerated() {
            events += interpreter.ingest(reading(degrees, at: Double(index + 1) / 60))
        }
        #expect(events.isEmpty)
    }

    @Test func closesOnceThenUnlatchesOnRealOpen() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(40, at: 0))
        let closing = interpreter.ingest(reading(0, at: 0.3))
        let flicker = interpreter.ingest(reading(1.5, at: 0.32)) + interpreter.ingest(reading(0, at: 0.34))
        let opening = interpreter.ingest(reading(12, at: 0.5))
        #expect(closing.filter { if case .closed = $0 { true } else { false } }.count == 1)
        #expect(flicker.isEmpty)
        #expect(opening.first == .unlatched)
    }

    @Test func slowOpeningStillCreaks() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(20, at: 0))
        var events: [DoorEvent] = []
        // 15°/s at 60 Hz: each sample moves only 0.25°, below the jitter tolerance.
        for step in 1...60 {
            events += interpreter.ingest(reading(20 + Double(step) * 0.25, at: Double(step) / 60))
        }
        #expect(events.contains { if case .swing = $0 { true } else { false } })
    }

    @Test func openStopRearmsAfterSwingingBack() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(150, at: 0))
        let first = interpreter.ingest(reading(180, at: 0.1))
        _ = interpreter.ingest(reading(160, at: 0.3))
        let second = interpreter.ingest(reading(180, at: 0.4))
        let isStop = { (event: DoorEvent) in if case .hitOpenStop = event { true } else { false } }
        #expect(first.contains(where: isStop))
        #expect(second.contains(where: isStop))
    }

    @Test func systemClosedStatusDoesNotLatchEarly() {
        // While folding, the system reports `.closed` from ~85°. Only the angle should latch.
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(HingeReading(degrees: 100, status: .partiallyOpen, timestamp: 0))
        var early: [DoorEvent] = []
        for (index, degrees) in [84.0, 60, 30, 10, 4].enumerated() {
            early += interpreter.ingest(
                HingeReading(degrees: degrees, status: .closed, timestamp: Double(index + 1) * 0.05))
        }
        let shut = interpreter.ingest(HingeReading(degrees: 0, status: .closed, timestamp: 0.3))
        #expect(!early.contains { if case .closed = $0 { true } else { false } })
        #expect(shut.contains { if case .closed = $0 { true } else { false } })
    }

    @Test func restingAlmostShutLatchesAfterAMoment() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(30, at: 0))
        // Updates thin out near shut: the last sample says 5°, and the system already says closed.
        _ = interpreter.ingest(HingeReading(degrees: 5, status: .closed, timestamp: 0.2))
        #expect(interpreter.settle(at: 0.3).isEmpty)
        #expect(interpreter.settle(at: 0.6).count == 1)
        #expect(interpreter.isLatched)
    }

    @Test func restingHalfOpenNeverLatches() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(reading(30, at: 0))
        #expect(interpreter.settle(at: 5).isEmpty)
    }
}
