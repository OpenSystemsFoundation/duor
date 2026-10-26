import Foundation

/// How a hinge creaks.
nonisolated struct CreakProfile: Sendable {
    /// Squeal resonances of the hinge and door.
    var formants: InlineArray<4, ModeSpec>
    /// Low groan of the door body.
    var body: InlineArray<3, ModeSpec>
    /// Hinge speed (degrees per second) where the creak starts, and where it is at full strength.
    var onsetSpeed: Float
    var fullSpeed: Float
    /// Stick-slip events per second at rest, and added per degree per second of hinge speed.
    var baseRate: Float
    var ratePerDegree: Float
    var maxRate: Float
    /// Slow random pitch drift (fraction), the "wobble" of a real creak.
    var wander: Float
    /// Random timing variation per slip (fraction). Adds roughness.
    var jitter: Float
    /// Friction noise mixed in with the slips.
    var hiss: Float
    /// Formants rise by this fraction at full strength.
    var brighten: Float
    /// Formant scale while closing; doors sound slightly different in each direction.
    var closingPitch: Float
    var level: Float
}

/// A continuous hinge creak from a stick-slip friction model.
///
/// A creak is a hinge pin that repeatedly sticks, builds up tension, and slips. Each slip is an
/// impulse; the slip rate rises with hinge speed (that's the pitch), and the impulses ring the
/// hinge and door resonances (that's the timbre). At low speed the grip is unreliable, so slips
/// drop out and the creak sputters into separate ticks.
nonisolated struct CreakVoice: Sendable {
    private let sampleRate: Float
    private var profile: CreakProfile
    private var noise: NoiseSource

    private var targetVelocity: Float = 0
    private var velocity: Float = 0
    private let velocitySmoothing: Float
    private var intensity: Float = 0

    private var phase: Float = 0
    private var jitter: Float = 1
    private var wander: Float = 0
    private var wanderTarget: Float = 0
    private let wanderSmoothing: Float
    private var wanderCountdown = 0
    private var controlCountdown = 0

    /// Lanes 0–3 are the squeal formants, lanes 4–6 the body groan.
    private var resonances = ModalBank()

    /// Samples between filter retunes. Retuning per sample would waste time on trig.
    private static let controlInterval = 128

    init(profile: CreakProfile, sampleRate: Float, seed: UInt32) {
        self.profile = profile
        self.sampleRate = sampleRate
        noise = NoiseSource(seed: seed)
        velocitySmoothing = 1 - expf(-1 / (0.04 * sampleRate))
        wanderSmoothing = 1 - expf(-1 / (0.09 * sampleRate))
        retune()
    }

    mutating func setProfile(_ profile: CreakProfile) {
        self.profile = profile
        retune()
    }

    /// Signed hinge velocity in degrees per second. Positive opens.
    mutating func setTarget(velocity: Float) {
        targetVelocity = velocity
    }

    /// Adds the creak to `output` and, at full level, to the reverb `send`.
    mutating func render(into output: UnsafeMutableBufferPointer<Float>, send: UnsafeMutableBufferPointer<Float>) {
        let span = max(profile.fullSpeed - profile.onsetSpeed, 1)
        for frame in output.indices {
            velocity += (targetVelocity - velocity) * velocitySmoothing
            let speed = abs(velocity)
            intensity = Self.smoothstep((speed - profile.onsetSpeed) / span)

            controlCountdown -= 1
            if controlCountdown <= 0 {
                controlCountdown = Self.controlInterval
                retune()
            }
            wanderCountdown -= 1
            if wanderCountdown <= 0 {
                wanderTarget = noise.bipolar() * profile.wander
                wanderCountdown = Int(sampleRate * noise.value(in: 0.08...0.3))
            }
            wander += (wanderTarget - wander) * wanderSmoothing

            var excitation: Float = 0
            if intensity > 0 {
                let rate = min((profile.baseRate + profile.ratePerDegree * speed) * (1 + wander), profile.maxRate)
                phase += rate / sampleRate * jitter
                if phase >= 1 {
                    phase -= 1
                    jitter = 1 + profile.jitter * noise.bipolar()
                    let grip = 0.3 + 0.7 * intensity
                    if noise.unit() < grip {
                        excitation = intensity * noise.value(in: 0.75...1)
                    }
                }
                excitation += noise.bipolar() * intensity * profile.hiss
            }

            let sample = resonances.process(excitation) * profile.level
            output[frame] += sample
            send[frame] += sample
        }
    }

    private mutating func retune() {
        let direction: Float = velocity < 0 ? profile.closingPitch : 1
        let scale = (1 + profile.brighten * intensity) * direction
        for index in profile.formants.indices {
            let mode = profile.formants[index]
            resonances.tune(
                lane: index, frequency: mode.frequency * scale, decay: mode.decay, gain: mode.gain,
                sampleRate: sampleRate)
        }
        for index in profile.body.indices {
            let mode = profile.body[index]
            resonances.tune(
                lane: profile.formants.count + index, frequency: mode.frequency, decay: mode.decay, gain: mode.gain,
                sampleRate: sampleRate)
        }
    }

    private static func smoothstep(_ value: Float) -> Float {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
