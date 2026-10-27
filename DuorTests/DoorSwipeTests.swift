import Testing

@testable import Duor

@Suite("DoorSwipe")
struct DoorSwipeTests {
    // MARK: Drive

    @Test func hingeHasTheDoorUntilASwipe() {
        var drive = DoorDrive(screen: .inner, hinge: 120)
        #expect(drive.degrees == 120)
        #expect(!drive.isSwiped)
        drive.swipe(to: 40)
        #expect(drive.degrees == 40)
        #expect(drive.isSwiped)
    }

    @Test func innerDisplayDoorNeverOpensPastThePhone() {
        var drive = DoorDrive(screen: .inner, hinge: 120)
        drive.swipe(to: 170)
        #expect(drive.degrees == 120)
    }

    @Test func singleScreenDoorOpensAllTheWayOnAFoldedPhone() {
        var drive = DoorDrive(screen: .single, hinge: 0)
        drive.swipe(to: 170)
        #expect(drive.degrees == 170)
        drive.swipe(to: 400)
        #expect(drive.degrees == 180)
    }

    @Test func foldingThePhoneKeepsASwipedShutDoorShut() {
        var drive = DoorDrive(screen: .inner, hinge: 180)
        drive.swipe(to: 0)
        for hinge in stride(from: 180.0, through: 30, by: -10) {
            drive.hinge = hinge
            drive.settle()
            #expect(drive.degrees == 0)
        }
        // Folded down to meet the door: the hinge has it again.
        drive.hinge = 1
        drive.settle()
        #expect(!drive.isSwiped)
    }

    @Test func swipingOpenAsFarAsThePhoneHandsBackToTheHinge() {
        var drive = DoorDrive(screen: .inner, hinge: 150)
        drive.swipe(to: 60)
        drive.settle()
        #expect(drive.isSwiped)
        drive.swipe(to: 150)
        drive.settle()
        #expect(!drive.isSwiped)
    }

    @Test func swipingShutOnASingleScreenHandsBackToTheHinge() {
        var drive = DoorDrive(screen: .single, hinge: 0)
        drive.swipe(to: 90)
        drive.settle()
        #expect(drive.isSwiped)
        drive.swipe(to: 0)
        drive.settle()
        #expect(!drive.isSwiped)
    }

    @Test func changingScreensHandsBackToTheHingeAndReportsTheJump() {
        // Swiped open on the cover display, then unfolded.
        var drive = DoorDrive(screen: .single, hinge: 0)
        drive.swipe(to: 120)
        drive.hinge = 40
        let jumped = drive.move(to: .inner)
        #expect(jumped)
        #expect(drive.degrees == 40)
        #expect(!drive.isSwiped)
        // Folding shut on a door the hinge already had: no jump.
        drive.hinge = 0
        let jumpedBack = drive.move(to: .single)
        #expect(!jumpedBack)
    }

    // MARK: Swipe

    @Test func swipingLeftOpensAndRightCloses() {
        #expect(DoorSwipe.degrees(from: 0, translation: -100, width: 400) > 0)
        #expect(DoorSwipe.degrees(from: 90, translation: 100, width: 400) < 90)
        #expect(DoorSwipe.velocity(-500, width: 400) > 0)
    }

    @Test func mostOfTheWidthIsAFullSwing() {
        let width = 400.0
        let full = DoorSwipe.degrees(from: 0, translation: -width * DoorSwipe.fullSwing, width: width)
        #expect(abs(full - 180) < 0.001)
    }

    // MARK: Fling

    private func run(_ fling: DoorFling, seconds: Double = 10) -> DoorFling {
        var fling = fling
        for _ in 0..<Int(seconds * 60) where !fling.isDone {
            fling.step(1.0 / 60)
        }
        return fling
    }

    @Test func gentlePushComesToRestAjar() {
        let fling = run(DoorFling(degrees: 60, velocity: 60, range: 0...180))
        #expect(fling.isDone)
        #expect(fling.degrees > 70 && fling.degrees < 120)
    }

    @Test func hardFlickStopsAtTheOpenStop() {
        let fling = run(DoorFling(degrees: 20, velocity: 900, range: 0...180))
        #expect(fling.isDone)
        #expect(fling.degrees == 180)
    }

    @Test func innerDisplayFlingStopsAtThePhone() {
        let fling = run(DoorFling(degrees: 20, velocity: 900, range: 0...130))
        #expect(fling.degrees == 130)
    }

    @Test func hardFlickShutSlams() {
        var fling = DoorFling(degrees: 120, velocity: -900, range: 0...180)
        var interpreter = DoorMotionInterpreter()
        var events = interpreter.ingest(.simulated(degrees: fling.degrees, at: 0))
        var time = 0.0
        while !fling.isDone {
            fling.step(1.0 / 60)
            time += 1.0 / 60
            events += interpreter.ingest(.simulated(degrees: fling.degrees, at: time))
        }
        #expect(events.contains(.closed(.slam)))
    }

    @Test func nearlyShutDoorSwingsItselfShutGently() {
        var fling = DoorFling(degrees: 7, velocity: 0, range: 0...180)
        var interpreter = DoorMotionInterpreter()
        var events = interpreter.ingest(.simulated(degrees: fling.degrees, at: 0))
        var time = 0.0
        while !fling.isDone {
            fling.step(1.0 / 60)
            time += 1.0 / 60
            events += interpreter.ingest(.simulated(degrees: fling.degrees, at: time))
        }
        #expect(fling.degrees == 0)
        #expect(events.contains(.closed(.gentle)))
    }

    // MARK: Interpreter

    @Test func restartTakesTheNextSampleAsTheStart() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(.simulated(degrees: 120, at: 0))
        interpreter.restart()
        #expect(!interpreter.hasStarted)
        // A jump to shut after a restart is not a slam.
        #expect(interpreter.ingest(.simulated(degrees: 0, at: 0.01)).isEmpty)
        #expect(interpreter.isLatched)
    }

    @Test func startingAtRestNearlyShutIsLatched() {
        var interpreter = DoorMotionInterpreter()
        _ = interpreter.ingest(HingeReading(degrees: 10, status: .closed, timestamp: 0))
        #expect(interpreter.isLatched)
    }
}
