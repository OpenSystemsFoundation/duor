import Foundation
import Testing

@testable import Duor

/// The hinge creak (`CreakVoice`): a pin that sticks and slips at the door's tight spots.
/// These pin what the 1.0 creak got wrong: it must not be a tone, must sit under the slam, must
/// stop when the door stops, and must be the same door every swing.
@Suite("Creak")
struct CreakTests {
    private static let sampleRate: Float = 48_000
    private var sampleRate: Float { Self.sampleRate }

    private static let doors: [String: SoundProfile] = [
        "oak": .oak, "cottage": .pine, "barn": .barn, "castle": .castle, "spaceship": .spaceship, "metal": .steel,
    ]

    // MARK: Helpers

    /// One update of the hinge: where it is, how fast it moves, and for how long that holds.
    private struct Step {
        var angle: Float
        var velocity: Float
        var seconds: Float
    }

    /// A constant-speed pass from `from` to `to` degrees, reported `rate` times a second.
    private func pass(from: Float, to: Float, speed: Float, rate: Float = 60) -> [Step] {
        let seconds = abs(to - from) / speed
        let count = max(Int(seconds * rate), 1)
        let velocity = to > from ? speed : -speed
        return (0..<count).map {
            Step(angle: from + (to - from) * Float($0) / Float(count), velocity: velocity, seconds: 1 / rate)
        }
    }

    private func stop(at angle: Float, for seconds: Float = 1) -> [Step] {
        [Step(angle: angle, velocity: 0, seconds: seconds)]
    }

    /// The swing sound on its own, before the room: the creak, and the movement bed when asked.
    private func render(
        _ profile: SoundProfile, _ steps: [Step], withBed: Bool = false, seed: UInt32 = 42,
        voice existing: CreakVoice? = nil
    ) -> (samples: [Float], voice: CreakVoice) {
        var creak = existing ?? CreakVoice(profile: profile.creak, sampleRate: sampleRate, seed: seed)
        var bed = SwingBedVoice(profile: profile.bed, hinge: profile.hinge, sampleRate: sampleRate, seed: seed &+ 1)
        var samples: [Float] = []
        for step in steps {
            var block = [Float](repeating: 0, count: Int(step.seconds * sampleRate))
            var send = block
            creak.setTarget(angle: step.angle, velocity: step.velocity)
            bed.setTarget(velocity: step.velocity)
            block.withUnsafeMutableBufferPointer { output in
                send.withUnsafeMutableBufferPointer { send in
                    // In buffers of 256 frames, as the audio engine asks for them.
                    var start = 0
                    while start < output.count {
                        let end = min(start + 256, output.count)
                        let out = UnsafeMutableBufferPointer(rebasing: output[start..<end])
                        let aux = UnsafeMutableBufferPointer(rebasing: send[start..<end])
                        creak.render(into: out, send: aux)
                        if withBed { bed.render(into: out, send: aux) }
                        start = end
                    }
                }
            }
            samples += block
        }
        return (samples, creak)
    }

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

    private func rms(_ samples: some Collection<Float>) -> Float {
        samples.isEmpty ? 0 : (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    private func decibels(_ value: Float) -> Float { value > 0 ? 20 * log10(value) : -120 }

    /// RMS over the loudest 300 ms.
    private func loudest(_ samples: [Float]) -> Float {
        let window = min(Int(0.3 * sampleRate), samples.count)
        var best: Float = 0
        var sum: Float = 0
        for index in samples.indices {
            sum += samples[index] * samples[index]
            if index >= window { sum -= samples[index - window] * samples[index - window] }
            best = max(best, sum)
        }
        return (best / Float(max(window, 1))).squareRoot()
    }

    /// How tonal the sound is, measured the way `Tools/RenderSounds` does: for every 40 ms window
    /// that is sounding (above -55 dBFS), the highest normalized autocorrelation for pitches
    /// between 80 Hz and 1 kHz. 1 is a pure tone; plain band-limited noise reads about 0.25, with
    /// single windows up to 0.45. Returns the values sorted.
    private func periodicity(_ samples: [Float]) -> [Float] {
        let window = Int(0.04 * sampleRate)
        let minLag = Int(sampleRate / 1_000), maxLag = Int(sampleRate / 80)
        var values: [Float] = []
        samples.withUnsafeBufferPointer { samples in
            var start = 0
            while start + window + maxLag < samples.count {
                var energy: Float = 0
                for index in start..<start + window { energy += samples[index] * samples[index] }
                if (energy / Float(window)).squareRoot() > 0.0018 {
                    var best: Float = 0
                    // Every other lag is plenty at 48 kHz, and keeps the test quick.
                    for lag in stride(from: minLag, through: maxLag, by: 2) {
                        var dot: Float = 0
                        var lagged: Float = 0
                        for index in start..<start + window {
                            dot += samples[index] * samples[index + lag]
                            lagged += samples[index + lag] * samples[index + lag]
                        }
                        best = max(best, dot / max((energy * lagged).squareRoot(), 1e-12))
                    }
                    values.append(best)
                }
                start += window / 2
            }
        }
        return values.sorted()
    }

    /// A pass over the door's first tight spot, long enough to hear it at `speed`.
    private func passOverSpot(_ profile: SoundProfile, speed: Float) -> [Step] {
        let map = profile.creak.friction
        let centre = map.count > 0 ? map.spots[0].angle : 60
        let reach = min(max(speed * 1.2, 14), 60)
        let from = max(centre - reach, 2)
        return pass(from: from, to: min(from + 2 * reach, 170), speed: speed) + stop(at: centre, for: 0.3)
    }

    // MARK: Not a tone

    @Test(arguments: ["oak", "cottage", "barn", "castle"], [5, 15, 40, 90, 150, 300] as [Float])
    func woodCreakIsNotATone(_ door: String, _ speed: Float) {
        // At the shipped level, as `Tools/RenderSounds` measures it: windows under -55 dBFS don't count.
        let profile = Self.doors[door]!
        let values = periodicity(render(profile, passOverSpot(profile, speed: speed), withBed: true).samples)
        // Every wood door is heard at its tight spot from a slow push to a normal swing.
        if (15...150).contains(speed) { #expect(!values.isEmpty, "\(door) at \(speed)°/s is heard") }
        guard let highest = values.last else { return }
        // The 1.0 creak read 0.8 to 0.99 here, with a median of 0.5 to 0.8. Noise reads about 0.25,
        // and that is where the creak sits now. A lone slip is too short for the measure to tell
        // it from a tone every time, so one window in twenty may stray above 0.5; none gets near a tone.
        #expect(values[values.count / 2] < 0.3, "\(door) at \(speed)°/s, median")
        #expect(values[values.count * 9 / 10] < 0.45, "\(door) at \(speed)°/s, 90th percentile")
        #expect(highest < 0.55, "\(door) at \(speed)°/s: \(highest)")
    }

    @Test func woodDoorsDoNotSquealAndMetalDoes() {
        for door in ["oak", "cottage", "barn", "castle"] { #expect(Self.doors[door]!.creak.squeal == 0) }
        #expect(SoundProfile.steel.creak.squeal > 0)
        // Through its tight spot at a slow speed the steel door's slips fall in step with a plate mode.
        let values = periodicity(render(.steel, passOverSpot(.steel, speed: 45)).samples)
        #expect((values.last ?? 0) > 0.7)
    }

    @Test func spaceshipKeepsItsServoHum() {
        #expect(SoundProfile.spaceship.creak.servo != nil)
        var loud = SoundProfile.spaceship
        loud.creak.level *= 8
        let values = periodicity(render(loud, pass(from: 20, to: 80, speed: 60)).samples)
        #expect(!values.isEmpty)
        #expect(values[values.count / 2] > 0.8)
    }

    // MARK: Level

    @Test(arguments: ["oak", "cottage", "barn", "castle", "spaceship", "metal"], [false, true])
    func creakIsWellBelowTheSlam(_ door: String, _ speakerVoicing: Bool) {
        let profile = Self.doors[door]!
        let slamSynth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: 42, speakerVoicing: speakerVoicing)
        slamSynth.play(.slam, speed: 400)
        let slam = loudest(render(slamSynth, seconds: 1.5))
        for seconds: Float in [3, 1, 0.4] {
            let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: 42, speakerVoicing: speakerVoicing)
            var samples: [Float] = []
            let steps = Int(seconds * 60)
            for step in 0..<steps {
                synth.setSwing(angle: 5 + 115 * Float(step) / Float(steps), velocity: 115 / seconds)
                samples += render(synth, seconds: 1 / 60)
            }
            synth.setSwing(angle: 120, velocity: 0)
            samples += render(synth, seconds: 0.5)
            let swing = loudest(samples)
            #expect(swing > 0, "\(door) makes a sound over \(seconds) s")
            #expect(decibels(swing) < decibels(slam) - 6, "\(door) over \(seconds) s")
        }
    }

    @Test(arguments: ["oak", "cottage", "barn", "castle", "metal"])
    func creakIsStrongestAtASlowToMediumSpeed(_ door: String) {
        let profile = Self.doors[door]!
        func level(_ speed: Float) -> Float { loudest(render(profile, pass(from: 5, to: 150, speed: speed)).samples) }
        let medium = max(level(30), level(60))
        #expect(medium > level(250) * 4, "\(door): fades on a fast swing")
        #expect(medium > level(8), "\(door): not loudest when barely moving")
    }

    @Test func slowSlipsAreFewAndStrongFastOnesManyAndWeak() {
        // Peak over RMS: separate strong slips stand far above their average, a rasp doesn't.
        func crest(_ speed: Float) -> Float {
            let samples = render(.barn, pass(from: 60, to: 90, speed: speed)).samples
            return samples.reduce(0) { max($0, abs($1)) } / rms(samples)
        }
        #expect(crest(8) > crest(100) * 1.5)
    }

    // MARK: Rest

    @Test func silentAtRest() {
        let samples = render(.castle, stop(at: 80, for: 0.5)).samples
        #expect(samples.allSatisfy { $0 == 0 })
    }

    @Test(arguments: ["oak", "barn", "spaceship", "metal"])
    func silentWhenStoppedMidSwing(_ door: String) {
        let profile = Self.doors[door]!
        let spot = profile.creak.friction.count > 0 ? profile.creak.friction.spots[0].angle : 60
        let moving = pass(from: spot - 10, to: spot, speed: 40)
        let samples = render(profile, moving + stop(at: spot, for: 2)).samples
        let movingCount = moving.count * Int(sampleRate / 60)
        #expect(rms(samples.prefix(movingCount)) > 0, "\(door) sounds while moving")
        // The last slips and their ring are gone within a second, and then it is exactly silent.
        #expect(samples.suffix(Int(0.8 * sampleRate)).allSatisfy { $0 == 0 }, "\(door)")
    }

    @Test func noTensionIsKeptWhileStopped() {
        // Stop just short of a slip, wait, and creep on: the door must not answer with a bang.
        let spot = SoundProfile.barn.creak.friction.spots[0].angle
        let first = render(.barn, pass(from: spot - 3, to: spot, speed: 20) + stop(at: spot, for: 1.5))
        let creep = render(.barn, [Step(angle: spot, velocity: 4, seconds: 0.05)], voice: first.voice).samples
        #expect(creep.allSatisfy { abs($0) < 0.001 })
    }

    // MARK: Safety and repeatability

    @Test(arguments: ["castle", "spaceship", "metal"])
    func anyHingeInputStaysFiniteAndBounded(_ door: String) {
        var random = NoiseSource(seed: 3)
        var steps: [Step] = []
        for index in 0..<400 {
            var angle = random.value(in: -90...500)
            var velocity = random.value(in: -4_000...4_000)
            switch index % 40 {
            case 7: angle = .nan
            case 13: velocity = .infinity
            case 19: velocity = -.infinity
            case 23: angle = .greatestFiniteMagnitude
            case 29: velocity = .nan
            case 31: velocity = 0
            default: break
            }
            steps.append(Step(angle: angle, velocity: velocity, seconds: random.value(in: 0.001...0.03)))
        }
        let samples = render(Self.doors[door]!, steps + stop(at: 0, for: 0.5), withBed: true).samples
        #expect(samples.allSatisfy { $0.isFinite })
        #expect(samples.reduce(0) { max($0, abs($1)) } < 1)
    }

    @Test func sameSeedAndGestureGiveTheSameSamples() {
        let gesture = pass(from: 5, to: 120, speed: 50) + stop(at: 120, for: 0.3)
        #expect(render(.oak, gesture, seed: 9).samples == render(.oak, gesture, seed: 9).samples)
        #expect(render(.oak, gesture, seed: 9).samples != render(.oak, gesture, seed: 10).samples)
    }

    @Test func creaksAtTheTightSpotsAndTheSameOnesEverySwing() {
        let map = SoundProfile.oak.creak.friction
        let spot = map.spots[0].angle
        // Somewhere well away from both of the oak door's spots.
        let between = (map.spots[0].angle + map.spots[1].angle) / 2
        func level(_ centre: Float, voice: CreakVoice? = nil) -> (Float, CreakVoice) {
            let result = render(.oak, pass(from: centre - 8, to: centre + 8, speed: 40), voice: voice)
            return (rms(result.samples), result.voice)
        }
        let (atSpot, voice) = level(spot)
        #expect(atSpot > level(between).0 * 4)
        // The same stretch again, later on the same door: other slips, about the same loudness.
        var later = voice
        for _ in 0..<3 {
            let (again, next) = level(spot, voice: later)
            #expect(abs(decibels(again) - decibels(atSpot)) < 4)
            later = next
        }
    }

    @Test func closingCreaksALittleDifferently() {
        let spot = SoundProfile.barn.creak.friction.spots[1].angle
        let opening = render(.barn, pass(from: spot - 15, to: spot + 15, speed: 40)).samples
        let closing = render(.barn, pass(from: spot + 15, to: spot - 15, speed: 40)).samples
        #expect(rms(closing) > 0)
        #expect(rms(closing) < rms(opening))
    }

    @Test(arguments: [(20, false), (120, false), (240, false), (60, true)] as [(Float, Bool)])
    func doesNotDependOnHowOftenTheHingeReports(_ rate: Float, _ irregular: Bool) {
        func level(_ steps: [Step]) -> Float { rms(render(.barn, steps + stop(at: 110, for: 0.3)).samples) }
        let reference = level(pass(from: 10, to: 110, speed: 70, rate: 60))
        var steps = pass(from: 10, to: 110, speed: 70, rate: rate)
        if irregular {
            // Uneven gaps between reports, 4 to 90 ms.
            var random = NoiseSource(seed: 77)
            steps = []
            var time: Float = 0
            while time < 100 / 70 {
                let gap = random.value(in: 0.004...0.09)
                steps.append(Step(angle: 10 + 70 * time, velocity: 70, seconds: gap))
                time += gap
            }
        }
        #expect(abs(decibels(level(steps)) - decibels(reference)) < 2.5, "\(rate) Hz, irregular: \(irregular)")
    }

    @Test func aDoorCoastingToRestGivesItsLastSlipsLaterNotAtOnce() {
        // After the hinge reports "stopped", the creak lets go over a moment instead of being cut.
        let spot = SoundProfile.castle.creak.friction.spots[0].angle
        let moving = pass(from: spot - 20, to: spot, speed: 60)
        let samples = render(.castle, moving + stop(at: spot, for: 1)).samples
        let stopped = moving.count * Int(sampleRate / 60)
        #expect(rms(samples[stopped..<stopped + Int(0.08 * sampleRate)]) > 0)
        #expect(rms(samples[(stopped + Int(0.08 * sampleRate))...]) < rms(samples[..<stopped]))
    }
}
