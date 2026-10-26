/// A small mono room (Schroeder/Freeverb style: parallel damped combs into series allpasses).
/// Gives the door a space to live in, like a hallway. All buffers are allocated up front.
nonisolated struct RoomReverb: Sendable {
    private struct Comb: Sendable {
        var buffer: [Float]
        var index = 0
        var feedback: Float
        var damping: Float
        var filtered: Float = 0

        mutating func process(_ input: Float) -> Float {
            let output = buffer[index]
            filtered = output * (1 - damping) + filtered * damping
            buffer[index] = input + filtered * feedback
            index += 1
            if index == buffer.count { index = 0 }
            return output
        }
    }

    private struct Allpass: Sendable {
        var buffer: [Float]
        var index = 0

        mutating func process(_ input: Float) -> Float {
            let delayed = buffer[index]
            buffer[index] = input + delayed * 0.5
            index += 1
            if index == buffer.count { index = 0 }
            return delayed - input
        }
    }

    private var combs: [Comb]
    private var allpasses: [Allpass]
    /// Wet level added to the dry signal.
    var mix: Float

    /// - Parameters:
    ///   - size: Comb feedback (0...0.95). Larger is a longer tail.
    ///   - damping: High-frequency loss per echo (0...1). Larger is a duller room.
    init(sampleRate: Float, size: Float = 0.8, damping: Float = 0.4, mix: Float) {
        // Freeverb's tunings, given in samples at 44.1 kHz.
        let scale = sampleRate / 44_100
        func silence(_ length: Int) -> [Float] {
            [Float](repeating: 0, count: max(1, Int(Float(length) * scale)))
        }
        combs = [1116, 1188, 1277, 1356].map { Comb(buffer: silence($0), feedback: size, damping: damping) }
        allpasses = [556, 441].map { Allpass(buffer: silence($0)) }
        self.mix = mix
    }

    mutating func process(_ input: Float) -> Float {
        let scaled = input * 0.2
        var wet: Float = 0
        for index in combs.indices {
            wet += combs[index].process(scaled)
        }
        for index in allpasses.indices {
            wet = allpasses[index].process(wet)
        }
        return wet * mix
    }
}
