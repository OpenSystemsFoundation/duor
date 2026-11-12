import Foundation

/// The broadband "crack" of two surfaces meeting, next to the ring of what was hit: a short burst
/// of band-passed noise. It is what tells wood from steel from rubber in the first few
/// milliseconds, and the part of a hit a phone speaker plays best.
nonisolated struct ContactNoise: Sendable, Equatable {
    /// Loudness of the burst at its start, as RMS next to a mode of gain 1 (0 = none).
    var level: Float
    /// Centre of the band in Hz. Hard, small things are bright; soft, big things dull.
    var frequency: Float
    /// How narrow the band is (centre / width). Around 1 is a broad "tch", higher more pitched.
    var q: Float = 0.9
    /// Seconds from start to silence, for a hit of middling hardness (2 to 20 ms).
    var duration: Float

    static let none = ContactNoise(level: 0, frequency: 1_000, duration: 0.002)
}

/// How to strike an object: what is hit, how hard, and how soft the contact is.
nonisolated struct ImpactSpec: Sendable {
    var modes: ModeSet
    /// Seconds of contact. Short contact (a fingernail, a steel bolt) excites high modes;
    /// long contact (a knuckle, a rubber stop) only the low ones.
    var contactTime: Float
    var amplitude: Float
    /// Roughness added to the contact force (0 = smooth, 1 = gritty).
    var roughness: Float = 0.3
    /// Seconds to wait before striking. Lets one sound be several hits.
    var delay: Float = 0
    /// Random detune per mode (fraction), so no two hits are identical.
    var detune: Float = 0.03
    var pitchScale: Float = 1
    var decayScale: Float = 1
    /// How much of this hit reaches the room reverb (0 = dry and close, 1 = full room).
    var reverbSend: Float = 1
    /// The noise of the surfaces meeting, on top of the ring.
    var contact: ContactNoise = .none
    /// How hard the hit is, 0 (eased together) ... 1 (as hard as it gets), see
    /// `DoorStrength.hardness`. A harder hit is a shorter contact with more of its energy in the
    /// high modes and a louder, shorter, brighter crack. 0.5 leaves the spec as written. Loudness
    /// stays with `amplitude`.
    var hardness: Float = 0.5
    /// Soft saturation of the ring (0 = clean). Rounds the first peaks of a hit the way a heavy
    /// hit overloads the ear, which makes it sound weightier for the same peak. A choice per hit:
    /// the mix itself stays clean.
    var drive: Float = 0
}

/// Plays one impact: a half-sine contact force driving a bank of modal resonators, plus a burst of
/// contact noise.
nonisolated struct ImpactVoice: Sendable {
    private(set) var isActive = false
    private var delay = 0
    private var age = 0
    private var lifetime = 0
    private var contactLength = 1
    private var pulseNormalization: Float = 0
    private var roughness: Float = 0
    private var amplitude: Float = 0
    private var reverbSend: Float = 0
    private var drive: Float = 0
    private var modes = ModalBank()
    private var noise = NoiseSource(seed: 1)

    // Contact noise.
    private var band = Biquad(.bandPass, frequency: 1_000, q: 1, sampleRate: 48_000)
    private var noiseLength = 0
    private var noiseLevel: Float = 0
    private var noiseAttack: Float = 0

    // What this voice was playing when it was stolen, fading out under the new hit.
    private var ghost = ModalBank()
    private var ghostRemaining = 0
    private var ghostGain: Float = 0
    private var ghostStep: Float = 0
    private var ghostSend: Float = 0
    private var ghostDrive: Float = 0

    /// A stolen voice fades over this long instead of being cut dead, which would click.
    static let stealFade: Float = 0.002

    /// Samples until this voice falls silent. Used to steal the voice closest to finishing.
    var remaining: Int { isActive ? delay + lifetime - age : 0 }

    mutating func start(_ spec: ImpactSpec, sampleRate: Float, random: inout NoiseSource) {
        if isActive, age > 0 {
            // Still ringing: let the old ring fade under the new hit.
            ghost = modes
            ghostRemaining = max(1, Int(Self.stealFade * sampleRate))
            ghostGain = amplitude
            ghostStep = amplitude / Float(ghostRemaining)
            ghostSend = reverbSend
            ghostDrive = drive
        }
        // (A voice stolen before it sounded has nothing to fade; a ghost already fading goes on.)

        // Harder is shorter and brighter: a third of the contact time from the softest hit to the
        // hardest, and a few dB per octave less or more in the high modes.
        let hardness = (spec.hardness.isFinite ? min(max(spec.hardness, 0), 1) : 0.5) - 0.5
        let shortening = expf(-1.1 * hardness)

        delay = Int(max(spec.delay, 0) * sampleRate)
        age = 0
        contactLength = max(1, Int(spec.contactTime * shortening * sampleRate))
        // A half-sine pulse sums to 2L/π; normalize so the low modes see a unit impulse.
        pulseNormalization = Float.pi / (2 * Float(contactLength))
        roughness = spec.roughness
        amplitude = spec.amplitude
        reverbSend = spec.reverbSend
        drive = max(spec.drive, 0)
        noise = NoiseSource(seed: random.nextUInt())

        var longestDecay: Float = 0
        modes.silence()
        for index in spec.modes.indices {
            let mode = spec.modes[index]
            let decay = mode.decay * spec.decayScale * (1 + 0.1 * random.bipolar())
            let frequency = mode.frequency * spec.pitchScale * (1 + spec.detune * random.bipolar())
            // Modes below the hinge keep their level: a soft contact still moves the whole object,
            // it just doesn't reach the high modes, and a hard one adds to them. So a harder hit is
            // never duller or quieter than a softer one, whatever it hits.
            let tilt =
                hardness == 0 ? 1 : powf(max(mode.frequency, Self.tiltHinge) / Self.tiltHinge, Self.tilt * hardness)
            modes.tune(lane: index, frequency: frequency, decay: decay, gain: mode.gain * tilt, sampleRate: sampleRate)
            longestDecay = max(longestDecay, decay)
        }

        noiseLength = 0
        if spec.contact.level > 0 {
            let length = min(max(spec.contact.duration * shortening, 0.0005), 0.05)
            let frequency = min(max(spec.contact.frequency * expf(0.7 * hardness), 40), sampleRate * 0.4)
            let q = min(max(spec.contact.q, 0.3), 8)
            noiseLength = max(2, Int(length * sampleRate))
            band = Biquad(.bandPass, frequency: frequency, q: q, sampleRate: sampleRate)
            // White noise in -1...1 has an RMS of 1/√3; the band keeps a share π·f/(q·rate) of its
            // power. Undo both, so `level` is the burst's RMS whatever its band.
            let passed = (Float.pi * frequency / (q * sampleRate)).squareRoot() / Float(3).squareRoot()
            noiseLevel = spec.contact.level * (0.4 + 1.2 * (hardness + 0.5)) * spec.amplitude / passed
            // A quarter of a millisecond in, so the burst starts without a step.
            noiseAttack = 1 / max(1, 0.00025 * sampleRate)
        }

        // e^-7 is about -60 dB: inaudible.
        lifetime = max(contactLength + Int(longestDecay * 7 * sampleRate), noiseLength)
        isActive = true
    }

    /// How strongly hardness tilts the modes: the exponent on frequency at the hardest hit is half
    /// of this (0.7 is about 2 dB per octave), above `tiltHinge` Hz. The hinge is the same for
    /// every object, so a harder close also shifts the balance from the thud of the leaf toward
    /// the click of the bolt.
    private static let tilt: Float = 0.7
    private static let tiltHinge: Float = 250

    /// Adds this voice to `output`, and to `send` scaled by its reverb send.
    mutating func render(into output: UnsafeMutableBufferPointer<Float>, send: UnsafeMutableBufferPointer<Float>) {
        if ghostRemaining > 0 {
            let count = min(ghostRemaining, output.count)
            for frame in 0..<count {
                var ring = ghost.process(0)
                if ghostDrive > 0 { ring = tanhf(ring * ghostDrive) / ghostDrive }
                ghostGain -= ghostStep
                let sample = ring * ghostGain
                output[frame] += sample
                send[frame] += sample * ghostSend
            }
            ghostRemaining -= count
        }
        guard isActive else { return }
        if delay >= output.count {
            delay -= output.count
            return
        }
        var frame = delay
        delay = 0
        while frame < output.count {
            var force: Float = 0
            if age < contactLength {
                let phase = (Float(age) + 0.5) / Float(contactLength)
                force = sinf(Float.pi * phase) * pulseNormalization * (1 + roughness * noise.bipolar())
            }
            var sample = modes.process(force)
            if drive > 0 { sample = tanhf(sample * drive) / drive }
            sample *= amplitude
            if age < noiseLength {
                // Fast in, then falling away to nothing at the end of the burst.
                let time = Float(age)
                let left = 1 - time / Float(noiseLength)
                let envelope = left * left * left * min(1, (time + 1) * noiseAttack)
                sample += band.process(noise.bipolar()) * envelope * noiseLevel
            }
            output[frame] += sample
            send[frame] += sample * reverbSend
            age += 1
            if age >= lifetime {
                isActive = false
                return
            }
            frame += 1
        }
    }
}
