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

/// Synthesizes every door sound in real time. No samples.
///
/// Thread model: the main thread posts commands into a small locked inbox; the audio thread
/// swaps the inbox out at the start of each buffer and renders. `render(into:)` never allocates.
nonisolated final class DoorSynth: Sendable {
    fileprivate enum Command: Sendable {
        case play(DoorSound, volume: Float)
        case knock(KnockSpot, volume: Float)
        case profile(SoundProfile)
    }

    private struct Inbox: Sendable {
        var commands: [Command]
        var creakVelocity: Float = 0
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

    func play(_ sound: DoorSound, volume: Float = 1) {
        post(.play(sound, volume: min(max(volume, 0), 1)))
    }

    /// A knock on a particular spot of the door. `play(.knock)` knocks in the middle.
    func knock(at spot: KnockSpot, volume: Float = 1) {
        post(.knock(spot, volume: min(max(volume, 0), 1)))
    }

    /// Signed hinge velocity in degrees per second. 0 lets the creak fade out.
    func setCreak(velocity: Float) {
        inbox.withLock { $0.creakVelocity = velocity }
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

    /// Fills `output` with mono samples in -1...1.
    func render(into output: UnsafeMutableBufferPointer<Float>) {
        core.withLock { core in
            inbox.withLock { inbox in
                // Both arrays keep their reserved capacity, so the swap never allocates.
                swap(&core.pending, &inbox.commands)
                core.creakVelocity = inbox.creakVelocity
                core.voicing.isOn = inbox.speakerVoicing
            }
            core.render(into: output)
        }
    }
}

/// Audio-thread state. Only touched inside `DoorSynth.render(into:)`.
private nonisolated struct SynthCore: Sendable {
    let sampleRate: Float
    var profile: SoundProfile
    var voices = InlineArray<24, ImpactVoice>(repeating: ImpactVoice())
    var creak: CreakVoice
    var reverb: RoomReverb
    var voicing: SpeakerVoicing
    var random: NoiseSource
    var pending: [DoorSynth.Command]
    var creakVelocity: Float = 0
    let masterGain: Float = 0.9
    /// Reverb send bus. Fixed size: renders are split into chunks of at most this many frames.
    var send: [Float]
    static let chunkSize = 512

    init(sampleRate: Float, profile: SoundProfile, seed: UInt32, speakerVoicing: Bool) {
        self.sampleRate = sampleRate
        self.profile = profile
        random = NoiseSource(seed: seed)
        creak = CreakVoice(profile: profile.creak, sampleRate: sampleRate, seed: seed &* 2_654_435_761)
        reverb = RoomReverb(sampleRate: sampleRate, mix: profile.room)
        voicing = SpeakerVoicing(sampleRate: sampleRate, isOn: speakerVoicing)
        pending = []
        pending.reserveCapacity(DoorSynth.inboxCapacity)
        send = [Float](repeating: 0, count: Self.chunkSize)
    }

    mutating func render(into output: UnsafeMutableBufferPointer<Float>) {
        for command in pending {
            handle(command)
        }
        pending.removeAll(keepingCapacity: true)
        creak.setTarget(velocity: creakVelocity)

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
            creak.render(into: output, send: send)

            // Room, voicing for the phone's speakers (when on), then a soft clipper so stacked hits
            // saturate gently instead of clipping.
            for frame in output.indices {
                let mixed = output[frame] + reverb.process(send[frame])
                output[frame] = tanhf(voicing.process(mixed) * masterGain)
            }
        }
    }

    private mutating func handle(_ command: DoorSynth.Command) {
        switch command {
        case .profile(let newProfile):
            profile = newProfile
            creak.setProfile(newProfile.creak)
            reverb.mix = newProfile.room
        case .knock(let spot, let volume):
            knock(at: spot, volume)
        case .play(let sound, let volume):
            switch sound {
            case .knock: knock(at: .center, volume)
            case .unlatch: unlatch(volume)
            case .latch: latch(volume)
            case .slam: slam(volume)
            case .openStop: openStop(volume)
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
                amplitude: 0.9 * volume, roughness: 0.2, detune: 0.03, pitchScale: pitch,
                decayScale: spot.decayScale, reverbSend: 0.3 + profile.room))
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
                    reverbSend: 0.3))
        }
        // No glass on knocks: the panes only rattle when the door moves.
        clatterBoards(profile.character.looseBoards * 0.4 * volume, after: 0.006, count: 2)
    }

    /// Handle turns, bolt slides out of the strike plate.
    private mutating func unlatch(_ volume: Float) {
        hiss(profile.character.airlockHiss * volume, after: 0.03, duration: 0.5)
        if profile.character.heavyBolt {
            // A big iron bolt dragged back: a low clank, a scrape, a second clank.
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0006, amplitude: 0.5 * volume, pitchScale: 0.5, decayScale: 3))
            strike(
                ImpactSpec(
                    modes: profile.hinge, contactTime: 0.03, amplitude: 0.12 * volume, roughness: 1, delay: 0.02,
                    pitchScale: 0.9, decayScale: 0.5))
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.0005, amplitude: 0.4 * volume,
                    delay: random.value(in: 0.07...0.09), pitchScale: 0.45, decayScale: 3))
            return
        }
        strike(ImpactSpec(modes: profile.latch, contactTime: 0.0002, amplitude: 0.35 * volume))
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0003, amplitude: 0.25 * volume,
                delay: random.value(in: 0.018...0.03), pitchScale: 0.85))
        strike(ImpactSpec(modes: profile.panel, contactTime: 0.002, amplitude: 0.15 * volume))
        rattleGlass(profile.character.glassRattle * 0.12 * volume, after: 0.01)
    }

    /// Door meets the frame, bolt rides the strike plate, then snaps into place.
    private mutating func latch(_ volume: Float) {
        if profile.character.softClose {
            hiss(profile.character.airlockHiss * 0.8 * volume, after: 0.04, duration: 0.35)
            // The damper takes the speed out; a magnet catches the door.
            strike(ImpactSpec(modes: profile.frame, contactTime: 0.014, amplitude: 0.5 * volume, roughness: 0.05))
            strike(
                ImpactSpec(
                    modes: profile.latch, contactTime: 0.00015, amplitude: 0.35 * volume, delay: 0.02,
                    pitchScale: 1.35, decayScale: 0.5))
            return
        }
        strike(ImpactSpec(modes: profile.frame, contactTime: 0.004, amplitude: 0.55 * volume * volume))
        strike(ImpactSpec(modes: profile.panel, contactTime: 0.003, amplitude: 0.35 * volume))
        let boltPitch: Float = profile.character.heavyBolt ? 0.5 : 1
        let boltDecay: Float = profile.character.heavyBolt ? 3 : 1
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.00025, amplitude: 0.3 * volume, pitchScale: boltPitch,
                decayScale: boltDecay))
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0002, amplitude: 0.5 * volume,
                delay: random.value(in: 0.028...0.045) * (profile.character.heavyBolt ? 2 : 1),
                pitchScale: 1.08 * boltPitch, decayScale: boltDecay))
        rattleGlass(profile.character.glassRattle * 0.4 * volume, after: 0.006)
        clatterBoards(profile.character.looseBoards * 0.35 * volume, after: 0.01, count: 2)
    }

    /// Heavy hit into the frame, the latch, then the hinges rattling down.
    private mutating func slam(_ volume: Float) {
        if profile.character.softClose {
            // A soft-close door can't slam: it just closes a little firmer.
            latch(min(volume, 1))
            return
        }
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.006, amplitude: volume,
                roughness: 0.5, decayScale: 1.4))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.004, amplitude: 0.7 * volume,
                detune: 0.05, decayScale: 1.3))
        let heavy = profile.character.heavyBolt
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0002, amplitude: 0.45 * volume, delay: 0.008,
                pitchScale: heavy ? 0.5 : 1, decayScale: heavy ? 3 : 1))
        var time: Float = 0.03
        var level: Float = 0.25
        for _ in 0..<4 {
            strike(
                ImpactSpec(
                    modes: profile.hinge, contactTime: 0.0004, amplitude: level * volume,
                    delay: time, pitchScale: random.value(in: 0.95...1.05)))
            time += random.value(in: 0.02...0.045)
            level *= 0.6
        }
        rattleGlass(profile.character.glassRattle * volume, after: 0.01)
        clatterBoards(profile.character.looseBoards * volume, after: 0.015, count: 5)
    }

    /// Door swings into a rubber stop: dull thud and a small hinge tick.
    private mutating func openStop(_ volume: Float) {
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.008, amplitude: 1.6 * volume, roughness: 0.1, decayScale: 0.8))
        strike(ImpactSpec(modes: profile.hinge, contactTime: 0.0005, amplitude: 0.12 * volume, delay: 0.035))
        rattleGlass(profile.character.glassRattle * 0.3 * volume, after: 0.01)
        clatterBoards(profile.character.looseBoards * 0.3 * volume, after: 0.012, count: 2)
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
    private mutating func rattleGlass(_ level: Float, after delay: Float) {
        guard level > 0.001 else { return }
        var time = delay
        var amplitude = level
        for _ in 0..<5 {
            strike(
                ImpactSpec(
                    modes: SoundProfile.glass, contactTime: 0.00015, amplitude: amplitude * 0.5, roughness: 0.6,
                    delay: time, detune: 0.02, pitchScale: random.value(in: 0.97...1.03), reverbSend: 0.5))
            time += random.value(in: 0.012...0.03)
            amplitude *= 0.62
        }
    }

    /// Loose planks knocking against each other after a hit.
    private mutating func clatterBoards(_ level: Float, after delay: Float, count: Int) {
        guard level > 0.001 else { return }
        var time = delay
        var amplitude = level
        for _ in 0..<count {
            strike(
                ImpactSpec(
                    modes: profile.knock, contactTime: 0.0012, amplitude: amplitude * 0.7, roughness: 0.5,
                    delay: time, pitchScale: random.value(in: 1.5...2.2), decayScale: 0.6))
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
