import Foundation

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
}

/// Plays one impact: a half-sine contact force driving a bank of modal resonators.
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
    private var modes = ModalBank()
    private var noise = NoiseSource(seed: 1)

    /// Samples until this voice falls silent. Used to steal the voice closest to finishing.
    var remaining: Int { isActive ? delay + lifetime - age : 0 }

    mutating func start(_ spec: ImpactSpec, sampleRate: Float, random: inout NoiseSource) {
        delay = Int(spec.delay * sampleRate)
        age = 0
        contactLength = max(1, Int(spec.contactTime * sampleRate))
        // A half-sine pulse sums to 2L/π; normalize so the low modes see a unit impulse.
        pulseNormalization = Float.pi / (2 * Float(contactLength))
        roughness = spec.roughness
        amplitude = spec.amplitude
        reverbSend = spec.reverbSend
        noise = NoiseSource(seed: random.nextUInt())

        var longestDecay: Float = 0
        modes.silence()
        for index in spec.modes.indices {
            let mode = spec.modes[index]
            let decay = mode.decay * spec.decayScale * (1 + 0.1 * random.bipolar())
            let frequency = mode.frequency * spec.pitchScale * (1 + spec.detune * random.bipolar())
            modes.tune(lane: index, frequency: frequency, decay: decay, gain: mode.gain, sampleRate: sampleRate)
            longestDecay = max(longestDecay, decay)
        }
        // e^-7 is about -60 dB: inaudible.
        lifetime = contactLength + Int(longestDecay * 7 * sampleRate)
        isActive = true
    }

    /// Adds this voice to `output`, and to `send` scaled by its reverb send.
    mutating func render(into output: UnsafeMutableBufferPointer<Float>, send: UnsafeMutableBufferPointer<Float>) {
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
            let sample = modes.process(force) * amplitude
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
