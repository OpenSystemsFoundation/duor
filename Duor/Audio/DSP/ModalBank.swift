import Foundation

/// Up to eight vibration modes of a physical object, run side by side in SIMD lanes.
///
/// Each lane is a two-pole resonator that rings at its frequency and fades with its decay time
/// after being struck. A lane's impulse response is `r^n · sin((n+1)ω) / sin ω`, so the input is
/// scaled by `sin ω` to give every mode a peak of about its gain, whatever its frequency.
nonisolated struct ModalBank: Sendable {
    private var a1 = SIMD8<Float>()
    private var a2 = SIMD8<Float>()
    private var inputGain = SIMD8<Float>()
    private var y1 = SIMD8<Float>()
    private var y2 = SIMD8<Float>()

    /// Sets one mode without clearing its current ring, so it can be retuned while sounding.
    /// - Parameter decay: Seconds to fall to 1/e (about -8.7 dB).
    mutating func tune(lane: Int, frequency: Float, decay: Float, gain: Float, sampleRate: Float) {
        let frequency = min(max(frequency, 20), sampleRate * 0.45)
        let omega = 2 * Float.pi * frequency / sampleRate
        let radius = expf(-1 / (max(decay, 0.0005) * sampleRate))
        a1[lane] = 2 * radius * cosf(omega)
        a2[lane] = -radius * radius
        inputGain[lane] = gain * sinf(omega)
    }

    mutating func silence() {
        y1 = .zero
        y2 = .zero
    }

    @inline(__always)
    mutating func process(_ input: Float) -> Float {
        let output = a1 * y1 + a2 * y2 + inputGain * input
        y2 = y1
        y1 = output
        return output.sum()
    }
}

/// Frequency, decay and loudness of one mode, used to describe a material.
nonisolated struct ModeSpec: Sendable {
    var frequency: Float
    /// Seconds to fall to 1/e.
    var decay: Float
    var gain: Float

    init(_ frequency: Float, _ decay: Float, _ gain: Float) {
        self.frequency = frequency
        self.decay = decay
        self.gain = gain
    }
}

/// The modes that give a struck object its character: one per lane of a `ModalBank`. Fixed size so
/// voices never allocate. Metal parts spend two of the eight on close-spaced pairs, which beat
/// slowly against each other the way a struck plate or bolt shimmers.
typealias ModeSet = InlineArray<8, ModeSpec>
