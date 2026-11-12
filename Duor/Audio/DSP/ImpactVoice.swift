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
    /// Seconds from start to silence, for a hit of middling hardness (2 to 20 ms for a hit; a
    /// scrape or a rush of air can last up to most of a second).
    var duration: Float
    /// The shape of the burst. 0 is a hit: in at once and falling away. 1 is something arriving:
    /// it swells up to its end and stops there (air pushed ahead of a leaf, a bolt riding up its
    /// ramp until it drops home).
    var swell: Float = 0
    /// Where the band ends up, as a multiple of `frequency`: above 1 the noise rises over its
    /// length (a scrape that speeds up), below 1 it falls (a motor winding down).
    var glide: Float = 1
    /// How much of the burst also drives the modes of what is struck (0 = none; at 1 they ring
    /// about as loud as `level` 1 would be). A scrape along metal is heard mostly this way: noise
    /// with the metal's colour instead of plain hiss.
    var ring: Float = 0

    static let none = ContactNoise(level: 0, frequency: 1_000, duration: 0.002)

    /// The same burst, louder or quieter.
    func scaled(level factor: Float) -> ContactNoise {
        var copy = self
        copy.level *= factor
        copy.ring *= factor
        return copy
    }
}

/// How to strike an object: what is hit, how hard, and how soft the contact is.
nonisolated struct ImpactSpec: Sendable {
    var modes: ModeSet
    /// Seconds of contact. Short contact (a fingernail, a steel bolt) excites high modes;
    /// long contact (a knuckle, a rubber stop) only the low ones. 0 is no blow at all: only the
    /// contact noise is heard, and what it rings.
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

    /// Nothing is struck: only a noise, such as air or a seal.
    static func noise(
        _ noise: ContactNoise, amplitude: Float, delay: Float = 0, reverbSend: Float = 1, hardness: Float = 0.5
    ) -> ImpactSpec {
        ImpactSpec(
            modes: ModeSet(repeating: ModeSpec(1_000, 0.001, 0)), contactTime: 0, amplitude: amplitude, roughness: 0,
            delay: delay, detune: 0, reverbSend: reverbSend, contact: noise, hardness: hardness)
    }
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
    private var noiseRelease: Float = 0
    private var noiseSwell: Float = 0
    /// One over the burst's length in samples.
    private var noiseStep: Float = 0
    /// How loud the burst drives the modes.
    private var noiseRing: Float = 0
    /// A gliding band: where it starts, its width, and the logarithm of how far it moves.
    private var noiseFrequency: Float = 1_000
    private var noiseQ: Float = 1
    private var noiseGlide: Float = 0
    private var rate: Float = 48_000

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
        // (Not finite or not positive: no blow.)
        contactLength = spec.contactTime > 0 ? max(1, Int(min(spec.contactTime, 2) * shortening * sampleRate)) : 0
        // A half-sine pulse sums to 2L/π; normalize so the low modes see a unit impulse.
        pulseNormalization = Float.pi / (2 * Float(max(contactLength, 1)))
        roughness = spec.roughness
        amplitude = spec.amplitude
        reverbSend = spec.reverbSend
        drive = spec.drive.isFinite ? min(max(spec.drive, 0), 8) : 0
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
        noiseRing = 0
        var ringOut = 0
        let contact = spec.contact
        if contact.level > 0 || contact.ring > 0, contact.level.isFinite, contact.ring.isFinite,
            contact.duration.isFinite, contact.frequency.isFinite, contact.q.isFinite
        {
            let length = min(max(contact.duration * shortening, 0.0005), 0.8)
            let frequency = min(max(contact.frequency * expf(0.7 * hardness), 40), sampleRate * 0.4)
            let q = min(max(contact.q, 0.3), 16)
            noiseLength = max(2, Int(length * sampleRate))
            noiseStep = 1 / Float(noiseLength)
            band = Biquad(.bandPass, frequency: frequency, q: q, sampleRate: sampleRate)
            rate = sampleRate
            noiseFrequency = frequency
            noiseQ = q
            let glide = contact.glide.isFinite ? min(max(contact.glide, 0.1), 10) : 1
            noiseGlide = glide == 1 ? 0 : logf(glide)
            noiseSwell = contact.swell.isFinite ? min(max(contact.swell, 0), 1) : 0
            // White noise in -1...1 has an RMS of 1/√3; the band keeps a share π·f/(q·rate) of its
            // power. Undo both, so `level` is the burst's RMS whatever its band.
            let passed = (Float.pi * frequency / (q * sampleRate)).squareRoot() / Float(3).squareRoot()
            noiseLevel = max(contact.level, 0) * (0.4 + 1.2 * (hardness + 0.5)) * spec.amplitude / passed
            // A quarter of a millisecond in, so the burst starts without a step, and a millisecond
            // and a half out when it ends at its loudest.
            noiseAttack = 1 / max(1, 0.00025 * sampleRate)
            noiseRelease = Float(noiseLength) / max(1, 0.0015 * sampleRate)
            if contact.ring > 0 {
                // Noise at the band's centre passes at full strength, 1/3 in power, and a mode it
                // drives rings up to that times a quarter of its decay in samples. Undo it, so
                // `ring` is about the level of the ringing whatever the mode.
                noiseRing = contact.ring / (max(longestDecay, 0.0005) * sampleRate / 12).squareRoot()
                ringOut = Int(longestDecay * 7 * sampleRate)
            }
        }

        // e^-7 is about -60 dB: inaudible.
        lifetime = max(contactLength + Int(longestDecay * 7 * sampleRate), noiseLength + ringOut)
        isActive = true
    }

    /// How strongly hardness tilts the modes: the exponent on frequency at the hardest hit is half
    /// of this (0.7 is about 2 dB per octave), above `tiltHinge` Hz. The hinge is the same for
    /// every object, so a harder close also shifts the balance from the thud of the leaf toward
    /// the click of the bolt.
    private static let tilt: Float = 0.7
    private static let tiltHinge: Float = 250

    /// The soft overload behind `ImpactSpec.drive`: close to tanh (within 2.5 %), levelling off
    /// at ±1, without the cost of an exponential on every sample of every driven voice.
    @inline(__always)
    private static func overload(_ value: Float) -> Float {
        let x = min(max(value, -3), 3)
        let square = x * x
        return x * (27 + square) / (27 + 9 * square)
    }

    /// Adds this voice to `output`, and to `send` scaled by its reverb send.
    mutating func render(into output: UnsafeMutableBufferPointer<Float>, send: UnsafeMutableBufferPointer<Float>) {
        if ghostRemaining > 0 {
            let count = min(ghostRemaining, output.count)
            for frame in 0..<count {
                var ring = ghost.process(0)
                if ghostDrive > 0 { ring = Self.overload(ring * ghostDrive) / ghostDrive }
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
            var burst: Float = 0
            if age < noiseLength {
                let time = Float(age)
                let along = time * noiseStep
                let left = 1 - along
                // A hit: fast in, then falling away to nothing at the end of the burst.
                var envelope = left * left * left * min(1, (time + 1) * noiseAttack)
                if noiseSwell > 0 {
                    // Something arriving: rising to its end, where it stops.
                    envelope += (along * along * min(1, left * noiseRelease) - envelope) * noiseSwell
                }
                if noiseGlide != 0, age & 31 == 0 {
                    band.retune(
                        .bandPass, frequency: min(noiseFrequency * expf(noiseGlide * along), rate * 0.4), q: noiseQ,
                        sampleRate: rate)
                }
                burst = band.process(noise.bipolar()) * envelope
                force += burst * noiseRing
            }
            var sample = modes.process(force)
            if drive > 0 { sample = Self.overload(sample * drive) / drive }
            sample = sample * amplitude + burst * noiseLevel
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
