import Foundation
import Testing

@testable import Duor

private let sampleRate: Float = 48_000

private let doors: [String: SoundProfile] = [
    "oak": .oak, "pine": .pine, "barn": .barn, "castle": .castle, "spaceship": .spaceship, "steel": .steel,
]

/// One sound, rendered in hardware-sized blocks, and what the gain staging did.
private func play(
    _ sound: DoorSound, speed: Float = DoorStrength.nominalSpeed, on profile: SoundProfile, seed: UInt32 = 42,
    voiced: Bool = false, seconds: Float = 1.2
) -> (samples: [Float], meter: SynthMeter) {
    let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: seed, speakerVoicing: voiced)
    synth.play(sound, speed: speed)
    var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
    samples.withUnsafeMutableBufferPointer { buffer in
        var start = 0
        while start < buffer.count {
            let end = min(start + 256, buffer.count)
            synth.render(into: UnsafeMutableBufferPointer(rebasing: buffer[start..<end]))
            start = end
        }
    }
    return (samples, synth.takeMeter())
}

private func energy(_ samples: some Collection<Float>) -> Float { samples.reduce(0) { $0 + $1 * $1 } }
private func decibels(_ value: Float) -> Float { value > 0 ? 20 * log10f(value) : -120 }

/// The tool's "on phone" measure (`Tools/RenderSounds`): the RMS of what a phone speaker gets
/// across (200 Hz to 6 kHz) over the loudest 300 ms, in dB.
private func onPhone(_ samples: [Float]) -> Float {
    var highPass1 = Biquad(.highPass, frequency: 200, q: 0.541, sampleRate: sampleRate)
    var highPass2 = Biquad(.highPass, frequency: 200, q: 1.307, sampleRate: sampleRate)
    var lowPass = Biquad(.lowPass, frequency: 6_000, q: 0.707, sampleRate: sampleRate)
    let heard = samples.map { lowPass.process(highPass2.process(highPass1.process($0))) }
    let window = min(Int(0.3 * sampleRate), heard.count)
    var best: Float = 0
    var sum: Float = 0
    for index in heard.indices {
        sum += heard[index] * heard[index]
        if index >= window { sum -= heard[index - window] * heard[index - window] }
        best = max(best, sum)
    }
    return 10 * log10f(max(best / Float(window), 1e-12))
}

/// Where the energy of a sound sits: its spectral centroid in Hz and the shares of its energy in
/// 2 to 5 kHz (where the ear is most sensitive, and a phone speaker loudest) and above 5 kHz.
private struct Spectrum {
    var centroid: Float
    var presence: Float
    var air: Float
}

/// The power spectrum over Hann-windowed frames of `size`, summed up the way the tool does it.
/// Frames overlap by three quarters and start with silence in front, so every sample counts the
/// same: with half-overlapping frames a click counts for up to twice as much in the middle of a
/// frame as between two, and how bright a sound measures depends on when in the render it starts
/// (a slam's hit comes 36 ms after a latch's).
private func spectrum(_ samples: some Collection<Float>, size: Int = 4_096) -> Spectrum {
    let padded = [Float](repeating: 0, count: size * 3 / 4) + samples
    let window = (0..<size).map { 0.5 - 0.5 * cosf(2 * .pi * Float($0) / Float(size)) }
    var weighted: Float = 0
    var total: Float = 0
    var presence: Float = 0
    var air: Float = 0
    var start = 0
    while start + size <= padded.count {
        var real = [Float](repeating: 0, count: size)
        var imaginary = [Float](repeating: 0, count: size)
        for index in 0..<size { real[index] = padded[start + index] * window[index] }
        fft(&real, &imaginary)
        for bin in 1..<size / 2 {
            let power = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
            let frequency = Float(bin) * sampleRate / Float(size)
            weighted += frequency * power
            total += power
            if frequency >= 5_000 { air += power } else if frequency >= 2_000 { presence += power }
        }
        start += size / 4
    }
    guard total > 0 else { return Spectrum(centroid: 0, presence: 0, air: 0) }
    return Spectrum(centroid: weighted / total, presence: presence / total, air: air / total)
}

/// Spectral centroid in Hz, the way the tool measures brightness.
private func centroid(_ samples: [Float]) -> Float { spectrum(samples).centroid }

/// The tool's harshness measure (`make sounds`): the spectrum of the first 200 ms after the onset
/// (the first sample above 5 % of the peak), which is the stretch a listener judges a material by.
private func onset(_ samples: [Float]) -> Spectrum {
    let threshold = samples.reduce(0) { max($0, abs($1)) } * 0.05
    guard let start = samples.firstIndex(where: { abs($0) > threshold }) else {
        return Spectrum(centroid: 0, presence: 0, air: 0)
    }
    return spectrum(samples[start..<min(start + Int(0.2 * sampleRate), samples.count)], size: 1_024)
}

/// In-place radix-2 FFT.
private func fft(_ real: inout [Float], _ imaginary: inout [Float]) {
    let count = real.count
    var j = 0
    for i in 1..<count {
        var bit = count >> 1
        while j & bit != 0 {
            j ^= bit
            bit >>= 1
        }
        j |= bit
        if i < j {
            real.swapAt(i, j)
            imaginary.swapAt(i, j)
        }
    }
    var length = 2
    while length <= count {
        let angle = -2 * Float.pi / Float(length)
        let stepReal = cosf(angle)
        let stepImaginary = sinf(angle)
        for start in stride(from: 0, to: count, by: length) {
            var turnReal: Float = 1
            var turnImaginary: Float = 0
            for k in 0..<length / 2 {
                let a = start + k
                let b = a + length / 2
                let partReal = real[b] * turnReal - imaginary[b] * turnImaginary
                let partImaginary = real[b] * turnImaginary + imaginary[b] * turnReal
                real[b] = real[a] - partReal
                imaginary[b] = imaginary[a] - partImaginary
                real[a] += partReal
                imaginary[a] += partImaginary
                (turnReal, turnImaginary) = (
                    turnReal * stepReal - turnImaginary * stepImaginary,
                    turnReal * stepImaginary + turnImaginary * stepReal
                )
            }
        }
        length <<= 1
    }
}

/// The recipes (`DoorSynth`'s latch, unlatch, slam and open stop): one number, the speed, sets
/// loudness, brightness and timing; the sounds sit where the design puts them against the slam;
/// and each door has its own stop.
@Suite("Recipes")
struct RecipeTests {
    // MARK: How hard

    @Test func strengthIsContinuousAcrossTheBoundaries() {
        var last = DoorStrength(speed: 10)
        for speed in stride(from: Float(12), through: 900, by: 2) {
            let strength = DoorStrength(speed: speed)
            // Nothing steps, and nothing goes back.
            #expect(strength.force >= last.force && strength.force < last.force * 1.03, "\(speed)")
            #expect(strength.hardness >= last.hardness)
            #expect(strength.slamWeight >= last.slamWeight && strength.slamWeight - last.slamWeight < 0.03)
            #expect(strength.overSlam >= last.overSlam)
            #expect(strength.boltDelay <= last.boltDelay)
            #expect(strength.damped.speed >= last.damped.speed && strength.damped.speed <= speed)
            last = strength
        }
        #expect(DoorStrength(speed: DoorStrength.slamSpeed).force == 1)
        #expect(DoorStrength(speed: 90).slamWeight == 0)
        #expect(DoorStrength(speed: 260).slamWeight > 0.2)
        #expect(DoorStrength(speed: 400).slamWeight == 1)
        #expect(DoorStrength(speed: 320).overSlam == 0)
        #expect(DoorStrength(speed: 700).overSlam == 1)
        // The bolt rides the strike plate for a moment when the door is eased shut, and snaps
        // home almost at once when it is thrown.
        #expect(DoorStrength(speed: 40).boltDelay > 0.045)
        #expect(DoorStrength(speed: 250).boltDelay < 0.02)
        // A damper lets a firm close through and takes most of a slam out.
        #expect(DoorStrength(speed: 100).damped.speed == 100)
        #expect(DoorStrength(speed: 600).damped.speed < 200)
    }

    /// The design's check: brightness and loudness both rise steadily with closing speed, with no
    /// jump at the gentle/firm (90°/s) and firm/slam (260°/s) boundaries larger than the recipe
    /// change intends. In 1.0 the slam was half as bright as the firmest latch.
    @Test(arguments: ["oak", "pine", "barn", "castle", "steel"])
    func closingHarderIsLouderAndBrighterAcrossTheBoundaries(_ door: String) {
        let profile = doors[door]!
        let speeds: [Float] = [30, 89, 91, 150, 259, 261, 320, 650]
        var loudness: [Float: Float] = [:]
        var brightness: [Float: Float] = [:]
        for speed in speeds {
            let sound: DoorSound = speed >= DoorStrength.slamSpeed ? .slam : .latch
            // Averaged over a few closes: every hit is a little different (the castle's by a
            // tenth either way in brightness, so it takes six to see a trend).
            let seeds: [UInt32] = [1, 2, 3, 4, 5, 6]
            var level: Float = 0
            var bright: Float = 0
            for seed in seeds {
                let samples = play(sound, speed: speed, on: profile, seed: seed, seconds: 0.6).samples
                level += onPhone(samples)
                bright += centroid(samples)
            }
            loudness[speed] = level / Float(seeds.count)
            brightness[speed] = bright / Float(seeds.count)
        }
        var loudest: Float = -200
        var brightest: Float = 0
        for speed in speeds {
            // Never quieter, and never duller by more than one close differs from the next.
            #expect(loudness[speed]! > loudest - 0.3, "\(door) at \(speed)°/s: \(loudness[speed]!) dB")
            #expect(brightness[speed]! > brightest * 0.93, "\(door) at \(speed)°/s: \(brightness[speed]!) Hz")
            loudest = max(loudest, loudness[speed]!)
            brightest = max(brightest, brightness[speed]!)
        }
        // Gentle to firm is the same recipe: no step at all.
        #expect(abs(loudness[91]! - loudness[89]!) < 0.8)
        #expect(abs(brightness[91]! / brightness[89]! - 1) < 0.08)
        // Firm to slam adds the air ahead of the leaf: a small step up, and the slam is at least
        // as bright as the firmest latch.
        #expect(
            (-0.5...2.5).contains(loudness[261]! - loudness[259]!), "\(door): \(loudness[261]! - loudness[259]!) dB")
        #expect(brightness[261]! > brightness[259]! * 0.95, "\(door)")
        // And over the whole range it is a long way, in both.
        #expect(loudness[650]! > loudness[30]! + 12)
        #expect(loudness[320]! > loudness[150]! + 3)
        #expect(loudness[150]! > loudness[30]! + 5)
        #expect(brightness[150]! > brightness[30]! * 1.2)
        #expect(brightness[320]! > brightness[150]! * 1.05)
        #expect(brightness[650]! > brightness[320]! * 1.05)
    }

    @Test func aSoftCloseDoorClosesFirmerButNeverSlams() {
        let level = { (sound: DoorSound, speed: Float) in
            onPhone(play(sound, speed: speed, on: .spaceship, voiced: true, seconds: 0.7).samples)
        }
        // Up to a firm close it follows the speed like any door.
        #expect(level(.latch, 150) > level(.latch, 50) + 6)
        #expect(level(.latch, 50) > level(.latch, 20) + 3)
        // Above it the damper takes the speed out: a slam is a firm close, a little firmer.
        #expect(abs(level(.slam, 320) - level(.latch, 150)) < 2.5)
        #expect(abs(level(.slam, 700) - level(.slam, 320)) < 2.5)
        // And no slam's rattle or rebound follows: it is over as soon as its seal has hissed.
        let late = { (speed: Float) in
            let samples = play(.slam, speed: speed, on: .spaceship).samples
            return energy(samples[Int(0.6 * sampleRate)...]) / energy(samples)
        }
        #expect(late(600) < 0.01)
    }

    @Test func theBoltSnapsHomeSoonerWhenTheDoorComesInFaster() {
        // The click is the brightest moment of a latch: find it above 3 kHz.
        func click(_ speed: Float) -> Float {
            var highPass = Biquad(.highPass, frequency: 3_000, q: 0.707, sampleRate: sampleRate)
            let bright = play(.latch, speed: speed, on: .oak).samples.map { abs(highPass.process($0)) }
            return Float(bright.firstIndex(of: bright.max()!)!) / sampleRate
        }
        let eased = click(40)
        let firm = click(200)
        #expect(eased > firm + 0.02, "eased \(eased) s, firm \(firm) s")
        #expect(eased < 0.09)
        // The heavy iron bolt takes twice as long.
        var highPass = Biquad(.highPass, frequency: 1_200, q: 0.707, sampleRate: sampleRate)
        let castle = play(.latch, speed: 40, on: .castle).samples.map { abs(highPass.process($0)) }
        #expect(Float(castle.firstIndex(of: castle.max()!)!) / sampleRate > eased + 0.03)
    }

    @Test func anEasedCloseHasMoreScrapeAheadOfItsClick() {
        // Between the leaf landing and the bolt snapping home the bolt rides the strike plate:
        // noise above the leaf's own ring, rising into the click. Measured against the click.
        func scrapeShare(_ speed: Float) -> Float {
            var highPass = Biquad(.highPass, frequency: 2_000, q: 0.707, sampleRate: sampleRate)
            let bright = play(.latch, speed: speed, on: .oak).samples.map { highPass.process($0) }
            let home = Int(DoorStrength(speed: speed).boltDelay * sampleRate)
            // From after the first touch has rung out to just before the click.
            let ride = energy(bright[(home * 2 / 3)..<(home - 48)])
            return ride / energy(bright[home..<(home + Int(0.03 * sampleRate))])
        }
        #expect(scrapeShare(30) > 0)
        #expect(scrapeShare(30) > scrapeShare(150) * 2)
        // It rises: the last third of the ride is louder than the middle third.
        var highPass = Biquad(.highPass, frequency: 2_000, q: 0.707, sampleRate: sampleRate)
        let bright = play(.latch, speed: 30, on: .oak).samples.map { highPass.process($0) }
        let home = Int(DoorStrength(speed: 30).boltDelay * sampleRate)
        #expect(energy(bright[(home * 2 / 3)..<(home - 48)]) > energy(bright[(home / 3)..<(home * 2 / 3)]))
    }

    // MARK: The slam

    @Test(arguments: ["oak", "barn", "castle", "steel"])
    func aSlamPushesAirAheadOfItAndTheHitFollows(_ door: String) {
        let profile = doors[door]!
        let slam = play(.slam, speed: 320, on: profile, seconds: 0.2).samples
        let lead = Int(DoorSynth.slamLead * sampleRate)
        // Air first: something, swelling, and far below the hit that follows.
        let early = energy(slam[..<(lead / 2)])
        let swell = energy(slam[(lead / 2)..<lead])
        let hit = energy(slam[lead..<(lead * 2)])
        #expect(early > 0)
        #expect(swell > early * 2)
        #expect(hit > swell * 10)
        // A latch has none: it starts with the leaf landing.
        let latch = play(.latch, speed: 200, on: profile, seconds: 0.2).samples
        #expect(energy(latch[..<lead]) > energy(latch[lead..<(lead * 2)]) * 0.3)
        // The hit waits for the air, but not long enough to feel late.
        #expect(DoorSynth.slamLead <= 0.04)
    }

    @Test(arguments: ["oak", "pine", "barn", "castle", "steel"])
    func aHardSlamIsMoreThanASlam(_ door: String) {
        let profile = doors[door]!
        // What follows the hit (the rebound, the hardware rattling down, the room) grows with the
        // speed, and so does the whole, though the blow itself hardly does. Measured as a phone
        // speaker gets it across.
        func slam(_ speed: Float) -> (whole: Float, after: Float) {
            var whole: Float = 0
            var after: Float = 0
            for seed: UInt32 in 1...2 {
                let samples = play(.slam, speed: speed, on: profile, seed: seed, seconds: 0.8).samples
                whole += onPhone(samples) / 2
                after += onPhone(Array(samples[Int(0.1 * sampleRate)...])) / 2
            }
            return (whole, after)
        }
        let threshold = slam(265)
        let full = slam(340)
        let hard = slam(680)
        #expect(full.after > threshold.after + 1, "\(door)")
        #expect(hard.after > full.after + 1, "\(door)")
        #expect(hard.whole > full.whole + 1, "\(door)")
    }

    // MARK: Soft on the ear

    /// The design's check after 1.1 was found harsh on a real phone: every sound starts dark.
    /// Over the first 200 ms, flat: a closing door has its energy around 700 Hz or lower with at
    /// most 8 % of it in 2 to 5 kHz (a real door closing is dark, and that band is where a phone
    /// speaker and the ear are both at their most sensitive); an unlatch at most 15 % there, an
    /// open stop 10 %; and next to nothing above 5 kHz (3 %; 6 % where there is glass or a seal).
    /// The hatch on its damper hisses, so it may sit higher, but under 1.5 kHz and 30 %. In 1.1
    /// as first built, the cottage door's slam had 30 % in 2 to 5 kHz and the hatch 62 %.
    @Test(arguments: ["oak", "pine", "barn", "castle", "spaceship", "steel"])
    func everySoundStartsDark(_ door: String) {
        let profile = doors[door]!
        let hatch = profile.character.softClose
        let airLimit: Float = hatch || profile.character.glassRattle > 0 ? 0.06 : 0.03
        // The takes `make sounds` measures, and two more of each.
        for seed: UInt32 in [42, 1, 2] {
            let closes: [(DoorSound, Float)] = [(.latch, 50), (.latch, 150), (.slam, 320)]
            for (sound, speed) in closes {
                let start = onset(play(sound, speed: speed, on: profile, seed: seed).samples)
                // (One slam differs from the next by several percent.)
                #expect(start.centroid < (hatch ? 1_500 : 700) * 1.1, "\(door) \(sound) at \(speed): \(start)")
                #expect(start.presence < (hatch ? 0.3 : 0.08), "\(door) \(sound) at \(speed): \(start)")
                #expect(start.air < airLimit, "\(door) \(sound) at \(speed): \(start)")
            }
            let unlatch = onset(play(.unlatch, speed: 60, on: profile, seed: seed).samples)
            #expect(unlatch.presence < 0.15 && unlatch.air < airLimit, "\(door) unlatch: \(unlatch)")
            let stop = onset(play(.openStop, speed: 120, on: profile, seed: seed).samples)
            #expect(stop.presence < 0.1 && stop.air < airLimit, "\(door) open stop: \(stop)")
            // The hatch's rush of air and its motor stay as low as its closes do.
            if hatch { #expect(unlatch.centroid < 1_500 && stop.centroid < 1_500, "\(unlatch), \(stop)") }
            let knock = onset(play(.knock, on: profile, seed: seed).samples)
            #expect(knock.presence < 0.03 && knock.air < 0.03, "\(door) knock: \(knock)")
        }
        // Even the hardest slam keeps out of the band that stings.
        let hard = onset(play(.slam, speed: 700, on: profile).samples)
        #expect(hard.presence < (hatch ? 0.3 : 0.12), "\(door) hard slam: \(hard)")
        #expect(hard.air < airLimit, "\(door) hard slam: \(hard)")
    }

    // MARK: Levels

    /// The design's loudness targets on the phone measure, voiced, against the door's slam:
    /// knock -4 dB, firm latch -6, open stop -8, gentle latch and unlatch -12, and everything
    /// within 14 dB. A soft-close door has no slam: its firm close is the reference. A door that
    /// slides open by itself is heard mostly as it opens: its unlatch is at -6.
    @Test(arguments: ["oak", "pine", "barn", "castle", "spaceship", "steel"])
    func soundsSitWhereTheDesignPutsThemAgainstTheSlam(_ door: String) {
        let profile = doors[door]!
        func level(_ sound: DoorSound, _ speed: Float) -> Float {
            // The take `make sounds` measures.
            onPhone(play(sound, speed: speed, on: profile, seed: 42, voiced: true, seconds: 0.7).samples)
        }
        let soft = profile.character.softClose
        let reference = soft ? level(.latch, 150) : level(.slam, 320)
        var targets: [(String, Float, Float)] = [
            ("knock", level(.knock, 150), -4), ("open stop", level(.openStop, 120), -8),
            ("gentle latch", level(.latch, 50), -12),
            ("unlatch", level(.unlatch, 60), profile.character.slides ? -6 : -12),
        ]
        if !soft { targets.append(("firm latch", level(.latch, 150), -6)) }
        for (name, measured, target) in targets {
            let relative = measured - reference
            #expect(abs(relative - target) < 3, "\(door) \(name): \(relative) dB against the slam, target \(target)")
            #expect(relative > -14, "\(door) \(name)")
        }
    }

    /// Single sounds reach the limiter at or below its ceiling when played flat, at any closing
    /// speed up to a full slam (just under the slam threshold is where the peak is highest), and
    /// voiced for the phone speaker the limiter shaves at most 4 dB off the first peak.
    @Test(arguments: ["oak", "pine", "barn", "castle", "spaceship", "steel"])
    func singleClosesStayUnderTheCeilingAtEverySpeed(_ door: String) {
        let profile = doors[door]!
        for speed: Float in [200, 259, 261, 320] {
            let sound: DoorSound = speed >= DoorStrength.slamSpeed ? .slam : .latch
            for seed: UInt32 in [1, 21] {
                let flat = play(sound, speed: speed, on: profile, seed: seed, seconds: 0.25).meter
                // At the ceiling, give or take one hit differing from the next.
                #expect(flat.mixPeak < 1.12, "\(door) at \(speed)°/s, seed \(seed): \(flat.mixPeak)")
                let voiced = play(sound, speed: speed, on: profile, seed: seed, voiced: true, seconds: 0.25).meter
                #expect(voiced.limiterGain > 0.63, "\(door) at \(speed)°/s voiced, seed \(seed)")
            }
        }
        // The hardest slam leans on the limiter, flat too, but not much.
        #expect(play(.slam, speed: 700, on: profile, seed: 1, seconds: 0.25).meter.limiterGain > 0.63, "\(door)")
    }

    // MARK: The open stop

    @Test func everyDoorRunsIntoItsOwnStop() {
        // Rubber for the oak and cottage doors, a wooden post for the barn, an iron ring for the
        // castle, an actuator's end stop for the spaceship, a sprung steel stop for the metal door.
        #expect(SoundProfile.oak.stop.bounces == 0 && !SoundProfile.oak.stop.isHardware)
        #expect(SoundProfile.pine.stop.bounces == 0 && !SoundProfile.pine.stop.isHardware)
        #expect(SoundProfile.pine.stop.modes[1].frequency > SoundProfile.oak.stop.modes[1].frequency)
        #expect(SoundProfile.barn.stop.contactTime < SoundProfile.oak.stop.contactTime)
        #expect(SoundProfile.castle.stop.isHardware && SoundProfile.castle.stop.bounces >= 2)
        #expect(SoundProfile.spaceship.stop.windDown > 0)
        #expect(SoundProfile.steel.stop.isHardware && SoundProfile.steel.stop.bounces == 1)
        for (name, profile) in doors where name != "spaceship" { #expect(profile.stop.windDown == 0, "\(name)") }

        // Rubber is dull and gone at once; the ring and the spring are heard ringing.
        let ringing = { (profile: SoundProfile) -> Float in
            var dry = profile
            dry.room = 0
            let samples = play(.openStop, speed: 120, on: dry, seconds: 0.8).samples
            return energy(samples[Int(0.12 * sampleRate)...]) / energy(samples)
        }
        #expect(ringing(.castle) > ringing(.oak) * 3)
        #expect(ringing(.steel) > ringing(.oak) * 3)
        // The spaceship's actuator winds down after the hit: without it the stop is over sooner.
        var noMotor = SoundProfile.spaceship
        noMotor.stop.windDown = 0
        #expect(ringing(.spaceship) > ringing(noMotor) * 2)
        // Hardware stops are of the door's metal.
        #expect(
            SoundProfile.castle.with(metal: .bronze).stop.modes[0].frequency
                < SoundProfile.castle.with(metal: .chrome).stop.modes[0].frequency)
        #expect(
            SoundProfile.oak.with(metal: .bronze).stop.modes[0].frequency == SoundProfile.oak.stop.modes[0].frequency)
    }

    /// The design's finding 9: in 1.0 the open stop was all but inaudible on the phone speaker
    /// (15 dB under the slam, and most of it below 250 Hz). Now each stop has a body the speaker plays.
    @Test(arguments: ["oak", "pine", "barn", "castle", "spaceship", "steel"])
    func theOpenStopHasABodyAPhoneSpeakerPlays(_ door: String) {
        let samples = play(.openStop, speed: 120, on: doors[door]!, seconds: 0.6).samples
        var highPass1 = Biquad(.highPass, frequency: 250, q: 0.541, sampleRate: sampleRate)
        var highPass2 = Biquad(.highPass, frequency: 250, q: 1.307, sampleRate: sampleRate)
        let heard = samples.map { highPass2.process(highPass1.process($0)) }
        #expect(energy(heard) > energy(samples) * 0.3, "\(door): \(energy(heard) / energy(samples))")
        // And harder is louder.
        #expect(
            onPhone(play(.openStop, speed: 300, on: doors[door]!, seconds: 0.6).samples)
                > onPhone(play(.openStop, speed: 60, on: doors[door]!, seconds: 0.6).samples) + 3)
    }

    // MARK: The wood doors next to each other

    /// The share of a sound's energy under `frequency` (a fourth-order low-pass).
    private func share(below frequency: Float, of samples: [Float]) -> Float {
        var first = Biquad(.lowPass, frequency: frequency, q: 0.541, sampleRate: sampleRate)
        var second = Biquad(.lowPass, frequency: frequency, q: 1.307, sampleRate: sampleRate)
        return energy(samples.map { second.process(first.process($0)) }) / energy(samples)
    }

    /// Oak is an ordinary house door: the barn and castle doors are the deep ones. Their slams and
    /// knocks carry more of their energy under 200 Hz, and more of it outright, and ring longer.
    @Test func barnAndCastleAreDeeperThanOak() {
        for seed: UInt32 in [42, 1, 2] {
            let oak = play(.slam, speed: 320, on: .oak, seed: seed, seconds: 2).samples
            let oakKnock = play(.knock, on: .oak, seed: seed, seconds: 1).samples
            for (name, profile) in [("barn", SoundProfile.barn), ("castle", .castle)] {
                let slam = play(.slam, speed: 320, on: profile, seed: seed, seconds: 2).samples
                #expect(share(below: 200, of: slam) > share(below: 200, of: oak) * 1.15, "\(name) slam, share")
                #expect(
                    energy(slam) * share(below: 200, of: slam) > energy(oak) * share(below: 200, of: oak),
                    "\(name) slam, energy")
                let knock = play(.knock, on: profile, seed: seed, seconds: 1).samples
                #expect(
                    share(below: 200, of: knock) > share(below: 200, of: oakKnock) * 1.2, "\(name) knock, share")
                // And the oak door is done sooner: less of its slam is left after a third of a second.
                let late = Int(0.35 * sampleRate)
                #expect(energy(slam[late...]) / energy(slam) > 3 * energy(oak[late...]) / energy(oak), "\(name) ring")
            }
            // The castle door is the deepest of all.
            let barn = play(.slam, speed: 320, on: .barn, seed: seed, seconds: 2).samples
            let castle = play(.slam, speed: 320, on: .castle, seed: seed, seconds: 2).samples
            #expect(spectrum(castle).centroid < spectrum(barn).centroid)
            #expect(spectrum(barn).centroid < spectrum(oak).centroid * 0.85)
        }
    }

    /// The cottage door is the quiet one: its knock, latch and slam are each under the same sound
    /// of the oak, barn and castle doors, flat and on the phone's speakers, and all of its sounds
    /// together sit 3 dB or more under theirs (less when voiced, where the limiter holds the
    /// louder doors back).
    @Test func cottageIsTheQuietestWoodDoor() {
        let others: [(String, SoundProfile)] = [("oak", .oak), ("barn", .barn), ("castle", .castle)]
        let sounds: [(DoorSound, Float)] = [(.knock, 150), (.latch, 150), (.slam, 320), (.openStop, 150)]
        func level(_ samples: [Float]) -> Float { 10 * log10f(energy(samples) / Float(samples.count)) }
        for voiced in [false, true] {
            var cottageTotal: Float = 0
            var totals = [Float](repeating: 0, count: others.count)
            for (sound, speed) in sounds {
                let cottage = play(sound, speed: speed, on: .pine, voiced: voiced, seconds: 1.5).samples
                cottageTotal += energy(cottage)
                for (index, other) in others.enumerated() {
                    let samples = play(sound, speed: speed, on: other.1, voiced: voiced, seconds: 1.5).samples
                    totals[index] += energy(samples)
                    // (Not the stops: those are different things, a rubber bumper, a post and a ring.)
                    guard sound != .openStop else { continue }
                    #expect(
                        (voiced ? onPhone(cottage) : level(cottage)) < (voiced ? onPhone(samples) : level(samples)),
                        "\(sound) against \(other.0), voiced \(voiced)")
                }
            }
            for (index, other) in others.enumerated() {
                let under = 10 * log10f(totals[index] / cottageTotal)
                #expect(under > (voiced ? 1.5 : 3), "\(other.0), voiced \(voiced): \(under) dB")
                // Quiet, not faint: it stays well within reach of the others.
                #expect(under < 8, "\(other.0), voiced \(voiced): \(under) dB")
            }
        }
    }

    // MARK: Knocks and metals

    @Test func fistAndKnuckleKeepTheirCharacters() {
        // Oak is knocked with a fist (soft, warm, no snap), the cottage door with a knuckle (crisp).
        let fist = play(.knock, on: .oak, seconds: 0.6).samples
        let knuckle = play(.knock, on: .pine, seconds: 0.6).samples
        #expect(centroid(knuckle) > centroid(fist) * 1.25)
        var snap = Biquad(.highPass, frequency: 2_500, q: 0.707, sampleRate: sampleRate)
        let fistSnap = energy(fist.map { snap.process($0) }) / energy(fist)
        snap = Biquad(.highPass, frequency: 2_500, q: 0.707, sampleRate: sampleRate)
        let knuckleSnap = energy(knuckle.map { snap.process($0) }) / energy(knuckle)
        #expect(knuckleSnap > fistSnap * 3)
        // Both pass the limiter untouched when played flat, and are no more than shaved when voiced.
        for profile in [SoundProfile.oak, .pine, .castle, .steel] {
            #expect(play(.knock, on: profile, seconds: 0.4).meter.limiterGain == 1)
            #expect(play(.knock, on: profile, voiced: true, seconds: 0.4).meter.limiterGain > 0.8)
        }
    }

    @Test func everyMetalClicksItsOwnWay() {
        let metals: [(String, MetalTone)] = [
            ("iron", .iron), ("brass", .brass), ("chrome", .chrome), ("copper", .copper), ("bronze", .bronze),
        ]
        // The bolt on its strike plate, alone: how bright it is, and how long it rings.
        func click(_ tone: MetalTone) -> (bright: Float, ring: Float) {
            let profile = SoundProfile.oak.with(metal: tone)
            var voice = ImpactVoice()
            var random = NoiseSource(seed: 5)
            voice.start(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0002, amplitude: 1, detune: 0, contact: profile.contact.latch),
                sampleRate: sampleRate, random: &random)
            var output = [Float](repeating: 0, count: Int(0.3 * sampleRate))
            var send = output
            output.withUnsafeMutableBufferPointer { out in
                send.withUnsafeMutableBufferPointer { voice.render(into: out, send: $0) }
            }
            let peak = output.reduce(0) { max($0, abs($1)) }
            let last = output.lastIndex { abs($0) > peak * 0.03 } ?? 0
            return (centroid(output), Float(last) / sampleRate)
        }
        let clicks = metals.map { ($0.0, click($0.1)) }
        for (index, first) in clicks.enumerated() {
            for second in clicks[(index + 1)...] {
                // Apart in pitch or in ring by enough to hear.
                let pitch = abs(log2f(first.1.bright / second.1.bright))
                let ring = abs(log2f(first.1.ring / second.1.ring))
                #expect(pitch > 0.1 || ring > 0.35, "\(first.0) and \(second.0): \(first.1), \(second.1)")
            }
        }
        let named = Dictionary(uniqueKeysWithValues: clicks)
        #expect(named["chrome"]!.bright > named["iron"]!.bright)
        #expect(named["iron"]!.bright > named["brass"]!.bright)
        #expect(named["brass"]!.bright > named["bronze"]!.bright)
        #expect(named["brass"]!.ring > named["iron"]!.ring)
        #expect(named["bronze"]!.ring > named["copper"]!.ring * 1.3)
        // And every door stays clean with every metal: under the ceiling, and silent again.
        // (The two doors whose stop is hardware. The castle's room is also the longest.)
        for (name, profile) in doors where ["castle", "steel"].contains(name) {
            for (metal, tone) in metals {
                for sound in [DoorSound.latch, .openStop] {
                    let played = play(sound, on: profile.with(metal: tone), seconds: 3.5)
                    #expect(played.samples.allSatisfy { $0.isFinite })
                    #expect(played.meter.mixPeak < 1.12, "\(name) \(metal) \(sound): \(played.meter.mixPeak)")
                    let tail = played.samples.suffix(Int(0.3 * sampleRate)).reduce(0) { max($0, abs($1)) }
                    #expect(tail < 0.002, "\(name) \(metal) \(sound) still ringing")
                }
            }
        }
    }
}

/// The spaceship's door: a powered panel that slides (`SoundCharacter.slides`), with a motor
/// (`SweepVoice`) and a chime.
@Suite("Sliding door")
struct SlidingDoorTests {
    /// The door without its room, and with only some of its layers.
    private func hatch(air: Bool = true, motor: Bool = true, chime: Bool = true) -> SoundProfile {
        var profile = SoundProfile.spaceship
        profile.room = 0
        if !air { profile.character.airlockHiss = 0 }
        if !motor { profile.character.motor = 0 }
        if !chime { profile.character.chime = 0 }
        return profile
    }

    /// Pitch in Hz from the zero crossings of a stretch of a tone.
    private func pitch(_ samples: ArraySlice<Float>) -> Float {
        var lowPass = Biquad(.lowPass, frequency: 900, q: 0.707, sampleRate: sampleRate)
        var highPass = Biquad(.highPass, frequency: 150, q: 0.707, sampleRate: sampleRate)
        let smooth = samples.map { highPass.process(lowPass.process($0)) }
        var crossings = 0
        for index in 1..<smooth.count where (smooth[index - 1] < 0) != (smooth[index] < 0) { crossings += 1 }
        return Float(crossings) * sampleRate / Float(2 * smooth.count)
    }

    private func slice(_ samples: [Float], _ from: Float, _ to: Float) -> ArraySlice<Float> {
        samples[Int(from * sampleRate)..<Int(to * sampleRate)]
    }

    @Test func onlyTheSpaceshipSlides() {
        for (name, profile) in doors {
            let character = profile.character
            #expect(character.slides == (name == "spaceship"), "\(name)")
            #expect((character.motor > 0) == (name == "spaceship"), "\(name)")
            #expect((character.chime > 0) == (name == "spaceship"), "\(name)")
        }
    }

    @Test func everySoundIsBoundedAndOverSoon() {
        let sounds: [(DoorSound, Float)] = [
            (.knock, 150), (.unlatch, 60), (.latch, 20), (.latch, 150), (.slam, 320), (.slam, 1_500),
            (.openStop, 40), (.openStop, 400),
        ]
        for (sound, speed) in sounds {
            for voiced in [false, true] {
                let played = play(sound, speed: speed, on: .spaceship, seed: 7, voiced: voiced, seconds: 2)
                #expect(played.samples.allSatisfy { $0.isFinite && abs($0) < 0.999 }, "\(sound) at \(speed)")
                #expect(played.meter.mixPeak < 1.12, "\(sound) at \(speed): \(played.meter.mixPeak)")
                // Decaying: next to nothing is left after 0.7 s, and silence after 1.5 s.
                let late = energy(played.samples[Int(0.7 * sampleRate)...]) / energy(played.samples)
                #expect(late < 0.001, "\(sound) at \(speed): \(late)")
                #expect(played.samples.suffix(Int(0.5 * sampleRate)).allSatisfy { abs($0) < 1e-4 })
            }
        }
        // The same take twice is the same samples.
        #expect(
            play(.unlatch, on: .spaceship, seed: 9).samples == play(.unlatch, on: .spaceship, seed: 9).samples)
    }

    /// The opening is one gesture of about half a second, not a click: still sounding at 0.3 s,
    /// over by 0.6 s, with nothing in it that jumps out (its peak, the locks, is within 18 dB of its
    /// level; a click on its own would be 30 dB over).
    @Test func theOpeningIsAWhooshOfHalfASecond() {
        for seed: UInt32 in [42, 1, 2] {
            let samples = play(.unlatch, on: hatch(), seed: seed).samples
            let whole = energy(samples)
            #expect(energy(slice(samples, 0.2, 0.4)) > whole * 0.25, "seed \(seed)")
            #expect(energy(samples[Int(0.6 * sampleRate)...]) < whole * 0.001, "seed \(seed)")
            let peak = samples.reduce(0) { max($0, abs($1)) }
            let level = (energy(slice(samples, 0, 0.4)) / (0.4 * sampleRate)).squareRoot()
            #expect(peak < level * 8, "seed \(seed): crest \(peak / level)")
        }
    }

    @Test func theOpeningRisesInItsAirAndItsMotor() {
        // The motor alone runs up: 230 Hz toward 540.
        let motor = play(.unlatch, on: hatch(air: false, chime: false)).samples
        let early = pitch(slice(motor, 0.06, 0.1))
        let late = pitch(slice(motor, 0.25, 0.35))
        #expect(late > early * 1.25, "\(early) Hz, then \(late) Hz")
        #expect((200...420).contains(early) && (430...600).contains(late), "\(early) Hz, then \(late) Hz")
        // The air alone: the panel on its track rises (after the seal's falling "pssht").
        for seed: UInt32 in [42, 1, 2] {
            let air = play(.unlatch, on: hatch(motor: false, chime: false), seed: seed).samples
            let slow = centroid(Array(slice(air, 0.12, 0.17)))
            let fast = centroid(Array(slice(air, 0.2, 0.26)))
            #expect(fast > slow * 1.1, "seed \(seed): \(slow) Hz, then \(fast) Hz")
            // And it is louder where the panel is fastest than where it sets off.
            #expect(energy(slice(air, 0.18, 0.24)) > energy(slice(air, 0.09, 0.15)) * 2)
        }
    }

    @Test func theClosingFallsAndLandsSoonerWhenItComesInFaster() {
        // The motor alone runs down through the thud.
        let motor = play(.latch, speed: 150, on: hatch(air: false, chime: false))
        var body = motor.samples
        // (Take the thud out of the way: it is over in 0.1 s, the motor is not.)
        let early = pitch(slice(body, 0.0, 0.03))
        let late = pitch(slice(body, 0.16, 0.22))
        #expect(early > late * 1.3, "\(early) Hz, then \(late) Hz")
        // The thud: the loudest moment, sooner for a harder close.
        func landing(_ speed: Float) -> Float {
            body = play(.latch, speed: speed, on: hatch(motor: false, chime: false)).samples
            let peak = body.reduce(0) { max($0, abs($1)) }
            return Float(body.firstIndex { abs($0) == peak }!) / sampleRate
        }
        let eased = landing(25)
        let firm = landing(150)
        #expect(eased > firm + 0.015, "eased \(eased) s, firm \(firm) s")
        #expect(eased < 0.12 && firm < 0.07)
    }

    @Test func theMotorWindsDownAtTheEndStop() {
        let samples = play(.openStop, speed: 120, on: hatch(air: false)).samples
        let early = pitch(slice(samples, 0.06, 0.1))
        let late = pitch(slice(samples, 0.24, 0.32))
        #expect(early > late * 1.25, "\(early) Hz, then \(late) Hz")
    }

    /// The chime is a field of the profile: at 0 there is none, and nothing else changes.
    @Test func theChimeIsQuietAndCanBeTurnedOff() {
        for sound in [DoorSound.unlatch, .latch] {
            let with = play(sound, on: hatch()).samples
            let without = play(sound, on: hatch(chime: false)).samples
            let chime = zip(with, without).map { $0 - $1 }
            #expect(energy(chime) > 0, "\(sound)")
            // Subtle: at least 10 dB under the rest of the sound.
            #expect(energy(chime) < energy(without) * 0.1, "\(sound): \(energy(chime) / energy(without))")
            // Two notes, 587 and 880 Hz: nearly all of it is under 1.5 kHz. (The rest is what the
            // soft clipper at the end of the chain makes of two sounds at once.)
            var highPass = Biquad(.highPass, frequency: 1_500, q: 0.707, sampleRate: sampleRate)
            let above = energy(chime.map { highPass.process($0) }) / energy(chime)
            #expect(above < 0.15, "\(sound): \(above)")
        }
    }
}

/// `SweepVoice`: a tone that glides.
@Suite("Sweeps")
struct SweepTests {
    private func play(_ spec: SweepSpec, seconds: Float = 1, then next: SweepSpec? = nil, at: Float = 0) -> [Float] {
        var voice = SweepVoice()
        voice.start(spec, sampleRate: sampleRate)
        var output = [Float](repeating: 0, count: Int(seconds * sampleRate))
        var send = output
        let split = Int(at * sampleRate)
        output.withUnsafeMutableBufferPointer { out in
            send.withUnsafeMutableBufferPointer { send in
                if let next {
                    voice.render(
                        into: UnsafeMutableBufferPointer(rebasing: out[..<split]),
                        send: UnsafeMutableBufferPointer(rebasing: send[..<split]))
                    voice.start(next, sampleRate: sampleRate)
                }
                var start = next == nil ? 0 : split
                while start < out.count {
                    let end = min(start + 256, out.count)
                    voice.render(
                        into: UnsafeMutableBufferPointer(rebasing: out[start..<end]),
                        send: UnsafeMutableBufferPointer(rebasing: send[start..<end]))
                    start = end
                }
            }
        }
        return output
    }

    private func crossings(_ samples: ArraySlice<Float>) -> Int {
        var count = 0
        for index in (samples.startIndex + 1)..<samples.endIndex
        where (samples[index - 1] < 0) != (samples[index] < 0) { count += 1 }
        return count
    }

    private func largestStep(_ samples: [Float]) -> Float {
        var step: Float = 0
        for index in 1..<samples.count { step = max(step, abs(samples[index] - samples[index - 1])) }
        return step
    }

    @Test func aSweepGlidesFadesInAndOutAndEndsOnTime() {
        let spec = SweepSpec(from: 200, to: 800, duration: 0.4, amplitude: 0.5, harmonics: 0)
        let samples = play(spec)
        let end = Int(0.4 * sampleRate)
        // Its pitch: 200 Hz at the start, 800 at the end, and 400 half way (an even glide).
        let tenth = Int(0.02 * sampleRate)
        #expect((6...10).contains(crossings(samples[..<tenth])))
        #expect((14...18).contains(crossings(samples[(end / 2 - tenth / 2)..<(end / 2 + tenth / 2)])))
        #expect((27...33).contains(crossings(samples[(end - tenth)..<end])))
        // Never louder than asked, in and out without a step, and nothing after its time.
        #expect(samples.allSatisfy { abs($0) <= 0.5 })
        #expect(samples.reduce(0) { max($0, abs($1)) } > 0.45)
        #expect(abs(samples[0]) < 0.001 && abs(samples[end - 1]) < 0.001)
        #expect(samples[end...].allSatisfy { $0 == 0 })
        // The same twice.
        #expect(play(spec) == samples)
        // Settling: most of the way early on.
        var settling = spec
        settling.settle = 1
        let settled = play(settling)
        #expect(crossings(settled[(end / 2 - tenth / 2)..<(end / 2 + tenth / 2)]) > 24)
    }

    @Test func overtonesAndThrobStayInBounds() {
        let samples = play(SweepSpec(from: 300, to: 300, duration: 0.3, amplitude: 1, harmonics: 0.3, throb: 0.5))
        #expect(samples.allSatisfy { abs($0) <= 1 + 0.3 + 0.09 })
        // The throb: the level dips 31 times a second.
        let window = Int(sampleRate / SweepVoice.throbRate)
        let from = Int(0.1 * sampleRate)
        let levels = (0..<(window / 48)).map { energy(samples[(from + $0 * 48)..<(from + $0 * 48 + 160)]) }
        #expect(levels.max()! > levels.min()! * 1.5)
    }

    @Test func aStolenSweepFadesInsteadOfClicking() {
        let first = SweepSpec(from: 500, to: 500, duration: 0.5, amplitude: 0.8, harmonics: 0)
        let second = SweepSpec(from: 300, to: 300, duration: 0.2, amplitude: 0.1, harmonics: 0)
        let alone = largestStep(play(first))
        let stolen = play(first, then: second, at: 0.1003)
        // No step larger than the tone's own from one sample to the next.
        #expect(largestStep(stolen) < alone * 1.3, "\(largestStep(stolen)) against \(alone)")
        #expect(stolen.allSatisfy { abs($0) <= 0.9 })
    }

    @Test func nonsenseStaysFiniteAndBounded() {
        let wild: [Float] = [.nan, .infinity, -.infinity, -1, 0, 1e-9, 0.5, 3, 1e9]
        var random = NoiseSource(seed: 23)
        func pick() -> Float { wild[Int(random.nextUInt() % UInt32(wild.count))] }
        for _ in 0..<80 {
            let spec = SweepSpec(
                from: pick(), to: pick(), duration: pick(), amplitude: pick(), attack: pick(), release: pick(),
                delay: pick(), harmonics: pick(), throb: pick(), settle: pick(), reverbSend: pick())
            let samples = play(spec, seconds: 4.5)
            #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 12 })
            // Never longer than the longest tone after the longest wait.
            #expect(samples.suffix(Int(0.4 * sampleRate)).allSatisfy { $0 == 0 })
        }
    }
}

/// The parts of `ImpactVoice` the recipes are built from beyond a plain hit: noise that swells,
/// glides, or rings what it scrapes.
@Suite("Scrapes and swells")
struct ScrapeTests {
    private func play(_ spec: ImpactSpec, seconds: Float = 0.5) -> [Float] {
        var voice = ImpactVoice()
        var random = NoiseSource(seed: 3)
        voice.start(spec, sampleRate: sampleRate, random: &random)
        var output = [Float](repeating: 0, count: Int(seconds * sampleRate))
        var send = output
        output.withUnsafeMutableBufferPointer { out in
            send.withUnsafeMutableBufferPointer { voice.render(into: out, send: $0) }
        }
        return output
    }

    @Test func aSwellRisesToItsEndAndStopsThere() {
        let length = Int(0.04 * sampleRate)
        let swell = play(
            .noise(ContactNoise(level: 0.3, frequency: 600, q: 0.8, duration: 0.04, swell: 1), amplitude: 1))
        let hit = play(.noise(ContactNoise(level: 0.3, frequency: 600, q: 0.8, duration: 0.04), amplitude: 1))
        #expect(energy(swell[(length * 3 / 4)..<length]) > energy(swell[..<(length / 4)]) * 20)
        #expect(energy(hit[..<(length / 4)]) > energy(hit[(length * 3 / 4)..<length]) * 20)
        // Over when its time is up, without a step at either end.
        #expect(swell[(length + 1)...].allSatisfy { $0 == 0 })
        #expect(abs(swell[0]) < 0.01 && abs(swell[length - 1]) < 0.05)
    }

    @Test func aGlidingBandRisesOrFalls() {
        func halves(_ glide: Float) -> (first: Float, second: Float) {
            let samples = play(
                .noise(
                    ContactNoise(level: 0.3, frequency: 1_000, q: 4, duration: 0.2, swell: 0.5, glide: glide),
                    amplitude: 1))
            let half = Int(0.1 * sampleRate)
            return (centroid(Array(samples[..<half])), centroid(Array(samples[half..<(2 * half)])))
        }
        let rising = halves(3)
        let falling = halves(0.33)
        let steady = halves(1)
        #expect(rising.second > rising.first * 1.4)
        #expect(falling.second < falling.first * 0.7)
        #expect(abs(steady.second / steady.first - 1) < 0.15)
    }

    @Test func aScrapeRingsWhatItScrapes() {
        let scrape = ContactNoise(level: 0, frequency: 2_500, q: 1.5, duration: 0.03, swell: 1, ring: 0.5)
        let ringing = play(ImpactSpec(modes: SoundProfile.oak.latch, contactTime: 0, amplitude: 1, contact: scrape))
        let end = Int(0.03 * sampleRate)
        // Heard through the bolt's modes only, at about the level asked for, and it rings on a
        // moment after the scrape ends.
        let loudest = (energy(ringing[(end * 3 / 4)..<end]) / Float(end / 4)).squareRoot()
        #expect((0.1...1.5).contains(loudest), "\(loudest)")
        #expect(energy(ringing[(end + 48)...]) > 0)
        #expect(ringing.suffix(4_800).allSatisfy { abs($0) < 1e-4 })
        // Without a blow nothing else sounds: no noise, no ring, nothing at all.
        let nothing = play(ImpactSpec(modes: SoundProfile.oak.latch, contactTime: 0, amplitude: 1))
        #expect(nothing.allSatisfy { $0 == 0 })
        // With a blow as well, the hit is there as before.
        let hit = play(ImpactSpec(modes: SoundProfile.oak.latch, contactTime: 0.0002, amplitude: 1))
        #expect(energy(hit[..<end]) > 0)
    }

    @Test func nonsenseStaysFiniteAndBounded() {
        let wild: [Float] = [.nan, .infinity, -.infinity, -1, 0, 1e-9, 0.5, 3, 1e9]
        var random = NoiseSource(seed: 17)
        func pick() -> Float { wild[Int(random.nextUInt() % UInt32(wild.count))] }
        for _ in 0..<60 {
            let noise = ContactNoise(
                level: min(abs(pick()), 4), frequency: pick(), q: pick(), duration: pick(), swell: pick(),
                glide: pick(),
                ring: min(abs(pick()), 4))
            let samples = play(
                ImpactSpec(
                    modes: SoundProfile.oak.latch, contactTime: [0, 0.0002, 0.01, pick()][Int(random.nextUInt() % 4)],
                    amplitude: 1, contact: noise, hardness: pick(), drive: pick()),
                seconds: 1)
            #expect(samples.allSatisfy { $0.isFinite })
            #expect(samples.reduce(0) { max($0, abs($1)) } < 200)
        }
    }
}
