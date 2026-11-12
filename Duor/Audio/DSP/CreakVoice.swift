import Foundation

/// A steady motor hum instead of a creak: a pulse train whose pitch follows the hinge speed.
/// Only the spaceship has one. It is meant to be tonal.
nonisolated struct ServoHum: Sendable {
    /// Pulses per second at rest, and added per degree per second of hinge speed.
    var baseRate: Float
    var ratePerDegree: Float
    var maxRate: Float
    /// Hinge speed (degrees per second) where the hum is at full strength.
    var fullSpeed: Float = 45
    /// Slow random pitch drift (fraction).
    var wander: Float = 0.015
    /// Random timing variation per pulse (fraction).
    var jitter: Float = 0.002
    /// Resonances rise by this fraction at full strength.
    var brighten: Float = 0.08
}

/// How a hinge creaks.
nonisolated struct CreakProfile: Sendable {
    /// The scrape of the pin in its knuckle: short, quiet resonances that colour each slip.
    var formants: InlineArray<4, ModeSpec>
    /// The door body the slips ring. This is where the creak's pitch comes from, so it stays the
    /// same whatever the hand does.
    var body: InlineArray<4, ModeSpec>
    /// Hinge speed (degrees per second) below which nothing is heard: sensor jitter of a door held still.
    var onsetSpeed: Float = 3
    /// Degrees the door travels between two slips, at full grip and moved slowly. Larger is a
    /// slower, heavier creak of separate knocks; smaller a finer rasp.
    var stickDistance: Float = 1.5
    /// Hinge speed at which the pin holds half as long: slips come twice as often per degree and
    /// each releases half as much. Faster movement is a soft rasp instead of separate slips.
    var easeSpeed: Float = 60
    /// Above this speed the surfaces start to slide without sticking, and at `slideFullSpeed` no
    /// slips are left, only friction noise.
    var slideSpeed: Float = 80
    var slideFullSpeed: Float = 220
    /// Seconds one slip takes. Drawn per slip: short slips are brighter, long ones duller.
    var pulse: ClosedRange<Float> = 0.0006...0.002
    /// Grit on each slip (0 = smooth, 1 = gritty).
    var roughness: Float = 0.5
    /// The pin sliding for a moment after it lets go: a noise tail on every slip, as strong as the
    /// slip itself at 1, fading over `scrapeDecay` seconds. It is what keeps a slip from ringing
    /// the door like a clean knock.
    var scrape: Float = 1
    var scrapeDecay: Float = 0.012
    /// How much of that sliding noise is heard directly, as a broad soft band up to
    /// `raspFrequency`, instead of through the resonances. Dry wood on a dry pin is mostly this.
    var rasp: Float = 48
    var raspFrequency: Float = 2_800
    /// Everything below this (Hz) is rolled off. Slips push one way, so without it every slip
    /// carries a thump under the door's lowest mode: mud on headphones, nothing on a phone.
    var lowCut: Float = 160
    /// Friction noise of the surfaces sliding, under and after the slips.
    var hiss: Float = 0.02
    /// How strongly the loudness follows the friction map: 1 is proportional to the grip, higher
    /// keeps the creak to the tight spots.
    var gripCurve: Float = 1.5
    /// Squeal (0 = never): when the slips come about as fast as a body mode vibrates, they fall in
    /// step with it and the mode sings for a moment. Metal doors do this, wood doesn't.
    var squeal: Float = 0
    /// Formant scale while closing; doors sound slightly different in each direction.
    var closingPitch: Float = 0.94
    var level: Float
    /// A motor hum instead of stick-slip (the spaceship).
    var servo: ServoHum?
    /// Where along the swing the hinge grips (its tight spots).
    var friction = FrictionMap.uniform(1)
}

/// The sound of a hinge pin that sticks, builds up tension, and slips.
///
/// Tension builds with the distance the door moves. When it passes a threshold the pin slips: one
/// short, shaped pulse into the door's resonances, as loud as the tension it released. The
/// threshold is drawn again for every slip and follows the friction map, so:
///
/// - moved slowly, the door gives a few strong slips you can almost count;
/// - moved faster, many weak ones that blur into a soft rasp, and above the door's slide speed
///   only a little friction noise;
/// - stopped mid-stick it is silent, and coasting to rest the last slips come further apart;
/// - it creaks at the door's tight spots, the same ones every swing.
///
/// The pitch is the door's (the body modes), never the hand's: slips come at random intervals, so
/// their rate is heard as roughness and not as a note.
///
/// A slip is not a clean knock either. After it lets go the pin slides for a moment, which is
/// noise: through the resonances (`scrape`) and heard directly as a soft broad band (`rasp`).
/// Dry wood is mostly that noise with the door's colour on it. Without it every slip rings the
/// same few modes, and a row of them is a tone again, only a different one.
///
/// Unconditionally stable: an accumulator and fixed resonators, nothing is solved per sample.
nonisolated struct CreakVoice: Sendable {
    private let sampleRate: Float
    private var profile: CreakProfile
    private var noise: NoiseSource

    // Control, updated every `controlInterval` samples.
    private var targetVelocity: Float = 0
    private var targetAngle: Float = 0
    private var velocity: Float = 0
    private var angle: Float = 0
    private var hasAngle = false
    private let riseGlide: Float
    private let fallGlide: Float
    private let angleGlide: Float
    private var controlCountdown = 0
    /// Degrees travelled per sample that count toward tension.
    private var travel: Float = 0
    /// Mean degrees between slips right now (grip and speed applied).
    private var meanThreshold: Float = 1
    /// Loudness of a slip that releases `stickDistance` degrees.
    private var slipGain: Float = 0
    private var noiseGain: Float = 0
    private var slipRate: Float = 0
    /// Samples between slips while the slips are in step with a body mode; 0 when they are not.
    private var lockPeriod: Float = 0
    private var formantScale: Float = 1

    // Slips.
    private var tension: Float = 0
    private var threshold: Float = 1
    private var sinceSlip: Float = 0
    private var lockWait: Float = 0
    private var lockLate: Float = 0
    private var pulseRemaining = 0
    private var pulseValue: Float = 0
    private var pulsePrevious: Float = 0
    private var pulseCoefficient: Float = 0
    private var scrapeLevel: Float = 0
    private var scrapeFade: Float = 0
    private var scrapeScale: Float = 0

    // Servo hum.
    private var intensity: Float = 0
    private var phase: Float = 0
    private var jitter: Float = 1
    private var wander: Float = 0
    private var wanderTarget: Float = 0
    private var wanderCountdown = 0

    /// Lanes 0–3 are the scrape formants, lanes 4–7 the door body.
    private var resonances = ModalBank()
    private var raspBand: Biquad
    /// One-pole low end of the creak, subtracted so it carries no rumble.
    private var low: Float = 0
    private var lowGlide: Float = 0
    /// Samples the resonances still ring after the last excitation. At 0 the voice costs nothing.
    private var ringRemaining = 0
    private var ringLength = 0

    /// Samples between control updates (0.33 ms at 48 kHz): often enough to be smooth, rare
    /// enough that the friction map and the glides cost nothing.
    private static let controlInterval = 16
    private static let maxSpeed: Float = 1_500

    init(profile: CreakProfile, sampleRate: Float, seed: UInt32) {
        self.profile = profile
        self.sampleRate = sampleRate
        noise = NoiseSource(seed: seed)
        let step = Float(Self.controlInterval) / sampleRate
        // Speed follows the hinge quickly on the way up and lets go slowly, so a door that stops
        // gives its last slips further apart instead of being cut off. Both are plain glides in
        // time: nothing here knows how often the hinge reports.
        riseGlide = 1 - expf(-step / 0.035)
        fallGlide = 1 - expf(-step / 0.11)
        angleGlide = 1 - expf(-step / 0.12)
        threshold = profile.stickDistance
        raspBand = Biquad(.lowPass, frequency: profile.raspFrequency, q: 0.6, sampleRate: sampleRate)
        retune()
    }

    mutating func setProfile(_ profile: CreakProfile) {
        self.profile = profile
        raspBand = Biquad(.lowPass, frequency: profile.raspFrequency, q: 0.6, sampleRate: sampleRate)
        formantScale = 0
        retune()
    }

    /// Hinge angle in degrees and signed velocity in degrees per second. Positive opens.
    /// May be called at any rate; the voice glides between calls.
    mutating func setTarget(angle: Float, velocity: Float) {
        if angle.isFinite {
            targetAngle = min(max(angle, -30), 210)
            if !hasAngle {
                self.angle = targetAngle
                hasAngle = true
            }
        }
        targetVelocity = velocity.isFinite ? min(max(velocity, -Self.maxSpeed), Self.maxSpeed) : 0
    }

    /// Adds the creak to `output` and, at full level, to the reverb `send`.
    mutating func render(into output: UnsafeMutableBufferPointer<Float>, send: UnsafeMutableBufferPointer<Float>) {
        if targetVelocity == 0, abs(velocity) < 0.5, pulseRemaining == 0 {
            // At rest: let the resonances ring out, then cost nothing.
            velocity = 0
            travel = 0
            intensity = 0
            // A stopped door keeps no tension to release with a bang when it next moves.
            tension = 0
            controlCountdown = 0
            // Wherever the door was moved to without a sound, that is where it is now.
            angle = targetAngle
            guard ringRemaining > 0 else { return }
            for frame in output.indices {
                let sample = shaped(resonances.process(0), sliding: 0)
                output[frame] += sample
                send[frame] += sample
            }
            ringRemaining -= output.count
            if ringRemaining <= 0 {
                resonances.silence()
                low = 0
                scrapeLevel = 0
            }
            return
        }
        ringRemaining = ringLength
        if profile.servo != nil {
            renderServo(into: output, send: send)
        } else {
            renderSlips(into: output, send: send)
        }
    }

    // MARK: Stick-slip

    private mutating func renderSlips(
        into output: UnsafeMutableBufferPointer<Float>, send: UnsafeMutableBufferPointer<Float>
    ) {
        for frame in output.indices {
            controlCountdown -= 1
            if controlCountdown <= 0 {
                controlCountdown = Self.controlInterval
                updateControl()
            }

            var excitation: Float = 0
            sinceSlip += 1
            if pulseRemaining > 0 {
                excitation = pulseValue * (1 + profile.roughness * noise.bipolar())
                let next = pulseCoefficient * pulseValue - pulsePrevious
                pulsePrevious = pulseValue
                pulseValue = next
                pulseRemaining -= 1
            } else if slipGain > 0 {
                // While the pin is slipping it cannot stick, so tension only builds between slips.
                tension += travel
                if lockPeriod > 0 {
                    if sinceSlip >= lockWait, tension > 0 { slip(releasing: tension) }
                } else if tension >= threshold {
                    slip(releasing: threshold)
                }
            }
            let sliding = noise.bipolar() * (noiseGain + scrapeLevel)
            scrapeLevel *= scrapeFade
            excitation += sliding

            let sample = shaped(resonances.process(excitation), sliding: sliding)
            output[frame] += sample
            send[frame] += sample
        }
    }

    /// Glides speed and angle toward what the hinge last reported and works out, from the
    /// friction map, how the pin grips right now.
    private mutating func updateControl() {
        let towardRest = abs(targetVelocity) < abs(velocity) && targetVelocity * velocity >= 0
        velocity += (targetVelocity - velocity) * (towardRest ? fallGlide : riseGlide)
        // The angle moves on with the speed between reports, and is pulled gently to the reported
        // angle, so a slow or irregular feed doesn't make it step.
        let step = Float(Self.controlInterval) / sampleRate
        angle += velocity * step
        angle += (targetAngle - angle) * angleGlide

        let closing = velocity < 0
        let scale: Float = closing ? profile.closingPitch : 1
        if scale != formantScale {
            formantScale = scale
            retune()
        }

        let speed = max(abs(velocity) - profile.onsetSpeed, 0)
        travel = speed / sampleRate
        let grip = profile.friction.grip(at: angle, closing: closing)
        // A tight spot holds the pin longer, and each slip there is louder.
        let hold = (0.35 + 0.65 * grip) / (1 + speed / max(profile.easeSpeed, 1))
        meanThreshold = max(profile.stickDistance * hold, 1e-4)
        let slide =
            1 - Self.smoothstep((speed - profile.slideSpeed) / max(profile.slideFullSpeed - profile.slideSpeed, 1))
        let loudness = powf(grip, profile.gripCurve)
        slipGain = speed > 0 ? loudness * slide : 0
        if slipGain <= 0 { tension = 0 }
        // Friction noise comes in with speed and stays when the slips have gone.
        noiseGain = profile.hiss * loudness * min(speed / max(profile.slideSpeed, 1), 1.5)
        slipRate = speed / meanThreshold

        lockPeriod = 0
        if profile.squeal > 0, grip > 0.4 {
            // In step with the body mode nearest the slip rate, if one is near.
            var nearest: Float = 0
            var distance: Float = 0.5
            for index in profile.body.indices {
                let frequency = profile.body[index].frequency
                let apart = abs(slipRate / frequency - 1)
                if apart < distance {
                    distance = apart
                    nearest = frequency
                }
            }
            if nearest > 0 { lockPeriod = sampleRate / nearest }
        }
    }

    /// The pin lets go: starts one half-sine pulse, as loud as the tension released, and draws the
    /// next threshold.
    private mutating func slip(releasing released: Float) {
        tension = max(tension - released, 0)
        // Slow slips keep some rhythm, as a real creak does. Fast ones are drawn widely (an
        // exponential spread), because slips at regular intervals above 60 a second or so are
        // heard as a note that slides with the hand.
        let spread = min(max(slipRate / 60, 0.45), 1)
        let draw = min(-logf(max(noise.unit(), 1e-4)), 3)
        threshold = meanThreshold * max(1 + spread * (draw - 1), 0.08)
        if lockPeriod > 0 {
            // In step with the mode, a little loosely: a squeal that wavers, not a test tone. Each
            // slip is early or late against a steady beat (the lateness is not carried over), or
            // the slips would drift out of step within a few periods and nothing would sing.
            let late = (1 - profile.squeal) * 0.4 * lockPeriod * noise.bipolar()
            sinceSlip = min(max(sinceSlip - lockWait, 0), 1)
            lockWait = max(lockPeriod + late - lockLate, 2)
            lockLate = late
        } else {
            sinceSlip = 0
            lockWait = 0
            lockLate = 0
        }

        var seconds = noise.value(in: profile.pulse)
        if lockPeriod > 0 { seconds = min(seconds, 0.5 * lockPeriod / sampleRate) }
        let length = max(Int(seconds * sampleRate), 2)
        // A half-sine from a two-multiply oscillator, started half a step in. It sums to 2L/π;
        // normalized so the low modes see an impulse the size of the release whatever its length.
        let omega = Float.pi / Float(length)
        let strength = slipGain * released / max(profile.stickDistance, 1e-4)
        let amplitude = strength * omega * 0.5
        scrapeLevel = max(scrapeLevel, strength * scrapeScale)
        pulseCoefficient = 2 * cosf(omega)
        pulseValue = amplitude * sinf(0.5 * omega)
        pulsePrevious = -pulseValue
        pulseRemaining = length
    }

    /// Adds the sliding noise as heard directly (low-passed) to the ringing resonances, takes
    /// the bottom out, and applies the level.
    @inline(__always)
    private mutating func shaped(_ ringing: Float, sliding: Float) -> Float {
        let sum = ringing + raspBand.process(sliding) * profile.rasp
        low += (sum - low) * lowGlide
        return (sum - low) * profile.level
    }

    // MARK: Servo

    /// The 1.0 pulse train, for the spaceship: its rate rises with hinge speed (that's the pitch).
    private mutating func renderServo(
        into output: UnsafeMutableBufferPointer<Float>, send: UnsafeMutableBufferPointer<Float>
    ) {
        guard let servo = profile.servo else { return }
        let wanderSmoothing = 1 - expf(-1 / (0.09 * sampleRate))
        let span = max(servo.fullSpeed - profile.onsetSpeed, 1)
        var speed = abs(velocity)
        var grip: Float = 0
        var pulseLevel: Float = 1
        for frame in output.indices {
            controlCountdown -= 1
            if controlCountdown <= 0 {
                controlCountdown = Self.controlInterval
                let towardRest = abs(targetVelocity) < abs(velocity) && targetVelocity * velocity >= 0
                velocity += (targetVelocity - velocity) * (towardRest ? fallGlide : riseGlide)
                angle += (targetAngle - angle) * angleGlide
                speed = abs(velocity)
                grip = profile.friction.grip(at: angle, closing: velocity < 0)
                // Full strength at a slow to medium speed, easing off on a fast swing.
                let ease =
                    1 - 0.6
                    * Self.smoothstep(
                        (speed - profile.slideSpeed) / max(profile.slideFullSpeed - profile.slideSpeed, 1))
                intensity = Self.smoothstep((speed - profile.onsetSpeed) / span) * grip * ease
                // More pulses a second carry more power: keep the hum's loudness, not its pulse size.
                let rate = min(servo.baseRate + servo.ratePerDegree * speed, servo.maxRate)
                pulseLevel = (servo.baseRate / max(rate, 1)).squareRoot()
                // Retuning per sample would waste time on trig; a few hundred times a second is smooth.
                let direction: Float = velocity < 0 ? profile.closingPitch : 1
                let scale = (1 + servo.brighten * intensity) * direction
                if abs(scale - formantScale) > 0.002 {
                    formantScale = scale
                    retune()
                }
            }
            wanderCountdown -= 1
            if wanderCountdown <= 0 {
                wanderTarget = noise.bipolar() * servo.wander
                wanderCountdown = Int(sampleRate * noise.value(in: 0.08...0.3))
            }
            wander += (wanderTarget - wander) * wanderSmoothing

            var excitation: Float = 0
            if intensity > 0 {
                let rate = min((servo.baseRate + servo.ratePerDegree * speed) * (1 + wander), servo.maxRate)
                phase += rate / sampleRate * jitter
                if phase >= 1 {
                    phase -= 1
                    jitter = 1 + servo.jitter * noise.bipolar()
                    excitation = intensity * pulseLevel * noise.value(in: 0.75...1)
                }
                excitation += noise.bipolar() * intensity * profile.hiss
            }

            let sample = shaped(resonances.process(excitation), sliding: 0)
            output[frame] += sample
            send[frame] += sample
        }
    }

    // MARK: Resonances

    private mutating func retune() {
        if formantScale <= 0 { formantScale = 1 }
        lowGlide = 1 - expf(-2 * Float.pi * min(max(profile.lowCut, 10), 2_000) / sampleRate)
        let fade = max(profile.scrapeDecay, 0.001) * sampleRate
        scrapeFade = expf(-1 / fade)
        // Noise of this size puts as much energy into a mode as the slip's own pulse does.
        scrapeScale = profile.scrape * (12 / fade).squareRoot()
        var longest: Float = 0
        for index in profile.formants.indices {
            let mode = profile.formants[index]
            resonances.tune(
                lane: index, frequency: mode.frequency * formantScale, decay: mode.decay, gain: mode.gain,
                sampleRate: sampleRate)
            longest = max(longest, mode.decay)
        }
        for index in profile.body.indices {
            let mode = profile.body[index]
            resonances.tune(
                lane: profile.formants.count + index, frequency: mode.frequency, decay: mode.decay, gain: mode.gain,
                sampleRate: sampleRate)
            longest = max(longest, mode.decay)
        }
        // e^-10 is about -87 dB under an already quiet creak: gone, and before the resonators reach denormal numbers.
        ringLength = Int(min(longest, 2) * 10 * sampleRate)
    }

    private static func smoothstep(_ value: Float) -> Float {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
