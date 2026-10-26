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
        case profile(SoundProfile)
    }

    private struct Inbox: Sendable {
        var commands: [Command]
        var creakVelocity: Float = 0
    }

    /// Commands past this many per buffer are dropped rather than growing the queue.
    fileprivate static let inboxCapacity = 32

    private let inbox: Mutex<Inbox>
    private let core: Mutex<SynthCore>

    init(sampleRate: Float, profile: SoundProfile = .oak, seed: UInt32 = .random(in: 1...UInt32.max)) {
        var commands: [Command] = []
        commands.reserveCapacity(Self.inboxCapacity)
        inbox = Mutex(Inbox(commands: commands))
        core = Mutex(SynthCore(sampleRate: sampleRate, profile: profile, seed: seed))
    }

    // MARK: Main thread

    func play(_ sound: DoorSound, volume: Float = 1) {
        post(.play(sound, volume: min(max(volume, 0), 1)))
    }

    /// Signed hinge velocity in degrees per second. 0 lets the creak fade out.
    func setCreak(velocity: Float) {
        inbox.withLock { $0.creakVelocity = velocity }
    }

    func setProfile(_ profile: SoundProfile) {
        post(.profile(profile))
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
    var random: NoiseSource
    var pending: [DoorSynth.Command]
    var creakVelocity: Float = 0
    let masterGain: Float = 0.9
    /// Reverb send bus. Fixed size: renders are split into chunks of at most this many frames.
    var send: [Float]
    static let chunkSize = 512

    init(sampleRate: Float, profile: SoundProfile, seed: UInt32) {
        self.sampleRate = sampleRate
        self.profile = profile
        random = NoiseSource(seed: seed)
        creak = CreakVoice(profile: profile.creak, sampleRate: sampleRate, seed: seed &* 2_654_435_761)
        reverb = RoomReverb(sampleRate: sampleRate, mix: profile.room)
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

            // Room, then a soft clipper so stacked hits saturate gently instead of clipping.
            for frame in output.indices {
                output[frame] = tanhf((output[frame] + reverb.process(send[frame])) * masterGain)
            }
        }
    }

    private mutating func handle(_ command: DoorSynth.Command) {
        switch command {
        case .profile(let newProfile):
            profile = newProfile
            creak.setProfile(newProfile.creak)
            reverb.mix = newProfile.room
        case .play(let sound, let volume):
            switch sound {
            case .knock: knock(volume)
            case .unlatch: unlatch(volume)
            case .latch: latch(volume)
            case .slam: slam(volume)
            case .openStop: openStop(volume)
            }
        }
    }

    // MARK: Recipes. Each sound is one or more strikes on the door's materials.

    /// A knuckle on solid wood: a short, heavily damped "tok" plus the knuckle's own sharp snap.
    /// Mostly dry, so it sounds close and tight rather than boomy.
    private mutating func knock(_ volume: Float) {
        let pitch = random.value(in: 0.97...1.03)
        strike(
            ImpactSpec(
                modes: profile.knock, contactTime: random.value(in: 0.0008...0.0012),
                amplitude: 0.9 * volume, roughness: 0.2, detune: 0.03, pitchScale: pitch,
                reverbSend: 0.3))
        strike(
            ImpactSpec(
                modes: profile.knock, contactTime: 0.0002, amplitude: 0.3 * volume,
                roughness: 0.9, pitchScale: 3.2 * pitch, decayScale: 0.3, reverbSend: 0.15))
    }

    /// Handle turns, bolt slides out of the strike plate: two small metal clicks.
    private mutating func unlatch(_ volume: Float) {
        strike(ImpactSpec(modes: profile.latch, contactTime: 0.0002, amplitude: 0.35 * volume))
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0003, amplitude: 0.25 * volume,
                delay: random.value(in: 0.018...0.03), pitchScale: 0.85))
        strike(ImpactSpec(modes: profile.panel, contactTime: 0.002, amplitude: 0.15 * volume))
    }

    /// Door meets the frame, bolt rides the strike plate, then snaps into place.
    private mutating func latch(_ volume: Float) {
        strike(ImpactSpec(modes: profile.frame, contactTime: 0.004, amplitude: 0.55 * volume * volume))
        strike(ImpactSpec(modes: profile.panel, contactTime: 0.003, amplitude: 0.35 * volume))
        strike(ImpactSpec(modes: profile.latch, contactTime: 0.00025, amplitude: 0.3 * volume))
        strike(
            ImpactSpec(
                modes: profile.latch, contactTime: 0.0002, amplitude: 0.5 * volume,
                delay: random.value(in: 0.028...0.045), pitchScale: 1.08))
    }

    /// Heavy hit into the frame, the latch, then the hinges rattling down.
    private mutating func slam(_ volume: Float) {
        strike(
            ImpactSpec(
                modes: profile.frame, contactTime: 0.006, amplitude: volume,
                roughness: 0.5, decayScale: 1.4))
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.004, amplitude: 0.7 * volume,
                detune: 0.05, decayScale: 1.3))
        strike(ImpactSpec(modes: profile.latch, contactTime: 0.0002, amplitude: 0.45 * volume, delay: 0.008))
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
    }

    /// Door swings into a rubber stop: dull thud and a small hinge tick.
    private mutating func openStop(_ volume: Float) {
        strike(
            ImpactSpec(
                modes: profile.panel, contactTime: 0.008, amplitude: 1.6 * volume, roughness: 0.1, decayScale: 0.8))
        strike(ImpactSpec(modes: profile.hinge, contactTime: 0.0005, amplitude: 0.12 * volume, delay: 0.035))
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
