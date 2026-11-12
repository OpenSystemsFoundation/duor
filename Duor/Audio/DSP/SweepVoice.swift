import Foundation

/// A tone that glides: a motor running up or winding down, or one soft note of a chime.
///
/// A strike rings at the pitch of what was hit, and noise through a narrow band only hints at a
/// pitch. A powered door needs a third kind of sound: a warm, steady tone that moves.
nonisolated struct SweepSpec: Sendable {
    /// Pitch in Hz at the start and at the end. Equal for a note.
    var from: Float
    var to: Float
    /// Seconds from start to silence.
    var duration: Float
    var amplitude: Float
    /// Seconds to fade in and out. Both are smooth curves, so even a short tone never clicks.
    var attack: Float = 0.02
    var release: Float = 0.08
    /// Seconds to wait before it starts.
    var delay: Float = 0
    /// Overtones on the sine (0 = pure): the second harmonic at this level, the third at its
    /// square. A little makes a motor instead of a whistle, and lets a phone speaker hint at a
    /// tone whose fundamental it cannot play.
    var harmonics: Float = 0.25
    /// A slow throb in the level (0 = steady, 1 = down to nothing), a few dozen times a second:
    /// the turning of a motor, where a steady tone would be a test signal.
    var throb: Float = 0
    /// How the pitch gets there: 0 moves evenly (by the same interval in the same time), 1 makes
    /// most of the move at the start and then settles, the way a motor reaches its speed.
    var settle: Float = 0
    var reverbSend: Float = 0.6
}

/// Plays one `SweepSpec`: a sine with two overtones whose pitch moves from one frequency to
/// another.
///
/// Stable by construction: a phase counter and a sine, no feedback.
nonisolated struct SweepVoice: Sendable {
    private(set) var isActive = false
    private var delay = 0
    private var age = 0
    private var length = 1
    private var phase: Float = 0
    private var step: Float = 0
    private var startFrequency: Float = 0
    /// Natural logarithm of how far the pitch moves.
    private var glide: Float = 0
    private var amplitude: Float = 0
    private var second: Float = 0
    private var third: Float = 0
    private var attackStep: Float = 0
    private var releaseStep: Float = 0
    private var settle: Float = 0
    private var throb: Float = 0
    private var throbPhase: Float = 0
    private var throbStep: Float = 0
    private var reverbSend: Float = 0
    private var rate: Float = 48_000

    // What this voice was playing when it was stolen, fading out under the new tone.
    private var ghostPhase: Float = 0
    private var ghostStep: Float = 0
    private var ghostGain: Float = 0
    private var ghostFade: Float = 0
    private var ghostSecond: Float = 0
    private var ghostThird: Float = 0
    private var ghostSend: Float = 0

    /// The longest a tone may be, in seconds.
    static let longest: Float = 2
    /// Turns of the throb per second.
    static let throbRate: Float = 31
    /// A stolen voice fades over this long instead of being cut dead, which would click.
    static let stealFade: Float = 0.004

    /// How much of its tone this voice has left, 0 (silent) ... 1 (just started), and more than 1
    /// while it still waits for its delay. The voice with the least left is the one to steal.
    var lifeLeft: Float {
        guard isActive else { return 0 }
        return Float(length - age) / Float(length) + (delay > 0 ? 1 : 0)
    }

    mutating func start(_ spec: SweepSpec, sampleRate: Float) {
        if isActive, age > 0 {
            ghostPhase = phase
            ghostStep = step
            ghostGain = amplitude * envelope()
            ghostFade = ghostGain / max(1, Self.stealFade * sampleRate)
            ghostSecond = second
            ghostThird = third
            ghostSend = reverbSend
        }
        isActive = false
        guard spec.from.isFinite, spec.to.isFinite, spec.duration.isFinite, spec.amplitude.isFinite,
            spec.duration > 0, spec.amplitude != 0
        else { return }

        rate = sampleRate
        let top = sampleRate * 0.2
        startFrequency = min(max(spec.from, 20), top)
        glide = logf(min(max(spec.to, 20), top) / startFrequency)
        length = max(8, Int(min(spec.duration, Self.longest) * sampleRate))
        delay = spec.delay.isFinite ? Int(min(max(spec.delay, 0), Self.longest) * sampleRate) : 0
        age = 0
        phase = 0
        step = startFrequency / sampleRate
        amplitude = min(max(spec.amplitude, -4), 4)
        second = spec.harmonics.isFinite ? min(max(spec.harmonics, 0), 1) : 0
        third = second * second
        // Fading in and out never takes more than the tone has.
        let attack = spec.attack.isFinite ? min(max(spec.attack, 0.001), spec.duration * 0.5) : 0.001
        let release = spec.release.isFinite ? min(max(spec.release, 0.002), spec.duration - attack) : 0.002
        attackStep = 1 / max(1, attack * sampleRate)
        releaseStep = 1 / max(1, release * sampleRate)
        throb = spec.throb.isFinite ? min(max(spec.throb, 0), 1) : 0
        throbPhase = 0
        settle = spec.settle.isFinite ? min(max(spec.settle, 0), 1) : 0
        throbStep = Self.throbRate / sampleRate
        reverbSend = spec.reverbSend.isFinite ? min(max(spec.reverbSend, 0), 2) : 0
        isActive = true
    }

    /// The fade in and out at this voice's age: smooth at both ends of both.
    @inline(__always)
    private func envelope() -> Float {
        let rise = min(Float(age) * attackStep, 1)
        let fall = min(Float(length - age) * releaseStep, 1)
        return rise * rise * (3 - 2 * rise) * fall * fall * (3 - 2 * fall)
    }

    /// A sine of `phase` turns with its second and third harmonics, from one call to `sinf`:
    /// cos 2x = 1 - 2 sin² x and sin 3x = 3 sin x - 4 sin³ x.
    @inline(__always)
    private static func wave(_ phase: Float, second: Float, third: Float) -> Float {
        let sine = sinf(2 * Float.pi * phase)
        let square = sine * sine
        return sine + second * (1 - 2 * square) + third * sine * (3 - 4 * square)
    }

    /// Adds this voice to `output`, and to `send` scaled by its reverb send.
    mutating func render(into output: UnsafeMutableBufferPointer<Float>, send: UnsafeMutableBufferPointer<Float>) {
        if ghostGain > 0 {
            for frame in output.indices {
                ghostGain -= ghostFade
                if ghostGain <= 0 {
                    ghostGain = 0
                    break
                }
                ghostPhase += ghostStep
                if ghostPhase >= 1 { ghostPhase -= 1 }
                let sample = Self.wave(ghostPhase, second: ghostSecond, third: ghostThird) * ghostGain
                output[frame] += sample
                send[frame] += sample * ghostSend
            }
        }
        guard isActive else { return }
        if delay >= output.count {
            delay -= output.count
            return
        }
        var frame = delay
        delay = 0
        while frame < output.count {
            if age & 15 == 0 {
                // Evenly, or most of the way in the first third and then settling: 1 - (1 - x)³.
                let along = Float(age) / Float(length)
                let left = 1 - along
                let moved = along + (1 - left * left * left - along) * settle
                step = startFrequency * expf(glide * moved) / rate
            }
            phase += step
            if phase >= 1 { phase -= 1 }
            var gain = amplitude * envelope()
            if throb > 0 {
                throbPhase += throbStep
                if throbPhase >= 1 { throbPhase -= 1 }
                // A triangle between 1 - throb and 1.
                gain *= 1 - throb * abs(2 * throbPhase - 1)
            }
            let sample = Self.wave(phase, second: second, third: third) * gain
            output[frame] += sample
            send[frame] += sample * reverbSend
            age += 1
            if age >= length {
                isActive = false
                return
            }
            frame += 1
        }
    }
}
