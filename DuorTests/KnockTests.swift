import CoreGraphics
import Testing

@testable import Duor

/// Records what the controller asks the audio engine to do.
private final class SoundRecorder: DoorSoundPlaying {
    var knocks: [(spot: KnockSpot, volume: Float)] = []
    var played: [DoorSound] = []

    func apply(profile: SoundProfile) {}
    func play(_ sound: DoorSound, volume: Float) { played.append(sound) }
    func knock(at spot: KnockSpot, volume: Float) { knocks.append((spot, volume)) }
    func setCreak(velocity: Double) {}
}

@Suite("Knocking")
struct KnockTests {
    // MARK: Controller

    @Test func knockOnClosedDoorPlaysAtTheSpot() {
        let sounds = SoundRecorder()
        let controller = DoorController(sounds: sounds)
        let spot = KnockSpot(x: 0.9, y: 0.45)
        controller.knock(at: spot)
        #expect(sounds.knocks.count == 1)
        #expect(sounds.knocks.first?.spot == spot)
        #expect((0.85...1).contains(sounds.knocks.first?.volume ?? 0))
        #expect(sounds.played.isEmpty, "knocks go through knock(at:), not play(.knock)")
        #expect(controller.feedback?.kind == .knock)
    }

    @Test func knockWithoutSpotLandsInTheMiddle() {
        let sounds = SoundRecorder()
        DoorController(sounds: sounds).knock()
        #expect(sounds.knocks.first?.spot == .center)
    }

    @Test func repeatedKnocksEachGiveFeedback() throws {
        let controller = DoorController(sounds: SoundRecorder())
        controller.knock(at: .center)
        let first = try #require(controller.feedback)
        controller.knock(at: .center)
        let second = try #require(controller.feedback)
        #expect(second.kind == .knock)
        #expect(second.id != first.id)
    }

    @Test func openDoorCannotBeKnocked() {
        let sounds = SoundRecorder()
        let controller = DoorController(sounds: sounds)
        controller.hardwareHingeChanged(.simulated(degrees: 0, at: 0))
        controller.hardwareHingeChanged(.simulated(degrees: 120, at: 1))
        #expect(!controller.isClosed)
        let feedback = controller.feedback
        controller.knock(at: .center)
        #expect(sounds.knocks.isEmpty)
        #expect(controller.feedback == feedback)
    }

    // MARK: Tap to spot

    @Test func tapMapsOntoTheLeaf() {
        let size = CGSize(width: 400, height: 800)
        #expect(KnockSpot(tap: CGPoint(x: 200, y: 400), in: size) == .center)
        // x runs from the hinge (leading) edge to the latch edge, y from the top.
        #expect(KnockSpot(tap: CGPoint(x: 0, y: 0), in: size) == KnockSpot(x: 0, y: 0))
        #expect(KnockSpot(tap: CGPoint(x: 380, y: 360), in: size) == KnockSpot(x: 0.95, y: 0.45))
        #expect(KnockSpot(tap: CGPoint(x: 400, y: 800), in: size) == KnockSpot(x: 1, y: 1))
    }

    @Test func tapOutsideTheLeafIsClamped() {
        let size = CGSize(width: 400, height: 800)
        #expect(KnockSpot(tap: CGPoint(x: -20, y: 900), in: size) == KnockSpot(x: 0, y: 1))
    }

    @Test func tapBeforeTheSizeIsKnownLandsInTheMiddle() {
        #expect(KnockSpot(tap: CGPoint(x: 30, y: 40), in: .zero) == .center)
        #expect(KnockSpot(tap: CGPoint(x: 30, y: 40), in: CGSize(width: 0, height: 800)) == .center)
    }
}
