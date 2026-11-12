import Testing

@testable import Duor

@Suite("OutputFader")
struct OutputFaderTests {
    private let frames = 256

    /// A full-scale buffer, run through the fader.
    private func buffer(_ fader: OutputFader) -> [Float] {
        var samples = [Float](repeating: 1, count: frames)
        samples.withUnsafeMutableBufferPointer { fader.apply(to: $0) }
        return samples
    }

    private func largestStep(_ samples: [Float], from previous: Float) -> Float {
        zip(samples, [previous] + samples).map { abs($0 - $1) }.max() ?? 0
    }

    @Test func leavesTheSoundAloneUntilAskedToFade() {
        let fader = OutputFader(sampleRate: 48_000)
        #expect(buffer(fader).allSatisfy { $0 == 1 })
        #expect(!fader.isSilent)
    }

    @Test func rampsToSilenceWithoutAJump() {
        let fader = OutputFader(sampleRate: 48_000)
        fader.requestFade()
        let ramp = buffer(fader)
        // 5 ms at 48 kHz is 240 frames: down to nothing inside one 256-frame buffer, in small steps.
        #expect(ramp.last == 0)
        #expect(largestStep(ramp, from: 1) < 0.01)
        // The buffer that reached silence may still be playing: not done until a silent one follows.
        #expect(!fader.isSilent)
        #expect(buffer(fader).allSatisfy { $0 == 0 })
        #expect(fader.isSilent)
    }

    @Test func resetRampsBackUpWithoutAJump() {
        let fader = OutputFader(sampleRate: 48_000)
        fader.requestFade()
        _ = buffer(fader)
        _ = buffer(fader)
        fader.reset()
        #expect(!fader.isSilent)
        let ramp = buffer(fader)
        #expect(ramp.first ?? 1 < 0.01)
        #expect(largestStep(ramp, from: 0) < 0.01)
        #expect(ramp.last == 1)
        #expect(buffer(fader).allSatisfy { $0 == 1 })
    }

    /// The fade sits after the synth, so it silences whatever is playing, even a slam mid-ring.
    @Test func silencesTheSynthMidSound() {
        let synth = DoorSynth(sampleRate: 48_000, seed: 2)
        let fader = OutputFader(sampleRate: 48_000)
        synth.play(.slam)
        var samples = [Float](repeating: 0, count: frames)
        // A slam starts with the air pushed ahead of the leaf: let the hit itself arrive first.
        for _ in 0..<Int(DoorSynth.slamLead * 48_000) / frames + 1 {
            samples.withUnsafeMutableBufferPointer { synth.render(into: $0) }
        }
        var peaks: [Float] = []
        for block in 0..<6 {
            if block == 2 { fader.requestFade() }
            samples.withUnsafeMutableBufferPointer { buffer in
                synth.render(into: buffer)
                fader.apply(to: buffer)
            }
            peaks.append(samples.map(abs).max() ?? 0)
        }
        #expect(peaks[1] > 0.05)
        #expect(peaks[3...].allSatisfy { $0 == 0 })
        #expect(fader.isSilent)
    }
}
