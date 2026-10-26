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
        synth.play(sound, volume: 1)
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
            synth.setCreak(velocity: velocity)
            let samples = render(synth, seconds: 0.6).suffix(Int(0.3 * sampleRate))
            return samples.reduce(0) { $0 + $1 * $1 }
        }
        #expect(energy(atVelocity: 0) == 0)
        #expect(energy(atVelocity: 15) > 0)
        #expect(energy(atVelocity: -120) > energy(atVelocity: 15))
    }

    @Test func creakFadesWhenHingeStops() {
        let synth = DoorSynth(sampleRate: sampleRate, seed: 5)
        synth.setCreak(velocity: 90)
        _ = render(synth, seconds: 0.5)
        synth.setCreak(velocity: 0)
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

    @Test(arguments: ["oak", "pine", "barn", "castle", "modern"])
    func everyDoorSoundsCleanly(_ door: String) {
        let profiles: [String: SoundProfile] = [
            "oak": .oak, "pine": .pine, "barn": .barn, "castle": .castle, "modern": .modern,
        ]
        for sound in DoorSound.allCases {
            let synth = DoorSynth(sampleRate: sampleRate, profile: profiles[door]!.with(metal: .brass), seed: 9)
            synth.play(sound, volume: 1)
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
        let knocks = [SoundProfile.oak, .pine, .barn, .castle, .modern].map(knock)
        for (index, first) in knocks.enumerated() {
            for second in knocks[(index + 1)...] {
                #expect(first != second)
            }
        }
    }
}
