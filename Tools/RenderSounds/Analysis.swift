// Measurements on rendered sound, without Accelerate so the tool also builds on Linux.

import Foundation

func decibels(_ value: Float) -> Float { value > 0 ? 20 * log10(value) : -120 }

func peak(_ samples: [Float]) -> Float { samples.reduce(0) { max($0, abs($1)) } }

func rms(_ samples: ArraySlice<Float>) -> Float {
    guard !samples.isEmpty else { return 0 }
    return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
}

/// Roughly what a phone's own speaker gets across: the RMS of the sound through a 200 Hz – 6 kHz band
/// (4th-order high-pass, 2nd-order low-pass), over the loudest 300 ms.
func phoneSpeakerRMS(_ samples: [Float]) -> Float {
    let heard = phoneBand(samples)
    let window = min(Int(0.3 * sampleRate), heard.count)
    var best: Float = 0
    var sum: Float = 0
    for index in heard.indices {
        sum += heard[index] * heard[index]
        if index >= window { sum -= heard[index - window] * heard[index - window] }
        best = max(best, sum)
    }
    return sqrt(best / Float(max(window, 1)))
}

func phoneBand(_ samples: [Float]) -> [Float] {
    var highPass1 = Biquad(.highPass, frequency: 200, q: 0.541, sampleRate: sampleRate)
    var highPass2 = Biquad(.highPass, frequency: 200, q: 1.307, sampleRate: sampleRate)
    var lowPass = Biquad(.lowPass, frequency: 6_000, q: 0.707, sampleRate: sampleRate)
    return samples.map { lowPass.process(highPass2.process(highPass1.process($0))) }
}

/// In-place iterative radix-2 FFT. `real.count` must be a power of two.
func fft(_ real: inout [Float], _ imaginary: inout [Float]) {
    let count = real.count
    var j = 0
    for i in 1..<count {
        var bit = count >> 1
        while j & bit != 0 {
            j ^= bit
            bit >>= 1
        }
        j |= bit
        if i < j {
            real.swapAt(i, j)
            imaginary.swapAt(i, j)
        }
    }
    var length = 2
    while length <= count {
        let angle = -2 * Double.pi / Double(length)
        for start in stride(from: 0, to: count, by: length) {
            for k in 0..<length / 2 {
                let wr = Float(cos(angle * Double(k))), wi = Float(sin(angle * Double(k)))
                let a = start + k, b = a + length / 2
                let tr = real[b] * wr - imaginary[b] * wi
                let ti = real[b] * wi + imaginary[b] * wr
                real[b] = real[a] - tr
                imaginary[b] = imaginary[a] - ti
                real[a] += tr
                imaginary[a] += ti
            }
        }
        length <<= 1
    }
}

/// Power spectrum of `samples` (Hann-windowed frames of 4096, summed). Frames overlap by three
/// quarters, so every sample counts the same wherever it falls: with half-overlapping frames a
/// click counts for up to twice as much in the middle of a frame as between two, and the
/// brightness of a sound depends on when it starts.
func powerSpectrum(_ samples: ArraySlice<Float>, size: Int = 4096) -> [Float] {
    var total = [Float](repeating: 0, count: size / 2)
    let window = (0..<size).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(size)) }
    var start = samples.startIndex
    repeat {
        var real = [Float](repeating: 0, count: size), imaginary = [Float](repeating: 0, count: size)
        for index in 0..<size where start + index < samples.endIndex {
            real[index] = samples[start + index] * window[index]
        }
        fft(&real, &imaginary)
        for bin in 0..<size / 2 { total[bin] += real[bin] * real[bin] + imaginary[bin] * imaginary[bin] }
        start += size / 4
    } while start + size / 4 < samples.endIndex
    return total
}

struct SpectrumSummary {
    var centroid: Float
    /// Share of energy in bands, 0...1.
    var below250: Float
    var mid250to2k: Float
    var presence2to5k: Float
    var above5k: Float
}

func summarize(_ spectrum: [Float]) -> SpectrumSummary {
    let binWidth = sampleRate / Float(spectrum.count * 2)
    var weighted: Float = 0, total: Float = 0
    var bands = [Float](repeating: 0, count: 4)
    for (bin, power) in spectrum.enumerated().dropFirst() {
        let frequency = Float(bin) * binWidth
        weighted += frequency * power
        total += power
        let band = frequency < 250 ? 0 : frequency < 2_000 ? 1 : frequency < 5_000 ? 2 : 3
        bands[band] += power
    }
    let share = { (value: Float) in total > 0 ? value / total : 0 }
    return SpectrumSummary(
        centroid: total > 0 ? weighted / total : 0, below250: share(bands[0]), mid250to2k: share(bands[1]),
        presence2to5k: share(bands[2]), above5k: share(bands[3]))
}

/// How harsh a sound starts: where its energy sits over the first 200 ms after its onset (the
/// first sample above 5 % of the peak), which is the stretch listeners judge a material by.
struct Harshness {
    /// Spectral centroid in Hz. Wood and knocks sit low; above about 2.7 kHz reads as metal or glass.
    var centroid: Float
    /// Share of the energy in 2–5 kHz, where the ear is most sensitive and a phone speaker
    /// loudest, and above 5 kHz (0...1).
    var presence: Float
    var air: Float
}

func harshness(_ samples: [Float]) -> Harshness {
    let threshold = peak(samples) * 0.05
    guard threshold > 0, let onset = samples.firstIndex(where: { abs($0) > threshold }) else {
        return Harshness(centroid: 0, presence: 0, air: 0)
    }
    let end = min(onset + Int(0.2 * sampleRate), samples.count)
    // Three quarters of a frame of lead-in, so the first milliseconds (the brightest) are not
    // lost under the start of the first window.
    let size = 1_024
    let summary = summarize(powerSpectrum(samples[max(onset - size * 3 / 4, 0)..<end], size: size))
    return Harshness(centroid: summary.centroid, presence: summary.presence2to5k, air: summary.above5k)
}

/// How tonal a continuous sound is: per 40 ms window that is sounding, the highest normalized
/// autocorrelation for pitches between 80 Hz and 1 kHz, and the pitch it is at.
struct Periodicity {
    /// Highest periodicity of any window (1 = a pure tone, 0 = noise).
    var maximum: Float
    var median: Float
    /// 10th and 90th percentile of the detected pitch over strongly periodic windows (> 0.5), Hz.
    var pitchLow: Float
    var pitchHigh: Float
    /// Share of 10 ms frames above -55 dBFS.
    var soundingShare: Float
}

func periodicity(_ samples: [Float]) -> Periodicity {
    let window = Int(0.04 * sampleRate)
    let minLag = Int(sampleRate / 1_000), maxLag = Int(sampleRate / 80)
    var values: [Float] = []
    var pitches: [Float] = []
    var start = 0
    while start + window + maxLag < samples.count {
        let frame = samples[start..<start + window]
        if rms(frame) > 0.0018 {  // -55 dBFS
            var best: Float = 0, bestLag = minLag
            let energy = frame.reduce(0) { $0 + $1 * $1 }
            for lag in minLag...maxLag {
                var dot: Float = 0, lagged: Float = 0
                for index in start..<start + window {
                    dot += samples[index] * samples[index + lag]
                    lagged += samples[index + lag] * samples[index + lag]
                }
                let value = dot / max(sqrt(energy * lagged), 1e-12)
                if value > best {
                    best = value
                    bestLag = lag
                }
            }
            values.append(best)
            if best > 0.5 { pitches.append(sampleRate / Float(bestLag)) }
        }
        start += window / 2
    }
    var sounding = 0, frames = 0
    let tenMs = Int(0.01 * sampleRate)
    for frameStart in stride(from: 0, to: samples.count - tenMs, by: tenMs) {
        frames += 1
        if rms(samples[frameStart..<frameStart + tenMs]) > 0.0018 { sounding += 1 }
    }
    values.sort()
    pitches.sort()
    let percentile = { (array: [Float], p: Float) -> Float in
        array.isEmpty ? 0 : array[min(array.count - 1, Int(p * Float(array.count)))]
    }
    return Periodicity(
        maximum: values.last ?? 0, median: percentile(values, 0.5), pitchLow: percentile(pitches, 0.1),
        pitchHigh: percentile(pitches, 0.9), soundingShare: frames > 0 ? Float(sounding) / Float(frames) : 0)
}

/// Seconds for the level to fall 60 dB after the peak (from the -5 to -25 dB slope of the
/// Schroeder backward integral, extrapolated), and the raw time the signal stays above peak - 40 dB.
func decayTimes(_ samples: [Float]) -> (t60: Float, ring: Float) {
    let peakValue = peak(samples)
    let peakIndex = samples.firstIndex { abs($0) == peakValue } ?? 0
    let lastLoud = samples.lastIndex { abs($0) > peakValue * 0.01 } ?? peakIndex
    let ring = Float(lastLoud - peakIndex) / sampleRate
    var energy = [Float](repeating: 0, count: samples.count - peakIndex)
    var sum: Float = 0
    for index in stride(from: samples.count - 1, through: peakIndex, by: -1) {
        sum += samples[index] * samples[index]
        energy[index - peakIndex] = sum
    }
    guard let total = energy.first, total > 0 else { return (0, ring) }
    let level = energy.map { 10 * log10(max($0 / total, 1e-12)) }
    guard let at5 = level.firstIndex(where: { $0 <= -5 }), let at25 = level.firstIndex(where: { $0 <= -25 }),
        at25 > at5
    else { return (0, ring) }
    return (Float(at25 - at5) / sampleRate * 3, ring)
}

/// Largest jump between adjacent samples. A click shows up as a big jump in a quiet place.
func largestStep(_ samples: [Float]) -> Float {
    var largest: Float = 0
    for index in samples.indices.dropFirst() { largest = max(largest, abs(samples[index] - samples[index - 1])) }
    return largest
}

func writeWAV(_ samples: [Float], to url: URL) throws {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    let byteCount = UInt32(samples.count * 2)
    data.append(contentsOf: Array("RIFF".utf8))
    append(36 + byteCount)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))  // PCM
    append(UInt16(1))  // mono
    append(UInt32(sampleRate))
    append(UInt32(sampleRate) * 2)
    append(UInt16(2))
    append(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    append(byteCount)
    for sample in samples {
        append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
    }
    try data.write(to: url)
}
