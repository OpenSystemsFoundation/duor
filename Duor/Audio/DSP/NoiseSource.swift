/// Fast, allocation-free pseudo-random numbers (xorshift32) for the audio thread.
/// Seeded, so renders are reproducible in tests.
nonisolated struct NoiseSource: Sendable {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed == 0 ? 0x9E37_79B9 : seed
    }

    mutating func nextUInt() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// Uniform in -1...1.
    mutating func bipolar() -> Float {
        Float(Int32(bitPattern: nextUInt())) / Float(Int32.max)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Float {
        Float(nextUInt() >> 8) / Float(1 << 24)
    }

    mutating func value(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }
}
