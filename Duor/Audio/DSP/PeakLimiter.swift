import Foundation

/// Keeps the mix under a ceiling without changing its shape: when a peak is coming, the gain
/// is already on its way down by the time the peak arrives, and comes back over about 80 ms.
///
/// The loudness of the door used to come from the soft clipper at the end of the chain, which
/// squashed the top of every hit. With the limiter in front of it a single sound passes clean, and
/// stacked sounds (a slam with everything rattling) are turned down as a whole instead of being
/// waveshaped. The clipper stays behind it as a safety net.
///
/// How: the signal is delayed by a short lookahead. The gain each sample needs is held for that
/// long and averaged over it, so the delayed peak always meets a gain small enough for it: the
/// output never passes the ceiling. Fixed state, no allocation.
nonisolated struct PeakLimiter: Sendable {
    /// Longest lookahead in samples (1.5 ms fits up to 96 kHz).
    private static let capacity = 160

    let ceiling: Float
    /// Samples the output runs behind the input.
    let lookahead: Int

    private var delayed = InlineArray<160, Float>(repeating: 0)
    private var gains = InlineArray<160, Float>(repeating: 1)
    private var index = 0
    private var gainSum: Float
    private var envelope: Float = 0
    private var hold = 0
    private let release: Float
    /// How far the envelope falls over one lookahead.
    private let holdGuard: Float

    /// The gain applied to the last sample: 1 when idle, lower while limiting.
    private(set) var gain: Float = 1

    init(sampleRate: Float, ceiling: Float = 1, lookahead: Float = 0.0015, release: Float = 0.08) {
        self.ceiling = max(ceiling, 0.001)
        self.lookahead = min(max(Int(lookahead * sampleRate), 1), Self.capacity)
        self.release = expf(-1 / (max(release, 0.001) * sampleRate))
        holdGuard = powf(self.release, Float(self.lookahead))
        gainSum = Float(self.lookahead)
    }

    /// One sample in, the sample from `lookahead` ago out. Real-time safe.
    mutating func process(_ input: Float) -> Float {
        let input = input.isFinite ? input : 0
        let level = abs(input)
        if level >= envelope * holdGuard {
            // Loud enough that the falling envelope could dip under it before it comes out of the
            // delay: stay put until it has.
            envelope = max(envelope, level)
            hold = lookahead
        } else if hold > 0 {
            hold -= 1
        } else {
            envelope *= release
        }
        let needed = envelope > ceiling ? ceiling / envelope : 1

        let output = delayed[index]
        delayed[index] = input
        gainSum += needed - gains[index]
        gains[index] = needed
        index += 1
        if index == lookahead {
            index = 0
            // Start each lap from an exact sum, so rounding never builds up.
            var sum: Float = 0
            for slot in 0..<lookahead { sum += gains[slot] }
            gainSum = sum
        }
        gain = min(gainSum / Float(lookahead), 1)
        return output * gain
    }
}
