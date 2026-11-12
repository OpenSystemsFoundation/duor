import Foundation
import Synchronization

/// The one-shot sounds a door can make.
nonisolated enum DoorSound: String, CaseIterable, Sendable {
    case knock
    case unlatch
    case latch
    case slam
    case openStop
}

/// How hard a door event is, from the speed it happened at: the one number that sets how a hit
/// sounds. Continuous across the gentle, firm and slam boundaries, so repeated closes never sound
/// stepped.
nonisolated struct DoorStrength: Sendable {
    /// Speed (degrees per second) of a typical firm close: what `play(_:)` uses by default.
    static let nominalSpeed: Float = 150
    /// Speeds above this are treated as this (a hinge can report wild values after a pause).
    static let maximumSpeed: Float = 1_500
    /// The speed range the hardness spans, gentlest to hardest.
    static let softest: Float = 15
    static let hardest: Float = 700

    var speed: Float

    /// 0 (barely moving) ... 1 (as hard as a door gets), on a log scale of speed.
    var hardness: Float {
        let x = logf(max(speed, Self.softest) / Self.softest) / logf(Self.hardest / Self.softest)
        return min(max(x, 0), 1)
    }

    /// Loudness of a latch: a door eased shut is quiet, a firm close full (the 1.0 values were 0.6
    /// and 1 with nothing in between).
    var latchVolume: Float { Self.ramp(speed, from: 20, to: 260, 0.4, 1) }
    /// A slam at the threshold, and harder above it.
    var slamVolume: Float { Self.ramp(speed, from: 260, to: 700, 0.9, 1) }
    var openStopVolume: Float { Self.ramp(speed, from: 0, to: 200, 0, 1) }

    private static func ramp(_ speed: Float, from low: Float, to high: Float, _ start: Float, _ end: Float) -> Float {
        let t = min(max((speed - low) / (high - low), 0), 1)
        return start + (end - start) * t
    }
}

/// Synthesizes every door sound in real time. No samples.
///
/// Thread model: the main thread posts commands into a small locked inbox; the audio thread
/// swaps the inbox out at the start of each buffer and renders. `render(into:)` never allocates.
nonisolated final class DoorSynth: Sendable {
    fileprivate enum Command: Sendable {
        case play(DoorSound, speed: Float)
        case knock(KnockSpot, volume: Float)
        case profile(SoundProfile)
    }

    private struct Inbox: Sendable {
        var commands: [Command]
        var swingAngle: Float = 0
        var swingVelocity: Float = 0
        var speakerVoicing: Bool
    }

    /// Commands past this many per buffer are dropped rather than growing the queue.
    fileprivate static let inboxCapacity = 32

    private let inbox: Mutex<Inbox>
    private let core: Mutex<SynthCore>

    /// - Parameter speakerVoicing: Start voiced for the phone's own speakers (see `SpeakerVoicing`).
    init(
        sampleRate: Float, profile: SoundProfile = .oak, seed: UInt32 = .random(in: 1...UInt32.max),
        speakerVoicing: Bool = false
    ) {
        var commands: [Command] = []
        commands.reserveCapacity(Self.inboxCapacity)
        inbox = Mutex(Inbox(commands: commands, speakerVoicing: speakerVoicing))
        core = Mutex(
            SynthCore(sampleRate: sampleRate, profile: profile, seed: seed, speakerVoicing: speakerVoicing))
    }

    // MARK: Main thread

    /// A door sound made at `speed` (degrees per second, see `DoorStrength`). Knocks have no speed:
    /// `play(.knock)` is a firm knock in the middle.
    func play(_ sound: DoorSound, speed: Float = DoorStrength.nominalSpeed) {
        post(.play(sound, speed: speed.isFinite ? min(max(speed, 0), DoorStrength.maximumSpeed) : 0))
    }

    /// A knock on a particular spot of the door. `play(.knock)` knocks in the middle.
    func knock(at spot: KnockSpot, volume: Float = 1) {
        post(.knock(spot, volume: min(max(volume, 0), 1)))
    }

    /// The hinge angle (degrees) and signed velocity (degrees per second) while the door swings.
    /// Velocity 0 lets the swing sound settle. Positive velocity opens.
    func setSwing(angle: Float, velocity: Float) {
        guard angle.isFinite, velocity.isFinite else { return }
        inbox.withLock {
            $0.swingAngle = angle
            $0.swingVelocity = velocity
        }
    }

    func setProfile(_ profile: SoundProfile) {
        post(.profile(profile))
    }

    /// Voice the output for the phone's own small speakers, or play it flat (headphones, Bluetooth,
    /// AirPlay). Glides, so it can change while a sound rings.
    func setSpeakerVoicing(_ isOn: Bool) {
        inbox.withLock { $0.speakerVoicing = isOn }
    }

    private func post(_ command: Command) {
        inbox.withLock { inbox in
            guard inbox.commands.count < Self.inboxCapacity else { return }
            inbox.commands.append(command)
        }
    }

    // MARK: Audio thread

    /// The loudest the mix has been before the limiter, and the most the limiter has turned it
    /// down, since the last call. For the render tool and tests: this is how gain staging is checked.
    func takeMeter() -> SynthMeter {
        core.withLock { core in
            let meter = core.meter
            core.meter = SynthMeter()
            return meter
        }
    }

    /// Fills `output` with mono samples in -1...1.
    func render(into output: UnsafeMutableBufferPointer<Float>) {
        core.withLock { core in
            // Never wait for the main thread: if it is posting right now, pick its commands up
            // next buffer (a few milliseconds later).
            inbox.withLockIfAvailable { inbox in
                // Both arrays keep their reserved capacity, so the swap never allocates.
                swap(&core.pending, &inbox.commands)
                core.swingAngle = inbox.swingAngle
                core.swingVelocity = inbox.swingVelocity
                core.voicing.isOn = inbox.speakerVoicing
            }
            core.render(into: output)
        }
    }
}

/// What the gain staging did (see `DoorSynth.takeMeter()`).
nonisolated struct SynthMeter: Sendable {
    /// Peak of the mix going into the limiter (1 = 0 dBFS, the limiter's ceiling).
    var mixPeak: Float = 0
    /// Lowest gain the limiter applied (1 = it never worked).
    var limiterGain: Float = 1
}

nonisolated extension DoorSynth {
    /// Overall level of the mix before the limiter. Set so that the loudest single sound of any
    /// door (a slam) reaches the limiter at about its ceiling: single sounds pass clean, and only
    /// stacked ones are turned down.
    static let mixGain: Float = 0.4
    /// The soft clipper after the limiter is a safety net: with the limiter holding the mix at 1
    /// it never gets past tanh(1), which this brings up to just under full scale.
    static let outputGain: Float = 0.98 / 0.761_594_2
}

/// Audio-thread state. Only touched inside `DoorSynth.render(into:)`.
private nonisolated struct SynthCore: Sendable {
    let sampleRate: Float
    var profile: SoundProfile
    var voices = InlineArray<24, ImpactVoice>(repeating: ImpactVoice())
    var creak: CreakVoice
    var bed: SwingBedVoice
    /// The room the door stands in, and the space beyond it that opens up with the door.
    var room: RoomReverb
    var beyond: RoomReverb
    /// How much of the sound goes into each, gliding with the swing angle and the profile.
    var roomGain: Float
    var beyondGain: Float = 0
    /// How far the doorway is open acoustically (0...1), following the swing angle.
    var openness: Float = 0
    var voicing: SpeakerVoicing
    var limiter: PeakLimiter
    /// Output level, gliding to the door's trim.
    var level: Float
    let levelGlide: Float
    var meter = SynthMeter()
    var random: NoiseSource
    var pending: [DoorSynth.Command]
    var swingAngle: Float = 0
    var swingVelocity: Float = 0
    /// Reverb send bus. Fixed size: renders are split into chunks of at most this many frames.
    var send: [Float]
    static let chunkSize = 512
    /// How hard a knock's body is driven into its own soft saturation (0 = clean).
    static let knockDrive: Float = 0.6

    init(sampleRate: Float, profile: SoundProfile, seed: UInt32, speakerVoicing: Bool) {
        self.sampleRate = sampleRate
        self.profile = profile
        random = NoiseSource(seed: seed)
        creak = CreakVoice(profile: profile.creak, sampleRate: sampleRate, seed: seed &* 2_654_435_761)
        bed = SwingBedVoice(profile: profile.bed, hinge: profile.hinge, sampleRate: sampleRate, seed: seed &* 40_503)
        room = RoomReverb(sampleRate: sampleRate, acoustics: profile.space)
        beyond = RoomReverb(sampleRate: sampleRate, acoustics: profile.scene.room)
        roomGain = profile.room
        voicing = SpeakerVoicing(sampleRate: sampleRate, isOn: speakerVoicing)
        limiter = PeakLimiter(sampleRate: sampleRate)
        level = profile.trim * DoorSynth.mixGain
        levelGlide = 1 - expf(-1 / (0.01 * sampleRate))
        pending = []
        pending.reserveCapacity(DoorSynth.inboxCapacity)
        send = [Float](repeating: 0, count: Self.chunkSize)
    }

    mutating func render(into output: UnsafeMutableBufferPointer<Float>) {
        for command in pending {
            handle(command)
        }
        pending.removeAll(keepingCapacity: true)
        creak.setTarget(angle: swingAngle, velocity: swingVelocity)
        bed.setTarget(velocity: swingVelocity)

        var start = 0
        while start < output.count {
            let end = min(start + Self.chunkSize, output.count)
            renderChunk(into: UnsafeMutableBufferPointer(rebasing: output[start..<end]))
            start = end
        }
    }

    private mutating func renderChunk(into output: UnsafeMutableBufferPointer<Float>) {
        output.update(repeating: 0)
        send.withUnsafeMutableBufferPointer { sendBuffer in
            let send = UnsafeMutableBufferPointer(rebasing: sendBuffer[0..<output.count])
            send.update(repeating: 0)
            for index in voices.indices {
                voices[index].render(into: output, send: send)
            }
            bed.render(into: output, send: send)
            creak.render(into: output, send: send)

            // The door's own room, and the space beyond as far as the door is open. Where nothing
            // comes back from beyond, an open door just lets some of the room out.
            let target = SceneAcoustics.openness(angle: swingAngle)
            openness += (target - openness) * (1 - expf(-Float(output.count) / (0.05 * sampleRate)))
            let scene = profile.scene
            let nextRoomGain = profile.room * (1 - min(max(scene.roomLoss, 0), 1) * openness)
            let nextBeyondGain = max(scene.level, 0) * openness
            room.process(send, into: output, gainStart: roomGain, gainEnd: nextRoomGain)
            beyond.process(send, into: output, gainStart: beyondGain, gainEnd: nextBeyondGain)
            roomGain = nextRoomGain
            beyondGain = nextBeyondGain

            // Level for this door, voicing for the phone's speakers (when on), the limiter, and
            // last a soft clipper as a safety net: it only shapes what the limiter lets through.
            let targetLevel = profile.trim * DoorSynth.mixGain
            for frame in output.indices {
                level += (targetLevel - level) * levelGlide
                let mixed = voicing.process(output[frame] * level)
                meter.mixPeak = max(meter.mixPeak, abs(mixed))
                let limited = limiter.process(mixed)
                meter.limiterGain = min(meter.limiterGain, limiter.gain)
                output[frame] = min(max(tanhf(limited) * DoorSynth.outputGain, -0.999), 0.999)
            }
        }
    }

    private mutating func handle(_ command: DoorSynth.Command) {
        switch command {
        case .profile(let newProfile):
            profile = newProfile
            creak.setProfile(newProfile.creak)
            bed.setProfile(newProfile.bed, hinge: newProfile.hinge)
            room.setAcoustics(newProfile.space)
            beyond.setAcoustics(newProfile.scene.room)
        case .knock(let spot, let volume):
            knock(at: spot, volume)
        case .play(let sound, let speed):
            let strength = DoorStrength(speed: speed)
            switch sound {
            case .knock: knock(at: .center, 1)
            case .unlatch: unlatch(1)
            case .latch: latch(strength.latchVolume, hardness: strength.hardness)
            case .slam: slam(strength.slamVolume, hardness: strength.hardness)
            case .openStop: openStop(strength.openStopVolume, hardness: strength.hardness)
            }
        }
    }

    // MARK: Recipes. Each sound is one or more strikes on the door's materials.
    // A door's `character` adds its signature on top: rattling glass, loose boards,
    // a heavy iron bolt, or a soft-close damper.

    /// A knuckle on solid wood: a short, heavily damped "tok" plus the knuckle's own sharp snap.
    /// Mostly dry, so it sounds close and tight rather than boomy.
    ///
    /// Where it lands shapes it (see `KnockSpot`). Every knock also lands a little off target,
    /// with a slightly different knuckle, so even the same spot never sounds the same twice.
    ///
    /// The knock's body is the one sound that is saturated on purpose (`knockDrive`). In 1.0 the
    /// clipper at the end of the chain squashed the top of every knock by 5 dB or more, which is
    /// part of why they sounded so solid. The mix is clean now, so the knock gets a milder version
    /// of that for itself: its first peaks are rounded by about 3 dB, nothing else is touched.
    private mutating func knock(at target: KnockSpot, _ volume: Float) {
        let spot = target.nudged(by: &random)
        var modes = spot.excite(profile.knock)
        for index in modes.indices {
            modes[index].gain *= random.value(in: 0.86...1.14)
        }
        let pitch = random.value(in: 0.97...1.03) * spot.pitchScale
        let touch = profile.knockTouch
        strike(
            ImpactSpec(
                modes: modes, contactTime: random.value(in: touch.contact) * spot.contactScale,
                amplitude: 0.95 * volume, roughness: 0.2, detune: 0.03, pitchScale: pitch,
                decayScale: spot.decayScale, reverbSend: 0.3 + profile.room, contact: profile.contact.knock,
                drive: Self.knockDrive))
        if touch.snapLevel > 0 {
            strike(
                ImpactSpec(
                    modes: modes, contactTime: 0.0002,
                    amplitude: touch.snapLevel * spot.snapScale * random.value(in: 0.7...1.3) * volume,
                    roughness: 0.9, pitchScale: touch.snapPitch * pitch, decayScale: 0.3, reverbSend: 0.15))
        }
        if touch.thump > 0 {
            strike(
                ImpactSpec(
                    modes: profile.frame, contactTime: 0.006, amplitude: touch.thump * spot.thumpScale * volume,
                    roughness: 0.1, decayScale: 0.7, reverbSend: 0.6))
        }
        // Near the handle the bolt ticks in its strike plate.
        let rattle = spot.latchRattle
        if rattle > 0.02 {
            let heavy = profile.character.heavyBolt
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0002, amplitude: 0.09 * rattle * volume,
                    roughness: 0.6, delay: random.value(in: 0.004...0.012),
                    pitchScale: random.value(in: 0.95...1.05) * (heavy ? 0.5 : 1), decayScale: heavy ? 1.5 : 0.5,
                    reverbSend: 0.3, contact: profile.contact.latch))
        }
        // No glass on knocks: the panes only rattle when the door moves.
        clatterBoards(profile.character.looseBoards * 0.4 * volume, after: 0.006, count: 2, hardness: 0.5)
    }

    /// Handle turns, bolt slides out of the strike plate.
    private mutating func unlatch(_ volume: Float) {
        hiss(profile.character.airlockHiss * volume, after: 0.03, duration: 0.5)
        if profile.character.heavyBolt {
            // A big iron bolt dragged back: a low clank, a scrape, a second clank.
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0006, amplitude: 0.5 * volume, pitchScale: 0.5, decayScale: 3,
                    contact: profile.contact.latch))
            strike(
                ImpactSpec(
                    modes: profile.hinge, contactTime: 0.03, amplitude: 0.12 * volume, roughness: 1, delay: 0.02,
                    pitchScale: 0.9, decayScale: 0.5))
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0005, amplitude: 0.4 * volume,
                    delay: random.value(in: 0.07...0.09), pitchScale: 0.45, decayScale: 3,
                    contact: profile.contact.latch))
            return
        }
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0002, amplitude: 0.35 * volume, contact: profile.contact.latch))
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0003, amplitude: 0.25 * volume,
                delay: random.value(in: 0.018...0.03), pitchScale: 0.85, contact: profile.contact.latch))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.002, amplitude: 0.15 * volume, contact: profile.contact.panel))
        rattleGlass(profile.character.glassRattle * 0.12 * volume, after: 0.01, hardness: 0.5)
    }

    /// Door meets the frame, bolt rides the strike plate, then snaps into place.
    private mutating func latch(_ volume: Float, hardness: Float) {
        if profile.character.softClose {
            hiss(profile.character.airlockHiss * 0.8 * volume, after: 0.04, duration: 0.35)
            // The damper takes the speed out; a magnet catches the door.
            // (So the hit itself is softer than the speed says.)
            strike(
                ImpactSpec(
                    modes: profile.frame, contactTime: 0.014, amplitude: 0.5 * volume, roughness: 0.05,
                    contact: profile.contact.frame, hardness: hardness * 0.6))
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.00015, amplitude: 0.35 * volume, delay: 0.02,
                    pitchScale: 1.35, decayScale: 0.5, contact: profile.contact.latch, hardness: hardness))
            return
        }
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.004, amplitude: 0.55 * volume,
                contact: profile.contact.frame, hardness: hardness))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.003, amplitude: 0.35 * volume, contact: profile.contact.panel,
                hardness: hardness))
        let boltPitch: Float = profile.character.heavyBolt ? 0.5 : 1
        let boltDecay: Float = profile.character.heavyBolt ? 3 : 1
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.00025, amplitude: 0.3 * volume, pitchScale: boltPitch,
                decayScale: boltDecay, contact: profile.contact.latch, hardness: hardness))
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0002, amplitude: 0.5 * volume,
                delay: random.value(in: 0.028...0.045) * (profile.character.heavyBolt ? 2 : 1),
                pitchScale: 1.08 * boltPitch, decayScale: boltDecay, contact: profile.contact.latch,
                hardness: hardness))
        rattleGlass(profile.character.glassRattle * 0.4 * volume, after: 0.006, hardness: hardness)
        clatterBoards(profile.character.looseBoards * 0.35 * volume, after: 0.01, count: 2, hardness: hardness)
    }

    /// Heavy hit into the frame, the latch, then the hinges rattling down.
    private mutating func slam(_ volume: Float, hardness: Float) {
        if profile.character.softClose {
            // A soft-close door can't slam: it just closes a little firmer.
            latch(min(volume, 1), hardness: hardness)
            return
        }
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.006, amplitude: volume,
                roughness: 0.5, decayScale: 1.4, contact: profile.contact.frame, hardness: hardness))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.004, amplitude: 0.7 * volume,
                detune: 0.05, decayScale: 1.3, contact: profile.contact.panel, hardness: hardness))
        let heavy = profile.character.heavyBolt
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0002, amplitude: 0.45 * volume, delay: 0.008,
                pitchScale: heavy ? 0.5 : 1, decayScale: heavy ? 3 : 1, contact: profile.contact.latch,
                hardness: hardness))
        var time: Float = 0.03
        var level: Float = 0.25
        for _ in 0..<4 {
            strike(
                ImpactSpec(
                    modes: profile.hinge, contactTime: 0.0004, amplitude: level * volume,
                    delay: time, pitchScale: random.value(in: 0.95...1.05), contact: profile.contact.hinge,
                    hardness: hardness))
            time += random.value(in: 0.02...0.045)
            level *= 0.6
        }
        rattleGlass(profile.character.glassRattle * volume, after: 0.01, hardness: hardness)
        clatterBoards(profile.character.looseBoards * volume, after: 0.015, count: 5, hardness: hardness)
    }

    /// Door swings into a rubber stop: dull thud and a small hinge tick.
    private mutating func openStop(_ volume: Float, hardness: Float) {
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.008, amplitude: 1.6 * volume, roughness: 0.1, decayScale: 0.8,
                contact: profile.contact.stop, hardness: hardness))
        strike(
            ImpactSpec(
                modes: profile.hinge, contactTime: 0.0005, amplitude: 0.12 * volume, delay: 0.035,
                contact: profile.contact.hinge, hardness: hardness))
        rattleGlass(profile.character.glassRattle * 0.3 * volume, after: 0.01, hardness: hardness)
        clatterBoards(profile.character.looseBoards * 0.3 * volume, after: 0.012, count: 2, hardness: hardness)
    }

    /// A pneumatic "pssshh": noise through broad high resonances, swelling and fading.
    private mutating func hiss(_ level: Float, after delay: Float, duration: Float) {
        guard level > 0.001 else { return }
        // A long contact spreads the push thin, so scale up by its length.
        let amplitude = level * duration * sampleRate / 400
        strike(
            ImpactSpec(
                modes: SoundProfile.air, contactTime: duration, amplitude: amplitude, roughness: 1, delay: delay,
                detune: 0.02, reverbSend: 0.4))
    }

    /// Window panes buzzing in their frame: quick, fading glass ticks.
    private mutating func rattleGlass(_ level: Float, after delay: Float, hardness: Float) {
        guard level > 0.001 else { return }
        var time = delay
        var amplitude = level
        for _ in 0..<5 {
            strike(
                ImpactSpec(
                    modes: SoundProfile.glass, contactTime: 0.00015, amplitude: amplitude * 0.5, roughness: 0.6,
                    delay: time, detune: 0.02, pitchScale: random.value(in: 0.97...1.03), reverbSend: 0.5,
                    hardness: hardness))
            time += random.value(in: 0.012...0.03)
            amplitude *= 0.62
        }
    }

    /// Loose planks knocking against each other after a hit.
    private mutating func clatterBoards(_ level: Float, after delay: Float, count: Int, hardness: Float) {
        guard level > 0.001 else { return }
        var time = delay
        var amplitude = level
        for _ in 0..<count {
            strike(
                ImpactSpec(
                    modes: profile.knock, contactTime: 0.0012, amplitude: amplitude * 0.7, roughness: 0.5,
                    delay: time, pitchScale: random.value(in: 1.5...2.2), decayScale: 0.6,
                    contact: profile.contact.panel, hardness: hardness))
            time += random.value(in: 0.025...0.06)
            amplitude *= 0.6
        }
    }

    /// Starts an impact on a free voice, or steals the one closest to finishing.
    private mutating func strike(_ spec: ImpactSpec) {
        var chosen = 0
        var leastRemaining = Int.max
        for index in voices.indices {
            let remaining = voices[index].remaining
            if remaining == 0 {
                chosen = index
                break
            }
            if remaining < leastRemaining {
                leastRemaining = remaining
                chosen = index
            }
        }
        voices[chosen].start(spec, sampleRate: sampleRate, random: &random)
    }
}
