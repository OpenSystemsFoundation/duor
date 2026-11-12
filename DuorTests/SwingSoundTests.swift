import Foundation
import Testing

@testable import Duor

@Suite("Swing sound")
struct SwingSoundTests {
    private let sampleRate: Float = 48_000

    private func render(_ synth: DoorSynth, seconds: Float) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
        samples.withUnsafeMutableBufferPointer { buffer in
            var start = 0
            while start < buffer.count {
                let end = min(start + 256, buffer.count)
                synth.render(into: UnsafeMutableBufferPointer(rebasing: buffer[start..<end]))
                start = end
            }
        }
        return samples
    }

    private func energy(_ samples: some Collection<Float>) -> Float { samples.reduce(0) { $0 + $1 * $1 } }

    /// Swings `profile` from `from` to `to` degrees over `seconds`, fed at `rate` updates per second.
    private func swing(
        _ profile: SoundProfile = .oak, from: Float, to: Float, seconds: Float, rate: Float = 60, seed: UInt32 = 5
    ) -> [Float] {
        let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: seed)
        let steps = Int(seconds * rate)
        let velocity = (to - from) / seconds
        var samples: [Float] = []
        for step in 0..<steps {
            synth.setSwing(angle: from + (to - from) * Float(step) / Float(steps), velocity: velocity)
            samples += render(synth, seconds: 1 / rate)
        }
        synth.setSwing(angle: to, velocity: 0)
        return samples + render(synth, seconds: 0.5)
    }

    // MARK: Friction map

    @Test func frictionMapHasTightSpotsAboveItsFloor() {
        let map = FrictionMap(recipe: .init(count: 2, width: 6...8, strength: 0.5...0.6, floor: 0.1), seed: 3)
        #expect(map.count == 2)
        let grips = stride(from: Float(0), through: 180, by: 0.5).map { map.grip(at: $0, closing: false) }
        #expect(grips.min() == 0.1)
        #expect(grips.max()! > 0.55)
        #expect(grips.allSatisfy { (0...1).contains($0) })
        for index in 0..<map.count {
            let spot = map.spots[index]
            #expect((12...150).contains(spot.angle))
            #expect(map.grip(at: spot.angle, closing: false) >= map.floor + spot.strength - 0.001)
            #expect(map.grip(at: spot.angle + spot.width * 2.5, closing: false) < map.floor + 0.05)
        }
    }

    @Test func closingPassesTheSpotsShiftedAndWeaker() {
        let map = FrictionMap(recipe: .init(count: 1, width: 6...6, strength: 0.8...0.8, floor: 0.1), seed: 9)
        let spot = map.spots[0]
        #expect(map.grip(at: spot.angle + map.closingShift, closing: true) < map.grip(at: spot.angle, closing: false))
        #expect(map.grip(at: spot.angle + map.closingShift, closing: true) > 0.6)
    }

    @Test func sameSeedSameMapAndOtherHardwareMovesTheSpots() {
        let recipe = FrictionMap.Recipe(count: 3, width: 8...12, strength: 0.5...0.9, floor: 0.2)
        #expect(FrictionMap(recipe: recipe, seed: 4) == FrictionMap(recipe: recipe, seed: 4))
        #expect(FrictionMap(recipe: recipe, seed: 4) != FrictionMap(recipe: recipe, seed: 5))
        #expect(SoundProfile.oak.with(metal: .brass).creak.friction != SoundProfile.oak.creak.friction)
        #expect(SoundProfile.oak.with(metal: .iron).creak.friction.count == SoundProfile.oak.creak.friction.count)
    }

    @Test func extremeAnglesAreSafe() {
        let map = SoundProfile.castle.creak.friction
        for angle: Float in [-1_000, -1, 0, 180, 400, .greatestFiniteMagnitude] {
            #expect((0...1).contains(map.grip(at: angle, closing: false)))
        }
    }

    // MARK: Synth

    @Test func swingIsSilentAtRest() {
        let synth = DoorSynth(sampleRate: sampleRate, seed: 2)
        synth.setSwing(angle: 70, velocity: 0)
        #expect(energy(render(synth, seconds: 0.5)) == 0)
    }

    @Test func swingSoundDependsOnWhereTheDoorIs() {
        // The same speed over different stretches of the swing passes different tight spots.
        let first = swing(.barn, from: 10, to: 50, seconds: 1)
        let second = swing(.barn, from: 90, to: 130, seconds: 1)
        #expect(first != second)
        #expect(abs(10 * log10(energy(first) / energy(second))) > 0.5)
    }

    @Test func sameGestureSameSound() {
        #expect(swing(from: 10, to: 100, seconds: 1) == swing(from: 10, to: 100, seconds: 1))
    }

    @Test(arguments: [20, 60, 120] as [Float])
    func swingSoundDoesNotDependOnTheUpdateRate(_ rate: Float) {
        let reference = energy(swing(from: 10, to: 110, seconds: 1, rate: 60))
        let other = energy(swing(from: 10, to: 110, seconds: 1, rate: rate))
        #expect(abs(10 * log10(other / reference)) < 3, "\(rate) Hz")
    }

    @Test func wildSwingInputStaysBounded() {
        let synth = DoorSynth(sampleRate: sampleRate, profile: .castle, seed: 8)
        var random = NoiseSource(seed: 1)
        var samples: [Float] = []
        for _ in 0..<200 {
            synth.setSwing(angle: random.value(in: -50...400), velocity: random.value(in: -3_000...3_000))
            samples += render(synth, seconds: 0.01)
        }
        synth.setSwing(angle: .nan, velocity: .infinity)
        samples += render(synth, seconds: 0.2)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }

    @Test(arguments: ["oak", "cottage", "barn", "castle", "spaceship", "metal"])
    func movementBedRisesWithSpeed(_ door: String) {
        let profiles: [String: SoundProfile] = [
            "oak": .oak, "cottage": .pine, "barn": .barn, "castle": .castle, "spaceship": .spaceship, "metal": .steel,
        ]
        var bed = SwingBedVoice(
            profile: profiles[door]!.bed, hinge: profiles[door]!.hinge, sampleRate: sampleRate, seed: 3)
        func level(_ velocity: Float) -> Float {
            var output = [Float](repeating: 0, count: 9_600)
            var send = output
            bed.setTarget(velocity: velocity)
            output.withUnsafeMutableBufferPointer { out in
                send.withUnsafeMutableBufferPointer { bed.render(into: out, send: $0) }
            }
            return energy(output.suffix(4_800))
        }
        let slow = level(30), fast = level(250)
        #expect(fast > slow * 4, "\(door)")
        _ = level(0)
        _ = level(0)
        #expect(level(0) < 1e-6, "\(door) settles")
    }

    // MARK: Strength

    @Test func strengthRisesSmoothlyWithSpeed() {
        let speeds = stride(from: Float(0), through: 900, by: 5).map(DoorStrength.init(speed:))
        let hardness = speeds.map(\.hardness)
        #expect(hardness == hardness.sorted())
        #expect(hardness.first == 0 && hardness.last == 1)
        let latch = speeds.map(\.latchVolume)
        #expect(latch == latch.sorted())
        // No step at the gentle/firm boundary (90°/s).
        #expect(abs(DoorStrength(speed: 91).latchVolume - DoorStrength(speed: 89).latchVolume) < 0.02)
    }

    @Test func fasterClosesAreLouder() {
        func level(_ sound: DoorSound, _ speed: Float) -> Float {
            let synth = DoorSynth(sampleRate: sampleRate, profile: .oak, seed: 12)
            synth.play(sound, speed: speed)
            return energy(render(synth, seconds: 1))
        }
        let latches = [30, 60, 120, 200].map { level(.latch, $0) }
        #expect(latches == latches.sorted())
        #expect(level(.slam, 600) > level(.slam, 270))
    }
}
