import Foundation

/// A room for the door to sound in: a pre-delay, a few separate early reflections, and a tail
/// from an eight-line feedback delay network.
///
/// The tail: eight delay lines of unrelated lengths feed back into each other through a mixing
/// matrix that loses no energy (a Householder reflection), so echoes multiply into a dense wash
/// instead of the repeating ring of a few combs. Each line loses a little per pass, set from the
/// decay time, and loses its highs a little faster, set from the damping. Two short allpasses
/// smear the sound on its way in.
///
/// Stable whatever it is given: every loss is below 1 and the mixing adds nothing, parameters are
/// clamped, and input that is not a number is dropped. All memory is allocated in `init`;
/// `process` never allocates. Changing the room fades the old one out and the new one in over a
/// few milliseconds, so it never clicks.
nonisolated struct RoomReverb: Sendable {
    /// Largest room the buffers are sized for (see `RoomAcoustics.size`).
    static let maximumSize: Float = 3
    /// Line lengths in seconds at size 1: spread so that no two are a simple ratio apart.
    private static let lineTimes: SIMD8<Float> = [0.0113, 0.0137, 0.0163, 0.0191, 0.0217, 0.0241, 0.0277, 0.0313]
    private static let allpassTimes: SIMD2<Float> = [0.0047, 0.0071]
    /// Where `RoomAcoustics.damping` is measured: the tail at this frequency (Hz) lasts
    /// `1 - damping` of the decay time, less above, more below.
    static let dampingFrequency: Float = 4_000
    /// Fade when the room changes, each way.
    private static let fadeTime: Float = 0.012

    private let sampleRate: Float
    /// Pre-delay and early taps, the two allpasses, then the eight lines, back to back.
    private var storage: [Float]
    private let tapMask: Int
    private let allpassStart: SIMD2<Int>
    private let allpassCapacity: SIMD2<Int>
    private let lineStart: SIMD8<Int>
    private let lineCapacity: SIMD8<Int>

    private var acoustics: RoomAcoustics
    /// The room to change to once the current one has faded out.
    private var pending: RoomAcoustics?
    /// 1 normally; ramps to 0 and back around a change of room.
    private var fade: Float = 1
    private let fadeStep: Float

    // Tuned from `acoustics`.
    private var tapWrite = 0
    private var preDelay = 1
    private var earlyDelay = SIMD4<Int>(repeating: 1)
    private var earlyGain = SIMD4<Float>()
    private var allpassLength = SIMD2<Int>(repeating: 1)
    private var allpassPosition = SIMD2<Int>()
    private var diffusion: Float = 0
    private var lineLength = SIMD8<Int>(repeating: 1)
    private var linePosition = SIMD8<Int>()
    private var lineGain = SIMD8<Float>()
    private var lineDamping = SIMD8<Float>()
    private var filtered = SIMD8<Float>()
    private var tailGain: Float = 0

    /// Samples of silence in, after which the tail is far below hearing and the room can sleep.
    private var sleepAfter = 0
    private var quiet = 0
    private var isAsleep = true

    /// Alternating signs spread the input over the lines and decorrelate their sum.
    private static let signs: SIMD8<Float> = [1, -1, 1, -1, 1, -1, 1, -1]

    init(sampleRate: Float, acoustics: RoomAcoustics) {
        let sampleRate = max(sampleRate, 8_000)
        self.sampleRate = sampleRate
        self.acoustics = acoustics
        fadeStep = 1 / (Self.fadeTime * sampleRate)

        // A power of two for the tapped delay, so taps wrap with a mask.
        var tapCapacity = 1
        while Float(tapCapacity) < 0.26 * sampleRate { tapCapacity *= 2 }
        tapMask = tapCapacity - 1
        var offset = tapCapacity
        var allpassStart = SIMD2<Int>()
        var allpassCapacity = SIMD2<Int>()
        for index in 0..<2 {
            allpassStart[index] = offset
            allpassCapacity[index] = Int(Self.allpassTimes[index] * Self.maximumSize * sampleRate) + 2
            offset += allpassCapacity[index]
        }
        var lineStart = SIMD8<Int>()
        var lineCapacity = SIMD8<Int>()
        for index in 0..<8 {
            lineStart[index] = offset
            lineCapacity[index] = Int(Self.lineTimes[index] * Self.maximumSize * sampleRate) + 2
            offset += lineCapacity[index]
        }
        self.allpassStart = allpassStart
        self.allpassCapacity = allpassCapacity
        self.lineStart = lineStart
        self.lineCapacity = lineCapacity
        storage = [Float](repeating: 0, count: offset)
        tune()
    }

    /// Changes the room. If it differs from the current one, the old tail fades out first.
    mutating func setAcoustics(_ new: RoomAcoustics) {
        if new == acoustics {
            pending = nil
        } else if isAsleep {
            // Nothing is sounding: just move.
            acoustics = new
            tune()
        } else {
            pending = new
        }
    }

    /// Sets every coefficient from `acoustics`. Parameters are clamped to what stays stable and
    /// fits the buffers.
    private mutating func tune() {
        func finite(_ value: Float, _ fallback: Float) -> Float { value.isFinite ? value : fallback }
        let size = min(max(finite(acoustics.size, 1), 0.1), Self.maximumSize)
        let decay = min(max(finite(acoustics.decay, 0.3), 0.02), 20)
        // Highs last this share of the time the lows do.
        let highs = min(max(1 - finite(acoustics.damping, 0.5), 0.05), 1)
        diffusion = min(max(finite(acoustics.diffusion, 0), 0), 0.75)

        let longest = tapMask
        preDelay = min(max(Int(finite(acoustics.preDelay, 0) * sampleRate), 1), longest)
        for index in 0..<4 {
            let tap = acoustics.early[index]
            earlyDelay[index] = min(max(Int(finite(tap.time, 0) * sampleRate), 1), longest)
            earlyGain[index] = min(max(finite(tap.gain, 0), -2), 2)
        }
        for index in 0..<2 {
            allpassLength[index] = min(
                max(Int(Self.allpassTimes[index] * size * sampleRate), 2), allpassCapacity[index])
            allpassPosition[index] = 0
        }
        var total = 0
        let turn = cosf(2 * Float.pi * min(Self.dampingFrequency, sampleRate * 0.4) / sampleRate)
        for index in 0..<8 {
            // Odd lengths share fewer factors.
            let length = min(max(Int(Self.lineTimes[index] * size * sampleRate) | 1, 3), lineCapacity[index])
            lineLength[index] = length
            linePosition[index] = 0
            total += length
            // Loss per pass that adds up to 60 dB over the decay time, and (after Jot) a one-pole
            // low-pass that takes the extra loss the highs need at `dampingFrequency` to get there
            // in their shorter time. Its pole solves |H|² = extra² for H = (1-b)/(1-b/z); both the
            // gain and the pole are below 1 by construction.
            let gain = min(powf(10, -3 * Float(length) / (decay * sampleRate)), 0.9999)
            lineGain[index] = gain
            let extra = powf(gain, 1 / highs - 1)
            let rest = 1 - extra * extra
            var pole: Float = 0
            if rest > 1e-6 {
                let middle = 1 - extra * extra * turn
                pole = (middle - max(middle * middle - rest * rest, 0).squareRoot()) / rest
            }
            lineDamping[index] = min(max(pole, 0), 0.98)
        }
        filtered = .zero
        // A click spreads over all the lines, so each output sample starts with a power of about
        // 1/(their total length), and that falls 60 dB over the decay time (a factor e every
        // decay/13.8). This brings the tail's total energy to `tail`² whatever the size and decay.
        let energy = decay * sampleRate / (13.8 * Float(total))
        tailGain = min(max(finite(acoustics.tail, 0), 0), 4) / max(energy, 0.01).squareRoot()
        sleepAfter = Int((decay * 2.2 + 0.4) * sampleRate)
    }

    private mutating func clear() {
        storage.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        filtered = .zero
        tapWrite = 0
    }

    /// Adds the room's answer to `input` into `output` (same length). The input is scaled by a gain
    /// that moves from `gainStart` to `gainEnd` across the buffer: how much of the sound goes into
    /// this room. Scaling what goes in rather than what comes out lets a tail ring on undisturbed
    /// while the gain changes.
    mutating func process(
        _ input: UnsafeMutableBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>,
        gainStart: Float = 1, gainEnd: Float = 1
    ) {
        let count = min(input.count, output.count)
        guard count > 0 else { return }
        let gainStart = gainStart.isFinite ? gainStart : 0
        let gainEnd = gainEnd.isFinite ? gainEnd : 0

        // Asleep until something worth hearing comes in.
        var hasInput = false
        if gainStart != 0 || gainEnd != 0 {
            for frame in 0..<count where !(abs(input[frame]) < 1e-9) {
                hasInput = true
                break
            }
        }
        if isAsleep {
            if let next = pending {
                acoustics = next
                pending = nil
                tune()
            }
            guard hasInput else { return }
            isAsleep = false
            quiet = 0
        } else if hasInput {
            quiet = 0
        } else {
            quiet += count
            if quiet > sleepAfter, pending == nil {
                clear()
                isAsleep = true
                fade = 1
                return
            }
        }

        let gainStep = (gainEnd - gainStart) / Float(count)
        var frame = 0
        while frame < count {
            frame = run(
                input, into: output, from: frame, to: count,
                gain: gainStart + gainStep * Float(frame), gainStep: gainStep)
            // Stopped early: the old room has faded out. Move, and carry on in the new one.
            if frame < count, let next = pending {
                clear()
                acoustics = next
                pending = nil
                tune()
            }
        }
    }

    /// Renders frames `start..<end`, or up to the frame where a pending change of room has faded
    /// the old one out. Returns the first frame not rendered.
    private mutating func run(
        _ input: UnsafeMutableBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>,
        from start: Int, to end: Int, gain: Float, gainStep: Float
    ) -> Int {
        var frame = start
        storage.withUnsafeMutableBufferPointer { buffer in
            guard let memory = buffer.baseAddress else {
                frame = end
                return
            }
            // Work on local copies, so the loop keeps its state in registers.
            var gain = gain
            var fade = self.fade
            var tapWrite = self.tapWrite
            var allpassPosition = self.allpassPosition
            var linePosition = self.linePosition
            var filtered = self.filtered
            let isChanging = pending != nil
            let fadeStep = self.fadeStep
            let tapMask = self.tapMask
            let preDelay = self.preDelay
            let earlyDelay = self.earlyDelay
            let earlyGain = self.earlyGain
            let allpassStart = self.allpassStart
            let allpassLength = self.allpassLength
            let diffusion = self.diffusion
            let lineStart = self.lineStart
            let lineLength = self.lineLength
            let lineGain = self.lineGain
            let lineDamping = self.lineDamping
            let tailGain = self.tailGain
            defer {
                self.fade = fade
                self.tapWrite = tapWrite
                self.allpassPosition = allpassPosition
                self.linePosition = linePosition
                self.filtered = filtered
            }
            while frame < end {
                if isChanging {
                    fade -= fadeStep
                    if fade <= 0 {
                        fade = 0
                        return
                    }
                } else if fade < 1 {
                    fade = min(fade + fadeStep, 1)
                }

                var sample = input[frame]
                if !sample.isFinite { sample = 0 }
                sample = min(max(sample * gain * fade, -8), 8)
                gain += gainStep

                // Pre-delay and early reflections share one tapped delay.
                memory[tapWrite] = sample
                var early: Float = 0
                for tap in 0..<4 {
                    early += memory[(tapWrite - earlyDelay[tap]) & tapMask] * earlyGain[tap]
                }
                var feed = memory[(tapWrite - preDelay) & tapMask]
                tapWrite = (tapWrite + 1) & tapMask

                // Smear.
                for stage in 0..<2 {
                    let slot = allpassStart[stage] + allpassPosition[stage]
                    let delayed = memory[slot]
                    let into = feed + delayed * diffusion
                    memory[slot] = into
                    feed = delayed - into * diffusion
                    allpassPosition[stage] += 1
                    if allpassPosition[stage] >= allpassLength[stage] { allpassPosition[stage] = 0 }
                }

                // The eight lines: read, lose a little (highs first), mix, write back.
                var read = SIMD8<Float>()
                for line in 0..<8 {
                    read[line] = memory[lineStart[line] + linePosition[line]]
                }
                filtered = read + (filtered - read) * lineDamping
                let returned = filtered * lineGain
                let mixed = returned - SIMD8(repeating: returned.sum() * 0.25)
                let write = mixed + Self.signs * (feed * 0.353_553_4)
                for line in 0..<8 {
                    memory[lineStart[line] + linePosition[line]] = write[line]
                }
                linePosition &+= 1
                linePosition.replace(with: 0, where: linePosition .>= lineLength)
                let tail = (read * Self.signs).sum() * 0.353_553_4

                output[frame] += (early + tail * tailGain) * fade
                frame += 1
            }
        }
        return frame
    }
}
