import CoreGraphics
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

    @Test func turningSwipingOffHandsBackToTheHinge() {
        var drive = DoorDrive(screen: .single, hinge: 0)
        drive.swipe(to: 90)
        let jumped = drive.release()
        #expect(jumped)
        #expect(!drive.isSwiped)
        #expect(drive.degrees == 0)
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

    // MARK: Slide

    @Test func shutDoorCoversTheFrame() {
        let slide = DoorSlide(degrees: 0)
        #expect(!slide.isOpen)
        #expect(slide.scale == 1)
        #expect(slide.offset(width: 400) == 0)
    }

    @Test func openDoorIsEntirelyOffScreen() {
        let width = 400.0
        let slide = DoorSlide(degrees: 180)
        #expect(slide.uncovered == 1)
        // The trailing edge of the door, grown about its center, plus its shadow.
        let trailingEdge = width / 2 + width * slide.scale / 2 + DoorSlide.shadowWidth + slide.offset(width: width)
        #expect(trailingEdge <= 0.001)
    }

    @Test func doorSlidesFurtherTheMoreItOpens() {
        let width = 400.0
        let offsets = stride(from: 0.0, through: 180, by: 20).map { DoorSlide(degrees: $0).offset(width: width) }
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test func doorIsLiftedWhileItSlides() {
        #expect(DoorSlide(degrees: 10).scale > 1)
        #expect(DoorSlide(degrees: 90).scale == 1 + DoorSlide.lift)
        #expect(DoorSlide(degrees: 400).uncovered == 1)
        #expect(DoorSlide(degrees: -5).uncovered == 0)
    }

    // MARK: Swipe mode

    @Test func swipeModeIsOffByDefaultWithAHinge() {
        #expect(!SwipeMode.isOnByDefault(hasHinge: true))
        #expect(!SwipeMode.isOn(saved: nil, hasHinge: true))
    }

    @Test func swipeModeKeepsTheUsersChoiceWithAHinge() {
        #expect(SwipeMode.isOn(saved: true, hasHinge: true))
        #expect(!SwipeMode.isOn(saved: false, hasHinge: true))
    }

    @Test func swipeModeIsAlwaysOnWithoutAHinge() {
        #expect(SwipeMode.isOnByDefault(hasHinge: false))
        #expect(SwipeMode.isOn(saved: nil, hasHinge: false))
        #expect(SwipeMode.isOn(saved: false, hasHinge: false))
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

    // MARK: Split View

    @Test func windowDoorRestsShutWhateverTheHinge() {
        var drive = DoorDrive(screen: .window, hinge: 180)
        #expect(drive.degrees == 0)
        #expect(!drive.followsHinge)
        drive.swipe(to: 120)
        drive.settle()
        // Open, and it stays open: the hinge doesn't hold this door.
        #expect(drive.degrees == 120)
        drive.hinge = 90
        drive.settle()
        #expect(drive.degrees == 120)
        drive.swipe(to: 0)
        drive.settle()
        #expect(!drive.isSwiped)
        #expect(drive.degrees == 0)
    }

    @Test func movingIntoAWindowShutsTheDoor() {
        var drive = DoorDrive(screen: .inner, hinge: 180)
        let jumped = drive.move(to: .window)
        #expect(jumped)
        #expect(drive.degrees == 0)
    }

    @Test func splitViewShowsTheFrontOfTheDoor() {
        #expect(DoorScreen.current(hasHinge: true, fillsScreen: false, hasFold: false, isFullyOpen: true) == .window)
        #expect(DoorScreen.current(hasHinge: true, fillsScreen: true, hasFold: true, isFullyOpen: true) == .inner)
        #expect(DoorScreen.current(hasHinge: true, fillsScreen: true, hasFold: false, isFullyOpen: false) == .single)
        #expect(DoorScreen.current(hasHinge: false, fillsScreen: false, hasFold: false, isFullyOpen: false) == .single)
    }

    @Test func windowFillsTheScreenEitherWayRound() {
        let screen = CGSize(width: 1017, height: 700)
        #expect(WindowFit.fills(window: screen, screen: screen))
        #expect(WindowFit.fills(window: CGSize(width: 700, height: 1017), screen: screen))
        #expect(!WindowFit.fills(window: CGSize(width: 508, height: 700), screen: screen))
    }
}
