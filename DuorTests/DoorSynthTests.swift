import Testing

@testable import Duor

@Suite("DoorSynth")
struct DoorSynthTests {
    private let sampleRate: Float = 48_000

    /// Renders in hardware-sized blocks, the way the audio thread calls the synth.
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

    private func peak(_ samples: some Collection<Float>) -> Float {
        samples.map(abs).max() ?? 0
    }

    @Test func idleIsSilent() {
        let synth = DoorSynth(sampleRate: sampleRate, seed: 1)
        #expect(peak(render(synth, seconds: 0.2)) == 0)
    }

    @Test(arguments: DoorSound.allCases)
    func soundIsAudibleBoundedAndDecays(_ sound: DoorSound) {
        let synth = DoorSynth(sampleRate: sampleRate, seed: 7)
        synth.play(sound)
        let samples = render(synth, seconds: 2.5)

        #expect(samples.allSatisfy { $0.isFinite })
        #expect(peak(samples) > 0.05, "too quiet")
        #expect(peak(samples) <= 1)
        let tail = samples.suffix(Int(0.2 * sampleRate))
        #expect(peak(tail) < 0.001, "still ringing after 2.3 s")
    }

    @Test func sameSeedRendersIdentically() {
        let first = DoorSynth(sampleRate: sampleRate, seed: 99)
        let second = DoorSynth(sampleRate: sampleRate, seed: 99)
        first.play(.slam)
        second.play(.slam)
        #expect(render(first, seconds: 0.5) == render(second, seconds: 0.5))
    }

    @Test func knocksVary() {
        let synth = DoorSynth(sampleRate: sampleRate, seed: 3)
        synth.play(.knock)
        let first = render(synth, seconds: 0.6)
        synth.play(.knock)
        let second = render(synth, seconds: 0.6)
        #expect(first != second)
    }

    @Test func creakFollowsHingeSpeed() {
        func energy(atVelocity velocity: Float) -> Float {
            let synth = DoorSynth(sampleRate: sampleRate, seed: 5)
            synth.setSwing(angle: 60, velocity: velocity)
            let samples = render(synth, seconds: 0.6).suffix(Int(0.3 * sampleRate))
            return samples.reduce(0) { $0 + $1 * $1 }
        }
        #expect(energy(atVelocity: 0) == 0)
        #expect(energy(atVelocity: 15) > 0)
        #expect(energy(atVelocity: -120) > energy(atVelocity: 15))
    }

    @Test func creakFadesWhenHingeStops() {
        let synth = DoorSynth(sampleRate: sampleRate, seed: 5)
        synth.setSwing(angle: 60, velocity: 90)
        _ = render(synth, seconds: 0.5)
        synth.setSwing(angle: 60, velocity: 0)
        let after = render(synth, seconds: 1.5)
        #expect(peak(after.suffix(Int(0.3 * sampleRate))) < 0.001)
    }

    @Test func burstOfCommandsIsBounded() {
        let synth = DoorSynth(sampleRate: sampleRate, seed: 11)
        for _ in 0..<200 {
            synth.play(.slam)
        }
        let samples = render(synth, seconds: 0.5)
        #expect(samples.allSatisfy { $0.isFinite })
        #expect(peak(samples) <= 1)
    }

    @Test(arguments: ["oak", "pine", "barn", "castle", "spaceship", "steel"])
    func everyDoorSoundsCleanly(_ door: String) {
        let profiles: [String: SoundProfile] = [
            "oak": .oak, "pine": .pine, "barn": .barn, "castle": .castle, "spaceship": .spaceship, "steel": .steel,
        ]
        for sound in DoorSound.allCases {
            let synth = DoorSynth(sampleRate: sampleRate, profile: profiles[door]!.with(metal: .brass), seed: 9)
            synth.play(sound)
            let samples = render(synth, seconds: 3.5)
            #expect(samples.allSatisfy { $0.isFinite }, "\(door) \(sound)")
            #expect(peak(samples) > 0.05, "\(door) \(sound) too quiet")
            #expect(peak(samples) <= 1, "\(door) \(sound)")
            #expect(peak(samples.suffix(Int(0.3 * sampleRate))) < 0.002, "\(door) \(sound) still ringing")
        }
    }

    @Test func doorsSoundDifferent() {
        func knock(_ profile: SoundProfile) -> [Float] {
            let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: 1)
            synth.play(.knock)
            return render(synth, seconds: 0.3)
        }
        let knocks = [SoundProfile.oak, .pine, .barn, .castle, .spaceship, .steel].map(knock)
        for (index, first) in knocks.enumerated() {
            for second in knocks[(index + 1)...] {
                #expect(first != second)
            }
        }
    }
}

extension DoorSynthTests {
    @Test func knockSpotChangesSound() {
        func knock(at spot: KnockSpot) -> [Float] {
            let synth = DoorSynth(sampleRate: sampleRate, profile: .pine, seed: 4)
            synth.knock(at: spot)
            return render(synth, seconds: 0.4)
        }
        let middle = knock(at: .center)
        let edge = knock(at: KnockSpot(x: 0.05, y: 0.5))
        #expect(middle != edge)
        // The stiff edge rings out sooner than the middle of the leaf.
        let tail = { (samples: [Float]) in samples[Int(0.08 * sampleRate)...].reduce(0) { $0 + $1 * $1 } }
        #expect(tail(edge) < tail(middle))
    }

    @Test(arguments: ["oak", "pine", "barn", "castle", "spaceship", "steel"])
    func knocksAnywhereSoundCleanly(_ door: String) {
        let profiles: [String: SoundProfile] = [
            "oak": .oak, "pine": .pine, "barn": .barn, "castle": .castle, "spaceship": .spaceship, "steel": .steel,
        ]
        let stops: [Float] = [0, 0.25, 0.5, 0.75, 1]
        for x in stops {
            for y in stops {
                let synth = DoorSynth(sampleRate: sampleRate, profile: profiles[door]!, seed: 13)
                synth.knock(at: KnockSpot(x: x, y: y))
                let samples = render(synth, seconds: 1.5)
                #expect(samples.allSatisfy { $0.isFinite }, "\(door) at \(x), \(y)")
                #expect(peak(samples) > 0.05, "\(door) at \(x), \(y) too quiet")
                #expect(peak(samples) <= 1, "\(door) at \(x), \(y)")
                #expect(peak(samples.suffix(Int(0.3 * sampleRate))) < 0.002, "\(door) at \(x), \(y) still ringing")
            }
        }
    }
}

@Suite("KnockSpot")
struct KnockSpotTests {
    @Test func middleIsDeeperAndRingsLongerThanEdge() {
        let middle = KnockSpot.center
        let edge = KnockSpot(x: 0.04, y: 0.5)
        #expect(middle.centerness == 1)
        #expect(edge.centerness < 0.3)
        #expect(edge.pitchScale > middle.pitchScale)
        #expect(edge.decayScale < middle.decayScale)
        #expect(edge.contactScale < middle.contactScale)
        #expect(edge.thumpScale > middle.thumpScale)
    }

    @Test func spotShapesTimbre() {
        let modes = SoundProfile.oak.knock
        let middle = KnockSpot.center.excite(modes)
        let quarter = KnockSpot(x: 0.5, y: 0.25).excite(modes)
        // The second mode has a node across the middle and moves most a quarter of the way down.
        #expect(quarter[1].gain / quarter[0].gain > middle[1].gain / middle[0].gain)
        for index in modes.indices {
            #expect(middle[index].frequency == modes[index].frequency)
            #expect(middle[index].gain > 0)
        }
    }

    @Test func latchRattlesOnlyNearTheHandle() {
        #expect(KnockSpot(x: 0.95, y: 0.5).latchRattle > 0.5)
        #expect(KnockSpot(x: 0.95, y: 0.05).latchRattle < 0.02)
        #expect(KnockSpot(x: 0.1, y: 0.5).latchRattle == 0)
        #expect(KnockSpot.center.latchRattle == 0)
    }

    @Test func nudgeStaysCloseAndOnTheDoor() {
        var random = NoiseSource(seed: 8)
        var spots: [KnockSpot] = []
        for _ in 0..<100 {
            let spot = KnockSpot(x: 0.99, y: 0.5).nudged(by: &random)
            #expect((0...1).contains(spot.x) && (0...1).contains(spot.y))
            #expect(abs(spot.x - 0.99) <= 0.031 && abs(spot.y - 0.5) <= 0.031)
            spots.append(spot)
        }
        #expect(Set(spots.map(\.y)).count > 90)
    }

    @Test func outOfRangeIsClamped() {
        let spot = KnockSpot(x: -1, y: .nan)
        #expect(spot.x == 0)
        #expect(spot.y == 0.5)
        #expect(KnockSpot(x: 3, y: 2) == KnockSpot(x: 1, y: 1))
    }
}
