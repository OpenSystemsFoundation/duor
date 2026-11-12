import Foundation

/// The quiet sound of a door moving, under the creak: air pushed by the leaf, and the hinge
/// knuckles rolling on their pin.
nonisolated struct SwingBedProfile: Sendable {
    /// Centre (Hz) and Q of the band the moving air is heard in. Heavier doors sit lower.
    var airFrequency: Float = 650
    var airQ: Float = 0.7
    /// Air level at `referenceSpeed`. It grows with the square of the speed and levels off above it.
    var airLevel: Float = 0.028
    /// Soft ticks of the hinge modes per degree of travel, and their level at `referenceSpeed`.
    var rollPerDegree: Float = 0.35
    var rollLevel: Float = 0.018
    /// Degrees per second where both are at their nominal level.
    var referenceSpeed: Float = 200
    /// Ring of the hinge ticks, relative to the hinge's own decay. Short: a knuckle rolling on
    /// its pin is a soft tick, and one that rings on turns a fast swing into a faint note.
    var rollDecay: Float = 0.14

    /// No bed at all.
    static let silent = SwingBedProfile(airLevel: 0, rollPerDegree: 0, rollLevel: 0)
}

/// A continuous "it moves" sound that rises with hinge speed, so the creak doesn't have to carry
/// all the motion and can stay in its tight spots. Real-time safe: fixed state, no allocation.
nonisolated struct SwingBedVoice: Sendable {
    private let sampleRate: Float
    private var profile: SwingBedProfile
    private var noise: NoiseSource
    private var airBand: Biquad
    private var airBand2: Biquad
    private var roll = ModalBank()

    private var targetSpeed: Float = 0
    private var speed: Float = 0
    private let glide: Float

    init(profile: SwingBedProfile, hinge: ModeSet, sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        self.profile = profile
        noise = NoiseSource(seed: seed)
        airBand = Biquad(.bandPass, frequency: profile.airFrequency, q: profile.airQ, sampleRate: sampleRate)
        airBand2 = Biquad(.bandPass, frequency: profile.airFrequency, q: profile.airQ, sampleRate: sampleRate)
        // Speed glides over about 60 ms, whatever the hinge update rate.
        glide = 1 - expf(-1 / (0.06 * sampleRate))
        tune(hinge: hinge)
    }

    mutating func setProfile(_ profile: SwingBedProfile, hinge: ModeSet) {
        self.profile = profile
        airBand = Biquad(.bandPass, frequency: profile.airFrequency, q: profile.airQ, sampleRate: sampleRate)
        airBand2 = Biquad(.bandPass, frequency: profile.airFrequency, q: profile.airQ, sampleRate: sampleRate)
        tune(hinge: hinge)
    }

    /// Signed hinge velocity in degrees per second.
    mutating func setTarget(velocity: Float) {
        targetSpeed = velocity.isFinite ? min(abs(velocity), 1_500) : 0
    }

    /// Adds the bed to `output` and all of it to the reverb `send`: the room is heard while the door moves.
    mutating func render(into output: UnsafeMutableBufferPointer<Float>, send: UnsafeMutableBufferPointer<Float>) {
        if targetSpeed == 0, speed < 0.01 {
            if speed > 0 {
                // The air is scaled after its filters, so their state is at full noise level: by
                // now the air is silent, so clear it rather than let it ring out unscaled (that
                // was a loud tick a moment after every swing).
                speed = 0
                airBand.reset()
                airBand2.reset()
            }
            // Let the last hinge ticks ring out.
            for frame in output.indices {
                let sample = roll.process(0)
                output[frame] += sample
                send[frame] += sample
            }
            return
        }
        let reference = max(profile.referenceSpeed, 1)
        let tickChance = profile.rollPerDegree / sampleRate
        for frame in output.indices {
            speed += (targetSpeed - speed) * glide
            let relative = min(speed / reference, 1.6)
            // Speed squared while the door moves slowly, levelling off on a fast swing: the air is
            // there on a normal swing and never takes over on a hard one.
            let square = relative * relative
            let air = airBand2.process(airBand.process(noise.bipolar())) * profile.airLevel * 8 * square / (1 + square)
            var tick: Float = 0
            if noise.unit() < tickChance * speed {
                tick = profile.rollLevel * min(relative, 1) * noise.value(in: 0.4...1)
            }
            let sample = air + roll.process(tick)
            output[frame] += sample
            send[frame] += sample
        }
    }

    private mutating func tune(hinge: ModeSet) {
        var previous: Float = 0
        for index in hinge.indices where index < 8 {
            let mode = hinge[index]
            // A tick this short is over before a close pair of modes could beat, so the second of
            // a pair only doubles the first: a louder, more pitched low end, and a roll that reads
            // as a faint note. Leave it out.
            let isPartner = previous > 0 && mode.frequency / previous < 1.04
            previous = mode.frequency
            roll.tune(
                lane: index, frequency: mode.frequency, decay: mode.decay * profile.rollDecay,
                gain: isPartner ? 0 : mode.gain, sampleRate: sampleRate)
        }
    }
}
