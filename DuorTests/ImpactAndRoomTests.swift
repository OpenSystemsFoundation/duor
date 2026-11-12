import Foundation
import Testing

@testable import Duor

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

private func peak(_ samples: some Collection<Float>) -> Float { samples.reduce(0) { max($0, abs($1)) } }
private func energy(_ samples: some Collection<Float>) -> Float { samples.reduce(0) { $0 + $1 * $1 } }
private func largestStep(_ samples: [Float]) -> Float {
    zip(samples.dropFirst(), samples).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

/// How bright a sound is: its power-weighted RMS frequency in Hz, from the energy of its
/// sample-to-sample differences. Like the spectral centroid, it rises when energy moves up.
private func brightness(_ samples: [Float]) -> Float {
    let total = energy(samples)
    guard total > 0 else { return 0 }
    let changes = zip(samples.dropFirst(), samples).reduce(Float(0)) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
    return (changes / total).squareRoot() * sampleRate / (2 * .pi)
}

private let doors: [String: SoundProfile] = [
    "oak": .oak, "pine": .pine, "barn": .barn, "castle": .castle, "spaceship": .spaceship, "steel": .steel,
]

// MARK: - Gain staging

@Suite("Gain staging")
struct GainStagingTests {
    @Test func limiterHoldsTheCeilingAndLeavesQuietSoundAlone() {
        var limiter = PeakLimiter(sampleRate: sampleRate, ceiling: 1)
        var random = NoiseSource(seed: 5)
        // Quiet: out is in, a lookahead later.
        let quiet = (0..<2_000).map { _ in random.bipolar() * 0.5 }
        let passed = quiet.map { limiter.process($0) }
        #expect(Array(passed[limiter.lookahead...]) == Array(quiet[..<(quiet.count - limiter.lookahead)]))
        // Loud, with sudden jumps: never over the ceiling.
        var loudest: Float = 0
        for index in 0..<48_000 {
            let burst: Float = (index / 3_000) % 2 == 0 ? 12 : 0.2
            loudest = max(loudest, abs(limiter.process(random.bipolar() * burst)))
        }
        #expect(loudest <= 1.0001)
        // And it lets go again: within half a second a quiet signal is back to itself.
        for _ in 0..<24_000 { _ = limiter.process(0.1) }
        #expect(abs(limiter.process(0.1) - 0.1) < 0.001)
        #expect(limiter.gain > 0.99)
    }

    @Test func limiterSurvivesNonsense() {
        var limiter = PeakLimiter(sampleRate: sampleRate)
        for value: Float in [.nan, .infinity, -.infinity, 1e30, -1e30, 0, 0.5] {
            for _ in 0..<300 {
                let output = limiter.process(value)
                #expect(output.isFinite && abs(output) <= 1.0001)
            }
        }
    }

    /// The design's check: a single sound reaches the clipper at or below 0 dBFS, so the clipper
    /// no longer shapes it. Played flat the mix gets there by itself (the limiter has nothing to
    /// do); voiced for the phone speaker the limiter may shave the first peak of the loudest hits.
    @Test(arguments: ["oak", "pine", "barn", "castle", "spaceship", "steel"])
    func singleSoundsReachTheClipperBelowFullScale(_ door: String) {
        // What the clipper puts out for an input of exactly full scale.
        let fullScale = tanhf(1) * DoorSynth.outputGain
        for voiced in [false, true] {
            for sound in DoorSound.allCases {
                for speed: Float in sound == .slam ? [320, 700] : [150] {
                    let synth = DoorSynth(
                        sampleRate: sampleRate, profile: doors[door]!, seed: 21, speakerVoicing: voiced)
                    synth.play(sound, speed: speed)
                    let samples = render(synth, seconds: 0.5)
                    let meter = synth.takeMeter()
                    #expect(peak(samples) <= fullScale + 0.0001, "\(door) \(sound) \(speed)")
                    // A slam far above the slam threshold may lean on the limiter harder.
                    guard speed <= 320 else { continue }
                    if voiced {
                        // At most 4 dB of limiting on the peak.
                        #expect(meter.limiterGain > 0.63, "\(door) \(sound) \(speed) voiced")
                    } else {
                        // At the ceiling (give or take half a dB from one hit to the next) before
                        // the limiter.
                        #expect(meter.mixPeak < 1.06, "\(door) \(sound) \(speed)")
                        #expect(meter.limiterGain > 0.94, "\(door) \(sound) \(speed)")
                    }
                }
            }
        }
    }

    /// Stacked sounds are turned down as a whole, without clicks: no jump between neighbouring
    /// samples bigger than a loud door sound makes by itself.
    @Test func twoHundredCommandsAtOnceDoNotClick() {
        let synth = DoorSynth(sampleRate: sampleRate, seed: 11)
        synth.play(.slam)
        _ = render(synth, seconds: 0.03)
        for _ in 0..<200 { synth.play(.slam, speed: 600) }
        var samples = render(synth, seconds: 0.2)
        for _ in 0..<200 { synth.knock(at: .center) }
        samples += render(synth, seconds: 0.8)
        #expect(samples.allSatisfy { $0.isFinite })
        #expect(peak(samples) < 1)
        #expect(largestStep(samples) < 0.5)
        #expect(synth.takeMeter().limiterGain < 0.5)
    }

    @Test func doorsAreLevelled() {
        // Knock, unlatch, open stop, slam: the loudness of every door within 6 dB of the others.
        var levels: [Float] = []
        for (_, profile) in doors {
            let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: 9)
            var samples: [Float] = []
            for sound in [DoorSound.knock, .knock, .unlatch, .openStop, .slam] {
                synth.play(sound, speed: sound == .slam ? 320 : 120)
                samples += render(synth, seconds: 1.2)
            }
            levels.append(10 * log10f(energy(samples) / Float(samples.count)))
        }
        #expect(levels.max()! - levels.min()! < 6)
    }

    @Test func changingTheDoorWhileItRingsDoesNotClick() {
        let synth = DoorSynth(sampleRate: sampleRate, profile: .castle, seed: 4)
        synth.play(.slam)
        let before = render(synth, seconds: 0.25)
        synth.setProfile(.spaceship)
        let after = render(synth, seconds: 0.5)
        #expect(after.allSatisfy { $0.isFinite })
        // The ring is fading, so nothing after the change should jump more than it did before.
        #expect(largestStep([before.last!] + after) <= largestStep(before))
    }
}

// MARK: - Impacts

@Suite("Impacts")
struct ImpactTests {
    private func play(_ spec: ImpactSpec, seconds: Float = 0.5, seed: UInt32 = 3) -> [Float] {
        var voice = ImpactVoice()
        var random = NoiseSource(seed: seed)
        voice.start(spec, sampleRate: sampleRate, random: &random)
        return ring(&voice, seconds: seconds)
    }

    private func ring(_ voice: inout ImpactVoice, seconds: Float) -> [Float] {
        var output = [Float](repeating: 0, count: Int(seconds * sampleRate))
        var send = output
        output.withUnsafeMutableBufferPointer { out in
            send.withUnsafeMutableBufferPointer { voice.render(into: out, send: $0) }
        }
        return output
    }

    @Test func modeSetsUseAllEightLanes() {
        for (name, profile) in doors {
            for set in [profile.panel, profile.knock, profile.frame, profile.latch, profile.hinge] {
                #expect(set.count == 8)
                for index in set.indices {
                    #expect(set[index].gain > 0 && set[index].frequency > 20 && set[index].decay > 0, "\(name)")
                }
            }
        }
        // Metal parts have close pairs that beat: two modes within 4% of each other.
        func closePairs(_ set: ModeSet) -> Int {
            (1..<set.count).count { set[$0].frequency / set[$0 - 1].frequency < 1.04 }
        }
        #expect(closePairs(SoundProfile.oak.latch) == 2)
        #expect(closePairs(SoundProfile.oak.hinge) == 2)
        #expect(closePairs(SoundProfile.glass) == 2)
        #expect(closePairs(SoundProfile.steel.panel) == 2)
        #expect(closePairs(SoundProfile.spaceship.panel) == 2)
        #expect(closePairs(SoundProfile.oak.panel) == 0)
    }

    @Test func contactNoiseIsAShortBurstOnTopOfTheRing() {
        let silentModes = SoundProfile.oak.panel.scaled(pitch: 1, gain: 0)
        let burst = ContactNoise(level: 0.3, frequency: 1_500, q: 0.9, duration: 0.006)
        let noise = play(ImpactSpec(modes: silentModes, contactTime: 0.002, amplitude: 1, contact: burst))
        let end = Int(0.006 * sampleRate)
        #expect(peak(noise[..<end]) > 0.1)
        #expect(peak(noise[(end + 1)...]) == 0)
        // No step at its start, and about the level asked for at its loudest.
        #expect(abs(noise[0]) < 0.05)
        let loudest = (energy(noise[..<(end / 4)]) / Float(end / 4)).squareRoot()
        #expect((0.1...0.4).contains(loudest))
        // No contact noise: just the ring, as before.
        let ring = play(ImpactSpec(modes: silentModes, contactTime: 0.002, amplitude: 1))
        #expect(peak(ring) == 0)
        // A rubber stop is longer and duller than a steel bolt.
        let stop = play(ImpactSpec(modes: silentModes, contactTime: 0.002, amplitude: 1, contact: ContactSet().stop))
        let bolt = play(ImpactSpec(modes: silentModes, contactTime: 0.002, amplitude: 1, contact: ContactSet().latch))
        #expect(brightness(stop) < brightness(bolt) / 3)
        #expect(stop.lastIndex { $0 != 0 }! > 3 * bolt.lastIndex { $0 != 0 }!)
    }

    @Test func harderHitsAreBrighterAndNoQuieter() {
        let contact = ContactSet()
        let parts: [(ModeSet, Float, ContactNoise)] = [
            (SoundProfile.oak.panel, 0.003, contact.panel), (SoundProfile.oak.frame, 0.004, contact.frame),
            (SoundProfile.oak.latch, 0.00025, contact.latch), (SoundProfile.steel.panel, 0.003, contact.panel),
        ]
        for (modes, contactTime, noise) in parts {
            var last: (brightness: Float, energy: Float) = (0, 0)
            for hardness: Float in [0, 0.25, 0.5, 0.75, 1] {
                let hit = play(
                    ImpactSpec(
                        modes: modes, contactTime: contactTime, amplitude: 1, detune: 0, contact: noise,
                        hardness: hardness))
                #expect(brightness(hit) > last.brightness * 1.02, "\(modes[0].frequency) Hz at \(hardness)")
                #expect(energy(hit) > last.energy, "\(modes[0].frequency) Hz at \(hardness)")
                last = (brightness(hit), energy(hit))
            }
        }
    }

    /// The design's check: brightness and loudness both rise steadily with closing speed, inside
    /// the latch (below 260°/s) and inside the slam (above).
    @Test(arguments: ["oak", "pine", "barn", "castle", "steel"])
    func closingFasterIsLouderAndBrighter(_ door: String) {
        func close(_ sound: DoorSound, _ speed: Float) -> [Float] {
            // Averaged over a few closes: every hit is a little different.
            var all: [Float] = []
            for seed: UInt32 in 1...3 {
                let synth = DoorSynth(sampleRate: sampleRate, profile: doors[door]!, seed: seed)
                synth.play(sound, speed: speed)
                all += render(synth, seconds: 1)
            }
            return all
        }
        for (sound, speeds) in [(DoorSound.latch, [25, 70, 150, 255] as [Float]), (.slam, [265, 420, 650])] {
            var last: (brightness: Float, energy: Float) = (0, 0)
            for speed in speeds {
                let samples = close(sound, speed)
                #expect(brightness(samples) > last.brightness, "\(door) \(sound) at \(speed)")
                #expect(energy(samples) > last.energy, "\(door) \(sound) at \(speed)")
                last = (brightness(samples), energy(samples))
            }
        }
    }

    /// A voice that is stolen while it rings fades out over 2 ms under the new hit instead of
    /// stopping dead, which would click.
    @Test func stolenVoiceFadesInsteadOfClicking() {
        var low = SoundProfile.oak.panel.scaled(pitch: 1, gain: 0)
        low[0] = ModeSpec(100, 0.5, 1)
        var voice = ImpactVoice()
        var random = NoiseSource(seed: 2)
        voice.start(
            ImpactSpec(modes: low, contactTime: 0.001, amplitude: 1, detune: 0), sampleRate: sampleRate, random: &random
        )
        // Stop at a crest of the 100 Hz ring.
        var ringing = ring(&voice, seconds: 0.0225)
        #expect(abs(ringing.last!) > 0.5)
        // Steal it for a hit that makes no sound itself.
        voice.start(ImpactSpec(modes: low, contactTime: 0.001, amplitude: 0), sampleRate: sampleRate, random: &random)
        let fade = ring(&voice, seconds: 0.01)
        ringing += fade
        // A 100 Hz ring at full level moves about 0.013 per sample; a dead stop would be 0.5 or more.
        #expect(largestStep(ringing) < 0.03)
        let fadeLength = Int(ImpactVoice.stealFade * sampleRate)
        #expect(abs(fade[fadeLength / 2]) > 0.1)
        #expect(peak(fade[fadeLength...]) == 0)
    }

    @Test func knockDriveRoundsThePeakNotTheTail() {
        let clean = play(ImpactSpec(modes: SoundProfile.oak.knock, contactTime: 0.002, amplitude: 1, detune: 0))
        let driven = play(
            ImpactSpec(modes: SoundProfile.oak.knock, contactTime: 0.002, amplitude: 1, detune: 0, drive: 0.6))
        #expect(peak(driven) < peak(clean) * 0.9)
        #expect(peak(driven) > peak(clean) * 0.5)
        // Quiet parts pass almost untouched.
        let late = Int(0.06 * sampleRate)
        #expect(abs(energy(driven[late...]) / energy(clean[late...]) - 1) < 0.05)
    }
}

// MARK: - Rooms

@Suite("Rooms")
struct RoomTests {
    /// A click through the room.
    private func response(
        _ acoustics: RoomAcoustics, seconds: Float = 5, input: (Int) -> Float = { $0 == 0 ? 1 : 0 }
    )
        -> [Float]
    {
        var room = RoomReverb(sampleRate: sampleRate, acoustics: acoustics)
        return run(&room, seconds: seconds, input: input)
    }

    private func run(_ room: inout RoomReverb, seconds: Float, input: (Int) -> Float) -> [Float] {
        let count = Int(seconds * sampleRate)
        var source = (0..<count).map(input)
        var output = [Float](repeating: 0, count: count)
        source.withUnsafeMutableBufferPointer { source in
            output.withUnsafeMutableBufferPointer { output in
                var start = 0
                while start < count {
                    let end = min(start + 256, count)
                    room.process(
                        UnsafeMutableBufferPointer(rebasing: source[start..<end]),
                        into: UnsafeMutableBufferPointer(rebasing: output[start..<end]))
                    start = end
                }
            }
        }
        return output
    }

    /// Seconds to fall 60 dB, from the -15 to -45 dB stretch of the Schroeder curve of the lows.
    private func decayTime(_ samples: [Float]) -> Float {
        var lowPass = Biquad(.lowPass, frequency: 1_000, q: 0.707, sampleRate: sampleRate)
        let lows = samples.map { Double(lowPass.process($0)) }
        let total = lows.reduce(0) { $0 + $1 * $1 }
        var remaining = total
        var start = 0
        for (index, sample) in lows.enumerated() {
            remaining -= sample * sample
            let level = 10 * log10(max(remaining / total, 1e-15))
            if start == 0, level <= -15 { start = index }
            if level <= -45 { return Float(index - start) / sampleRate * 2 }
        }
        return .infinity
    }

    /// The design's check: each door's room decays as long as it should, the castle's clearly longest.
    @Test func everyDoorHasItsOwnRoom() {
        var times: [String: Float] = [:]
        for (name, profile) in doors {
            let measured = decayTime(response(profile.space))
            #expect(abs(measured / profile.space.decay - 1) < 0.15, "\(name): \(measured) s")
            times[name] = measured
        }
        // Oak: a carpeted hallway of about 0.4 s. Castle: a stone hall of about 1.8 s. Metal: a
        // concrete stairwell of about 1.2 s. Cottage: smallest and driest.
        #expect(abs(times["oak"]! - 0.4) < 0.08)
        #expect(abs(times["castle"]! - 1.8) < 0.25)
        #expect(abs(times["steel"]! - 1.2) < 0.2)
        #expect(times["pine"]! == times.values.min()!)
        let others = times.filter { $0.key != "castle" }.values.max()!
        #expect(times["castle"]! > others * 1.3)
        // The same is heard through the synth: the castle's slam rings on longest.
        func tail(_ profile: SoundProfile) -> Float {
            let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: 5)
            synth.play(.knock)
            let samples = render(synth, seconds: 2)
            return energy(samples[Int(0.8 * sampleRate)...]) / energy(samples)
        }
        for (name, profile) in doors where name != "castle" {
            #expect(tail(.castle) > tail(profile) * 4, "\(name)")
        }
    }

    @Test func tailLevelDoesNotDependOnSizeOrDecay() {
        // `tail` sets the energy of the tail against the click that made it, whatever the room.
        for (size, decay) in [(Float(0.5), Float(0.3)), (1, 0.8), (2.7, 1.8), (2, 0.5)] {
            let room = RoomAcoustics(size: size, decay: decay, damping: 0.1, diffusion: 0.5, tail: 1)
            let total = energy(response(room))
            #expect((0.5...2).contains(total), "size \(size), decay \(decay): \(total)")
        }
    }

    @Test func highsDieSoonerInADampedRoom() {
        func bright(_ damping: Float) -> Float {
            let late = response(RoomAcoustics(size: 1, decay: 1, damping: damping))[Int(0.3 * sampleRate)...]
            return brightness(Array(late))
        }
        #expect(bright(0.7) < bright(0.1) * 0.7)
    }

    @Test func earlyReflectionsArriveOnTime() {
        var room = RoomAcoustics(size: 1, decay: 0.3, damping: 0.5, preDelay: 0.05, tail: 1)
        room.early[0] = Reflection(0.01, 0.5)
        room.early[1] = Reflection(0.02, -0.25)
        let click = response(room, seconds: 0.5)
        #expect(click[Int(0.01 * sampleRate)] == 0.5)
        #expect(click[Int(0.02 * sampleRate)] == -0.25)
        // Nothing else before the pre-delay is over.
        let quiet = click[..<Int(0.05 * sampleRate)].enumerated().filter { $0.element != 0 }.map(\.offset)
        #expect(quiet == [Int(0.01 * sampleRate), Int(0.02 * sampleRate)])
        #expect(peak(click[Int(0.05 * sampleRate)...]) > 0.001)
    }

    /// The design's check: stable and finite whatever goes in, for any parameters.
    @Test func staysFiniteForAnyInputAndAnyRoom() {
        var random = NoiseSource(seed: 31)
        let wild: [Float] = [.nan, .infinity, -.infinity, -1e9, -1, 0, 1e-30, 0.5, 1, 7, 1e9]
        func pick() -> Float { wild[Int(random.nextUInt() % UInt32(wild.count))] }
        for _ in 0..<24 {
            var acoustics = RoomAcoustics(
                size: pick(), decay: pick(), damping: pick(), diffusion: pick(), preDelay: pick(), tail: pick())
            for index in acoustics.early.indices { acoustics.early[index] = Reflection(pick(), pick()) }
            let output = response(acoustics, seconds: 0.5) { index in
                switch index % 977 {
                case 0: Float.nan
                case 1: Float.infinity
                case 2: -1e30
                default: random.bipolar() * 4
                }
            }
            #expect(output.allSatisfy { $0.isFinite })
            // 4 in, clamped feedback below 1, early taps of at most 2 each: far below this.
            #expect(peak(output) < 1_000)
        }
        // Loud noise for a long time in a long room never builds up.
        let long = response(RoomAcoustics(size: 3, decay: 20, damping: 0, tail: 1), seconds: 8) { _ in
            random.bipolar()
        }
        #expect(long.allSatisfy { $0.isFinite })
        #expect(peak(long) < 20)
    }

    @Test func fallsSilentAndSleeps() {
        for (name, profile) in doors {
            let output = response(profile.space, seconds: profile.space.decay * 2.2 + 1.5)
            #expect(output.suffix(Int(0.5 * sampleRate)).allSatisfy { $0 == 0 }, "\(name)")
        }
    }

    @Test func changingTheRoomDoesNotClick() {
        var room = RoomReverb(sampleRate: sampleRate, acoustics: .stoneHall)
        let tone = { (index: Int) -> Float in 0.5 * sinf(2 * .pi * 220 * Float(index) / sampleRate) }
        var output = run(&room, seconds: 1, input: tone)
        let steady = largestStep(Array(output.suffix(4_800)))
        room.setAcoustics(.airlock)
        output += run(&room, seconds: 0.5) { tone($0 + 48_000) }
        room.setAcoustics(.hallway)
        output += run(&room, seconds: 0.5) { tone($0 + 72_000) }
        #expect(output.allSatisfy { $0.isFinite })
        // A click would be a jump far bigger than the tone makes in any of the rooms.
        #expect(largestStep(output) < steady * 3)
        // And it did change: the hallway is quieter than the hall for a steady tone.
        #expect(energy(output.suffix(4_800)) < energy(output[43_200..<48_000]))
    }

    // MARK: Beyond the door

    private func openStop(onto scene: SceneAcoustics, angle: Float) -> [Float] {
        var profile = SoundProfile.oak
        profile.scene = scene
        let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: 6)
        synth.setSwing(angle: angle, velocity: 0)
        _ = render(synth, seconds: 0.5)
        synth.play(.openStop)
        return render(synth, seconds: 3)
    }

    @Test func aShutDoorHidesWhatIsBehindIt() {
        let hall = openStop(onto: .greatHall, angle: 0)
        #expect(hall == openStop(onto: .beach, angle: 0))
        #expect(hall == openStop(onto: .brickWall, angle: 0))
    }

    @Test func theSceneIsHeardThroughTheOpenDoor() {
        let late = { (samples: [Float]) in energy(samples[Int(0.5 * sampleRate)...]) }
        let early = { (samples: [Float]) in energy(samples[..<Int(0.05 * sampleRate)]) }
        let hall = openStop(onto: .greatHall, angle: 120)
        let living = openStop(onto: .livingRoom, angle: 120)
        let beach = openStop(onto: .beach, angle: 120)
        let wall = openStop(onto: .brickWall, angle: 120)
        let shut = openStop(onto: .beach, angle: 0)
        // A great hall rings on long after everything else is gone.
        #expect(late(hall) > late(living) * 10)
        #expect(late(hall) > late(shut) * 10)
        // Outdoors there is less room than behind a shut door, and nothing comes back.
        #expect(energy(beach) < energy(shut))
        #expect(energy(beach) < energy(living))
        // A brick wall slaps straight back.
        #expect(early(wall) > early(beach) * 1.05)
        // Every scene is its own space.
        let scenes: [SceneAcoustics] = [.livingRoom, .greatHall, .beach, .forest, .space, .brickWall]
        for (index, scene) in scenes.enumerated() {
            let sound = openStop(onto: scene, angle: 120)
            #expect(sound.allSatisfy { $0.isFinite })
            for other in scenes[(index + 1)...] { #expect(sound != openStop(onto: other, angle: 120)) }
        }
    }

    @Test func theDoorwayOpensWithTheAngle() {
        #expect(SceneAcoustics.openness(angle: 0) == 0)
        #expect(SceneAcoustics.openness(angle: -20) == 0)
        #expect(SceneAcoustics.openness(angle: 90) == 1)
        #expect(SceneAcoustics.openness(angle: 180) == 1)
        // Most of the way open by 45°.
        #expect(SceneAcoustics.openness(angle: 45) > 0.7)
        var last: Float = -1
        for angle in stride(from: Float(0), through: 90, by: 5) {
            #expect(SceneAcoustics.openness(angle: angle) > last)
            last = SceneAcoustics.openness(angle: angle)
        }
    }
}
