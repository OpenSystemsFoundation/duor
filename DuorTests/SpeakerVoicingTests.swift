import Foundation
import Testing

@testable import Duor

@Suite("SpeakerVoicing")
struct SpeakerVoicingTests {
    let sampleRate: Float = 48_000

    func sine(_ frequency: Float, seconds: Float, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { amplitude * sinf(2 * .pi * frequency * Float($0) / sampleRate) }
    }

    func process(_ input: [Float], isOn: Bool) -> [Float] {
        var voicing = SpeakerVoicing(sampleRate: sampleRate, isOn: isOn)
        return input.map { voicing.process($0) }
    }

    /// Amplitude of one frequency in `samples` (Goertzel), skipping the first `settle` seconds.
    func level(of frequency: Float, in samples: [Float], settle: Float = 0.2) -> Float {
        let part = samples.dropFirst(Int(settle * sampleRate))
        let coefficient = 2 * cosf(2 * .pi * frequency / sampleRate)
        var previous: Float = 0
        var beforePrevious: Float = 0
        for sample in part {
            let current = sample + coefficient * previous - beforePrevious
            beforePrevious = previous
            previous = current
        }
        let power = previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious
        return 2 * power.squareRoot() / Float(part.count)
    }

    /// RMS through a phone-speaker-like band (200 Hz – 6 kHz).
    func phoneLevel(_ samples: [Float]) -> Float {
        var highPass1 = Biquad(.highPass, frequency: 200, q: 0.541, sampleRate: sampleRate)
        var highPass2 = Biquad(.highPass, frequency: 200, q: 1.307, sampleRate: sampleRate)
        var lowPass = Biquad(.lowPass, frequency: 6_000, q: 0.707, sampleRate: sampleRate)
        let heard = samples.map { lowPass.process(highPass2.process(highPass1.process($0))) }
        return (heard.reduce(0) { $0 + $1 * $1 } / Float(heard.count)).squareRoot()
    }

    func render(_ synth: DoorSynth, seconds: Float) -> [Float] {
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

    // MARK: Voicing

    @Test func offPassesTheSignalThroughUntouched() {
        var random = NoiseSource(seed: 3)
        let input = (0..<4_800).map { _ in random.bipolar() * 0.5 }
        #expect(process(input, isOn: false) == input)
    }

    @Test func cutsWhatTheSpeakerCannotPlay() {
        let input = sine(60, seconds: 1)
        let voiced = process(input, isOn: true)
        // At least 20 dB down at 60 Hz.
        #expect(level(of: 60, in: voiced) < level(of: 60, in: input) * 0.1)
    }

    @Test func turnsLowNotesIntoOvertonesTheSpeakerCanPlay() {
        let input = sine(100, seconds: 1)
        let voiced = process(input, isOn: true)
        // A 100 Hz tone has nothing at 200 or 400 Hz; voiced, its octaves carry its pitch.
        #expect(level(of: 200, in: input) < 0.001)
        #expect(level(of: 200, in: voiced) > 0.02)
        #expect(level(of: 400, in: voiced) > 0.01)
    }

    @Test func keepsTheMidrangeAndMakesItLouder() {
        let input = sine(1_000, seconds: 1, amplitude: 0.1)
        let voiced = process(input, isOn: true)
        #expect(level(of: 1_000, in: voiced) > level(of: 1_000, in: input) * 1.3)
    }

    @Test func switchingDoesNotClick() {
        var voicing = SpeakerVoicing(sampleRate: sampleRate, isOn: false)
        let input = sine(440, seconds: 1)
        var output: [Float] = []
        for (index, sample) in input.enumerated() {
            if index == input.count / 3 { voicing.isOn = true }
            if index == input.count * 2 / 3 { voicing.isOn = false }
            output.append(voicing.process(sample))
        }
        // A click is a jump between neighbouring samples bigger than the tone itself makes, flat
        // or voiced (voiced is louder, so its steps are bigger).
        func biggestJump(_ samples: [Float]) -> Float {
            zip(samples.dropFirst(), samples).map { abs($0 - $1) }.max() ?? 0
        }
        let steadyJump = max(biggestJump(input), biggestJump(process(input, isOn: true)))
        #expect(biggestJump(output) < steadyJump * 1.1)
    }

    // MARK: Door sounds

    @Test(arguments: ["oak", "pine", "barn", "castle", "spaceship", "steel"])
    func doorSoundsComeAcrossLouderOnThePhoneSpeaker(_ door: String) {
        let profiles: [String: SoundProfile] = [
            "oak": .oak, "pine": .pine, "barn": .barn, "castle": .castle, "spaceship": .spaceship, "steel": .steel,
        ]
        func sounds(voiced: Bool) -> [Float] {
            let synth = DoorSynth(sampleRate: sampleRate, profile: profiles[door]!, seed: 7, speakerVoicing: voiced)
            synth.play(.knock)
            var samples = render(synth, seconds: 0.8)
            synth.play(.slam)
            // Long enough for the castle's slam, whose ring is heard for longer when voiced.
            samples += render(synth, seconds: 2.4)
            return samples
        }
        let flat = sounds(voiced: false)
        let voiced = sounds(voiced: true)
        #expect(voiced.allSatisfy { $0.isFinite })
        #expect(voiced.allSatisfy { abs($0) < 1 })
        // At least 2 dB louder through a phone-sized speaker.
        #expect(phoneLevel(voiced) > phoneLevel(flat) * 1.26, "\(door)")
        // And it still rings out to silence.
        #expect((voiced.suffix(Int(0.2 * sampleRate)).map(abs).max() ?? 1) < 0.002, "\(door) still ringing")
    }

    @Test func synthFollowsTheRouteWhileSoundRings() {
        let synth = DoorSynth(sampleRate: sampleRate, profile: .oak, seed: 7)
        synth.play(.slam)
        var samples = render(synth, seconds: 0.1)
        synth.setSpeakerVoicing(true)
        samples += render(synth, seconds: 0.5)
        synth.setSpeakerVoicing(false)
        samples += render(synth, seconds: 0.5)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) < 1 })
    }

    // MARK: Route

    @Test func voicesOnlyForTheBuiltInSpeakerUnlessForced() {
        #expect(SpeakerVoicingMode.auto.isOn(builtInSpeaker: true))
        #expect(!SpeakerVoicingMode.auto.isOn(builtInSpeaker: false))
        #expect(SpeakerVoicingMode.on.isOn(builtInSpeaker: false))
        #expect(!SpeakerVoicingMode.off.isOn(builtInSpeaker: true))
    }
}
