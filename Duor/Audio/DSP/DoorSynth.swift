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
/// sounds. Loudness (`force`), brightness and contact time (`hardness`) and timing (`boltDelay`)
/// all come from it, and all are continuous across the gentle, firm and slam boundaries, so
/// repeated closes never sound stepped.
nonisolated struct DoorStrength: Sendable {
    /// Speed (degrees per second) of a typical firm close: what `play(_:)` uses by default.
    static let nominalSpeed: Float = 150
    /// Speeds above this are treated as this (a hinge can report wild values after a pause).
    static let maximumSpeed: Float = 1_500
    /// The speed range the hardness spans, gentlest to hardest.
    static let softest: Float = 15
    static let hardest: Float = 700
    /// Where a close turns into a slam (`DoorMotionInterpreter.Configuration.slamSpeed`): `force`
    /// is 1 here.
    static let slamSpeed: Float = 260

    var speed: Float

    /// 0 (barely moving) ... 1 (as hard as a door gets), on a log scale of speed.
    var hardness: Float {
        let x = logf(max(speed, Self.softest) / Self.softest) / logf(Self.hardest / Self.softest)
        return min(max(x, 0), 1)
    }

    /// How loud the hit is (amplitude), 1 at the slam threshold. Below it loudness follows speed
    /// closely: an eased close is about 12 dB under a slam, a firm one 6. Above it the hit itself
    /// only grows a little, because a door can't hit much harder than hard; a harder slam is more
    /// in what follows it (see `overSlam`).
    var force: Float {
        let relative = min(max(speed, Self.softest), Self.hardest) / Self.slamSpeed
        return powf(relative, relative < 1 ? Self.forceExponent : 0.1)
    }
    static let forceExponent: Float = 0.16

    /// How much of a slam this close is, 0 (a latch) ... 1 (a full slam). It comes in over a
    /// stretch of speed around the threshold instead of at it: the frame is hit heavier, the leaf
    /// bounces back, the hardware starts to rattle.
    var slamWeight: Float { Self.smoothstep((speed - 190) / 170) }

    /// How far past a plain slam, 0 ... 1: more rebound and a longer rattle.
    var overSlam: Float { Self.smoothstep((speed - 340) / 360) }

    /// Seconds between the leaf meeting its stop and the bolt snapping home: the bolt rides up the
    /// strike plate in that time, so it is long when the door is eased shut and short when it is
    /// thrown.
    var boltDelay: Float {
        let ease = 1 - hardness
        return 0.009 + 0.08 * ease * ease
    }

    /// The same event with a damper in the way (a soft-close door): above a firm close the extra
    /// speed is mostly taken out.
    var damped: DoorStrength {
        let knee: Float = 150
        return DoorStrength(speed: speed <= knee ? speed : knee * powf(speed / knee, 0.15))
    }

    private static func smoothstep(_ value: Float) -> Float {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
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
    /// How hard a full slam overloads the ring of the frame and leaf (see `ImpactSpec.drive`): the
    /// weight of a slam without the peak.
    static let slamDrive: Float = 0.7
    /// The hit of a slam comes this long after the event, behind the swell of air pushed ahead of
    /// the leaf. Short: long enough to hear the air, not long enough for the hit to feel late.
    static let slamLead: Float = 0.036
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
    /// Level of the leaf's edge knocking on its stop in a full slam, next to the blow.
    static let edgeKnock: Float = 0.28

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
            case .unlatch: unlatch()
            case .latch: close(strength, slam: false)
            case .slam: close(strength, slam: true)
            case .openStop: openStop(strength)
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
        let volume = volume * profile.levels.knock
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
                    modes: profile.latch, contactTime: 0.0004, amplitude: 0.09 * rattle * volume,
                    roughness: 0.6, delay: random.value(in: 0.004...0.012),
                    pitchScale: random.value(in: 0.95...1.05) * (heavy ? 0.5 : 1), decayScale: heavy ? 1.5 : 0.5,
                    reverbSend: 0.3, contact: profile.contact.latch))
        }
        // No glass on knocks: the panes only rattle when the door moves.
        clatterBoards(profile.character.looseBoards * 0.4 * volume, after: 0.006, count: 2, hardness: 0.5)
    }

    /// Handle and spindle turn (two soft spring ticks), the bolt draws back out of the strike
    /// plate (a short scrape and a click), and the leaf lets go of its stop: low and quiet.
    /// The handle turns at the same pace however the door then swings, so this has no speed.
    private mutating func unlatch() {
        let volume = profile.levels.unlatch
        let character = profile.character
        hiss(character.airlockHiss * volume, after: 0.03, duration: 0.5)
        let released: Float
        if character.heavyBolt {
            // A big iron bolt dragged back: a low clank, a scrape, a second clank.
            released = random.value(in: 0.07...0.09)
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0006, amplitude: 0.5 * volume, pitchScale: 0.5, decayScale: 3,
                    contact: profile.contact.latch))
            strike(
                ImpactSpec(
                    modes: profile.hinge, contactTime: 0, amplitude: 0.3 * volume, delay: 0.012, pitchScale: 0.9,
                    decayScale: 0.5,
                    contact: ContactNoise(
                        level: 0.05, frequency: profile.contact.latch.frequency * 0.5, q: 1.4,
                        duration: released - 0.012, swell: 0.6, glide: 0.7, ring: 0.5)))
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0005, amplitude: 0.4 * volume, delay: released,
                    pitchScale: 0.45, decayScale: 3, contact: profile.contact.latch))
        } else {
            // Two soft ticks of the handle's spring and spindle taking up their play.
            let second = random.value(in: 0.02...0.03)
            released = second + random.value(in: 0.028...0.04)
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0007, amplitude: 0.1 * volume, roughness: 0.5,
                    pitchScale: 0.78, decayScale: 0.5, reverbSend: 0.6,
                    contact: profile.contact.latch.scaled(level: 0.5), hardness: 0.25))
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0006, amplitude: 0.13 * volume, roughness: 0.5,
                    delay: second, pitchScale: 0.88, decayScale: 0.5, reverbSend: 0.6,
                    contact: profile.contact.latch.scaled(level: 0.5), hardness: 0.3))
            // The bolt sliding back against its spring, which lets up as it goes: a falling scrape.
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0, amplitude: 0.22 * volume, delay: second, decayScale: 0.5,
                    reverbSend: 0.6,
                    contact: ContactNoise(
                        level: 0.04, frequency: profile.contact.latch.frequency * 0.7, q: 1.6,
                        duration: released - second, swell: 0.8, glide: 0.6, ring: 0.45)))
            // Clear of the plate.
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0003, amplitude: 0.3 * volume, delay: released,
                    contact: profile.contact.latch, hardness: 0.45))
        }
        // Under the click, the door it is mounted in: a small low thunk, so the click has a body.
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.005, amplitude: 0.16 * volume, roughness: 0.1, delay: released,
                decayScale: 0.6, hardness: 0.3))
        // The leaf comes off its stop: the frame gives a little, low and quiet.
        let free = released + random.value(in: 0.02...0.03)
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.009, amplitude: 0.26 * volume, roughness: 0.1, delay: free,
                decayScale: 0.8, contact: profile.contact.frame.scaled(level: 0.5), hardness: 0.15))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.004, amplitude: 0.16 * volume, delay: free,
                contact: profile.contact.panel.scaled(level: 0.5), hardness: 0.25))
        rattleGlass(character.glassRattle * 0.12 * volume, after: free + 0.01, hardness: 0.5)
    }

    /// A door closing, from eased shut to slammed.
    ///
    /// The leaf meets its stop; the bolt touches the strike plate and rides up it (a short rising
    /// scrape) until it snaps home (the click); the leaf touches the stop a second time as it
    /// settles. How long the bolt takes shrinks as the door comes in faster. Eased shut there is
    /// more scrape and a soft click; a firm close is tight and bright.
    ///
    /// A slam is the same close and more: air pushed ahead of the leaf (a short swell of noise
    /// before the hit), the frame hit heavily with a strong crack, the leaf bouncing back off it,
    /// and the hardware rattling down. That comes in gradually around the slam threshold
    /// (`DoorStrength.slamWeight`) and keeps growing above it, so a close just under the threshold
    /// and one just over it sound nearly alike, and a hard slam is more than a slam.
    private mutating func close(_ strength: DoorStrength, slam: Bool) {
        let character = profile.character
        if character.softClose {
            softClose(strength.damped)
            return
        }
        let hardness = strength.hardness
        let force = strength.force
        let over = slam ? strength.overSlam : 0
        // The recipe follows the speed, not the name: what is called a slam is at least a little
        // of one, and what is not is at most half.
        let weight = slam ? max(strength.slamWeight, 0.2) : min(strength.slamWeight, 0.5)

        var start: Float = 0
        if slam {
            // Air squeezed out of the doorway ahead of the leaf: a swell in the low middle that
            // rises into the hit. Short, because the hit waits for it.
            start = DoorSynth.slamLead * (1 - 0.3 * over)
            let air = profile.bed.airFrequency
            strike(
                .noise(
                    ContactNoise(level: 0.2, frequency: air * 0.5, q: 0.8, duration: start, swell: 1, glide: 2.4),
                    amplitude: 1.2 * weight * weight * force, reverbSend: 0.7))
        }

        // The leaf meets its stop. A slam lands heavier and longer on the frame, with more crack.
        // Its peak hardly grows: from a firm close up the ring is driven into a soft overload
        // instead (see `ImpactSpec.drive`), and far above the threshold the blow itself even
        // eases off a little, because a door can't hit much harder than hard. What grows is the
        // crack, how long the leaf rings, how much of it the room gives back, and what follows.
        // The bright part comes in first and the heavy part after, so a close never gets duller
        // as it gets harder.
        let bright = weight.squareRoot()
        let heavy = weight * weight
        let crack = 1 + 1.2 * bright
        let roomful = 1 + 0.4 * heavy
        let drive = DoorSynth.slamDrive * (min(max((hardness - 0.55) / 0.25, 0), 1) + over)
        let blow = force * (1 - 0.12 * over) * (1 + (profile.levels.slam - 1) * weight)
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.004, amplitude: 0.55 * blow,
                roughness: 0.3 + 0.2 * weight, delay: start, decayScale: 1 + 0.1 * heavy, reverbSend: roomful,
                contact: profile.contact.frame.scaled(level: crack), hardness: hardness, drive: drive))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.003 * (1 - 0.25 * bright),
                amplitude: (0.35 + 0.05 * weight) * blow,
                delay: start + 0.0015 * weight, detune: 0.03 + 0.02 * weight, decayScale: 1 + 0.3 * heavy,
                reverbSend: roomful, contact: profile.contact.panel.scaled(level: crack), hardness: hardness,
                drive: drive))

        // The edge of the leaf knocks on its stop, wood on wood: a short contact, and the brightest
        // part of the wood. It comes in with the slam, and it is what makes a harder close
        // brighter: in the middle (500 Hz to 1.5 kHz), like a knock, not at the top.
        if weight > 0.02 {
            strike(
                ImpactSpec(
                    modes: profile.knock, contactTime: 0.001,
                    amplitude: Self.edgeKnock * weight * (1.5 + 0.5 * heavy) * blow,
                    roughness: 0.3, delay: start + 0.0005, pitchScale: 2, decayScale: 0.8, reverbSend: roomful,
                    contact: profile.contact.panel.scaled(level: crack), hardness: hardness))
        }

        // The bolt: touches the strike plate, rides up it, snaps home. A heavy iron bolt is lower
        // and slower.
        let heavyBolt = character.heavyBolt
        let boltPitch: Float = heavyBolt ? 0.5 : 1
        let boltDecay: Float = heavyBolt ? 3 : 1
        let home = start + strength.boltDelay * (heavyBolt ? 2 : 1)
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.00035, amplitude: (0.1 + 0.15 * hardness) * force, delay: start,
                pitchScale: boltPitch, decayScale: boltDecay * 0.6, contact: profile.contact.latch,
                hardness: hardness))
        // More of the scrape when the door is eased shut: the bolt takes its time. A slow bolt
        // scrapes low and dull; a quick one zips, and rings the plate.
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0,
                amplitude: 1.8 * (1 - hardness).squareRoot() * (1 - hardness) * (0.3 + hardness) * force,
                delay: start,
                pitchScale: boltPitch, decayScale: boltDecay * 0.5, reverbSend: 0.6,
                contact: ContactNoise(
                    level: 0.1, frequency: profile.contact.latch.frequency * (0.14 + 0.42 * hardness), q: 1.6,
                    duration: home - start, swell: 1, glide: 2.2, ring: 0.05 + 0.15 * hardness)))
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0003, amplitude: (0.3 + 0.45 * hardness + 0.05 * weight) * blow,
                delay: home,
                pitchScale: 1.08 * boltPitch, decayScale: boltDecay, contact: profile.contact.latch,
                hardness: hardness))
        // And the leaf answers the bolt: a low thunk under the click, so it is never a bare tick.
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.005, amplitude: (0.1 + 0.1 * hardness) * blow, roughness: 0.1,
                delay: home, decayScale: 0.6, hardness: hardness * 0.6))

        // The second touch: a latched leaf settling against its stop, a slammed one bouncing
        // back off the frame.
        let again =
            slam
            ? start + random.value(in: 0.07...0.11)
            : home + random.value(in: 0.045...0.075) * (heavyBolt ? 1.3 : 1)
        let touch = (0.13 + 0.15 * weight + 0.12 * over) * force
        let softer = max(hardness - 0.3, 0)
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.006, amplitude: touch, roughness: 0.2, delay: again,
                decayScale: 0.8 + 0.3 * weight, contact: profile.contact.frame, hardness: softer))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.004, amplitude: touch * 0.6, delay: again,
                contact: profile.contact.panel, hardness: softer))
        // The bolt knocks in its keep as the leaf comes back.
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.00035, amplitude: (0.07 + 0.1 * weight) * force,
                delay: again + 0.003, pitchScale: 0.95 * boltPitch, decayScale: boltDecay * 0.5,
                contact: profile.contact.latch, hardness: softer))
        if over > 0.05 {
            // Thrown hard enough to come back twice.
            strike(
                ImpactSpec(
                    modes: profile.frame, contactTime: 0.007, amplitude: 0.4 * over * force, roughness: 0.2,
                    delay: again + random.value(in: 0.055...0.085), decayScale: 0.8,
                    contact: profile.contact.frame, hardness: max(softer - 0.2, 0)))
        }

        // The hardware rattling down: hinge knuckles on their pins, longer after a harder slam.
        if weight > 0.05 {
            var time = start + 0.03
            var level = 0.3 * (0.4 * bright + 0.6 * weight) * force
            for _ in 0..<(4 + Int(2 * over + 0.5)) {
                strike(
                    ImpactSpec(
                        modes: profile.hinge, contactTime: 0.0006, amplitude: level, delay: time,
                        pitchScale: random.value(in: 0.95...1.05), contact: profile.contact.hinge,
                        hardness: hardness))
                time += random.value(in: 0.02...0.045) * (1 + 0.4 * over)
                level *= 0.6 + 0.1 * over
            }
        }
        // (The panes are shaken by the whole leaf, so they don't ease off as much as the blow.)
        rattleGlass(
            character.glassRattle * (0.4 + 0.6 * weight) * force * (1 - 0.12 * over), after: start + 0.006,
            hardness: hardness)
        clatterBoards(
            character.looseBoards * (0.1 + 0.9 * weight) * blow, after: start + 0.01,
            count: 2 + Int(3 * weight + 0.5), hardness: hardness)
    }

    /// A soft-close door can't slam: the damper takes the speed out, a seal hisses, and a magnet
    /// catches the leaf. (`strength` is what is left after the damper.)
    private mutating func softClose(_ strength: DoorStrength) {
        let hardness = strength.hardness
        // Under the damper loudness follows what speed is left more closely than on a free door:
        // eased shut, the hatch hardly lands.
        let force = powf(max(strength.speed, DoorStrength.softest) / 150, 1.1) * profile.levels.softClose
        // The seal takes up, air let out as it is squeezed: most of what is heard of a soft close.
        strike(
            .noise(
                ContactNoise(level: 0.36, frequency: 900, q: 0.9, duration: 0.45, glide: 0.6),
                amplitude: profile.character.airlockHiss * force, delay: 0.01, reverbSend: 0.5, hardness: hardness))
        // So the hit itself is softer than the speed says: a padded thud, and the skin ringing.
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.012, amplitude: 0.4 * force, roughness: 0.05,
                contact: profile.contact.frame, hardness: hardness * 0.6, drive: 1))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.005, amplitude: 0.55 * force, roughness: 0.05,
                decayScale: 1.3, contact: profile.contact.panel, hardness: hardness * 0.6, drive: 0.8))
        // The catch pulls the leaf the last of the way: a clean click, sooner when it came in fast.
        let home = strength.boltDelay * 0.8
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0003, amplitude: 0.18 * force, delay: home,
                pitchScale: 1.1, decayScale: 0.5, contact: profile.contact.latch, hardness: hardness))
        // And the damper pushes back once.
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.014, amplitude: 0.12 * force, roughness: 0.05,
                delay: home + random.value(in: 0.05...0.07), decayScale: 0.8, hardness: hardness * 0.4))
    }

    /// The open leaf runs into its door stop, each door's own (`DoorStop`): the stop sounds, the
    /// leaf takes the blow, a loose stop chatters, and the leaf shudders on its hinges after.
    private mutating func openStop(_ strength: DoorStrength) {
        let stop = profile.stop
        let hardness = strength.hardness
        // As loud at a normal opening speed as a close at the same speed, levelling off sooner:
        // a leaf swung open has less behind it than one pulled shut.
        let force = powf(min(max(strength.speed, DoorStrength.softest), 400) / 120, 0.6) * profile.levels.stop

        strike(
            ImpactSpec(
                modes: stop.modes, contactTime: stop.contactTime, amplitude: stop.level * force, roughness: 0.15,
                reverbSend: 0.8, contact: profile.contact.stop, hardness: hardness))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: max(stop.contactTime, 0.003), amplitude: stop.leaf * force,
                roughness: 0.1, decayScale: 0.8, contact: profile.contact.panel.scaled(level: 0.5),
                hardness: hardness * 0.8))

        // A stop that is loose (a ring, a spring) bounces: quicker and quieter each time.
        var time = stop.bounceGap * random.value(in: 0.9...1.1)
        var gap = time
        var level = stop.level * 0.5 * force
        for _ in 0..<min(max(stop.bounces, 0), 4) {
            strike(
                ImpactSpec(
                    modes: stop.modes, contactTime: stop.contactTime * 0.7, amplitude: level, delay: time,
                    pitchScale: random.value(in: 0.97...1.03), reverbSend: 0.8,
                    contact: profile.contact.stop.scaled(level: 0.6), hardness: max(hardness - 0.2, 0)))
            gap *= 0.62
            time += gap
            level *= 0.55
        }

        // The shudder: the leaf swings back a hair and settles, heard in the frame through the
        // hinges, and a hinge knuckle ticks.
        let wobble = random.value(in: 0.05...0.07)
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.012, amplitude: stop.shudder * force, roughness: 0.1,
                delay: wobble, decayScale: 0.7, hardness: 0.2))
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.014, amplitude: stop.shudder * 0.5 * force, roughness: 0.1,
                delay: wobble * 2.1, decayScale: 0.6, hardness: 0.1))
        strike(
            ImpactSpec(
                modes: profile.hinge, contactTime: 0.0005, amplitude: 0.1 * force, delay: 0.035,
                contact: profile.contact.hinge, hardness: hardness))

        if stop.windDown > 0 {
            // The actuator has nowhere left to go: its whine falls away as the motor runs down.
            let level = stop.windDown * force
            strike(
                .noise(
                    ContactNoise(level: 0.5, frequency: 640, q: 10, duration: 0.42, glide: 0.3),
                    amplitude: level, delay: 0.01, reverbSend: 0.6))
            strike(
                .noise(
                    ContactNoise(level: 0.22, frequency: 1_280, q: 10, duration: 0.3, glide: 0.3),
                    amplitude: level, delay: 0.01, reverbSend: 0.6))
        }
        rattleGlass(profile.character.glassRattle * 0.3 * force, after: 0.01, hardness: hardness)
        clatterBoards(profile.character.looseBoards * 0.3 * force, after: 0.012, count: 2, hardness: hardness)
    }

    /// A pneumatic "pfff": noise through broad resonances (`SoundProfile.air`), swelling and fading.
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
                    modes: SoundProfile.glass, contactTime: 0.0004, amplitude: amplitude * 0.4, roughness: 0.6,
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

    /// Starts an impact on a free voice, or steals the one furthest into its decay.
    private mutating func strike(_ spec: ImpactSpec) {
        var chosen = 0
        var leastLeft = Float.infinity
        for index in voices.indices {
            let left = voices[index].lifeLeft
            if left == 0 {
                chosen = index
                break
            }
            if left < leastLeft {
                leastLeft = left
                chosen = index
            }
        }
        voices[chosen].start(spec, sampleRate: sampleRate, random: &random)
    }
}
