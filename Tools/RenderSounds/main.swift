// Renders every door sound to a WAV file so the synth can be auditioned and tuned on a Mac.
//
//   make sounds                 # writes build/sounds/*.wav and prints levels
//   afplay build/sounds/sequence.wav
//
// Compiled together with Duor/Audio/DSP/*.swift (no app or AVFoundation code).

import Accelerate
import Foundation

let sampleRate: Float = 48_000
let blockSize = 256
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/sounds")

/// Something to do to the synth at a point in time.
struct Cue {
    var time: Float
    var action: (DoorSynth) -> Void
}

func play(_ sound: DoorSound, at time: Float, volume: Float = 1) -> Cue {
    Cue(time: time) { $0.play(sound, volume: volume) }
}

/// Feeds hinge velocity at 60 Hz, like `onHingeChange` would, then stops.
func swing(from start: Float, duration: Float, velocity: @escaping (Float) -> Float) -> [Cue] {
    let steps = Int(duration * 60)
    var cues = (0...steps).map { step in
        let t = Float(step) / 60
        return Cue(time: start + t) { $0.setCreak(velocity: velocity(t)) }
    }
    cues.append(Cue(time: start + duration) { $0.setCreak(velocity: 0) })
    return cues
}

func render(_ name: String, seconds: Float, cues: [Cue], profile: SoundProfile = .oak) throws {
    let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: 42)
    let frameCount = Int(seconds * sampleRate)
    var samples = [Float](repeating: 0, count: frameCount)
    var pending = cues.sorted { $0.time < $1.time }[...]

    var frame = 0
    while frame < frameCount {
        let now = Float(frame) / sampleRate
        while let cue = pending.first, cue.time <= now {
            cue.action(synth)
            pending = pending.dropFirst()
        }
        let count = min(blockSize, frameCount - frame)
        samples.withUnsafeMutableBufferPointer { buffer in
            synth.render(into: UnsafeMutableBufferPointer(rebasing: buffer[frame..<frame + count]))
        }
        frame += count
    }

    let peak = samples.map(abs).max() ?? 0
    let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(max(frameCount, 1)))
    let decibels = { (value: Float) in value > 0 ? 20 * log10(value) : -.infinity }
    let finite = samples.allSatisfy(\.isFinite)
    // Ring time: from the peak until the signal last exceeds the peak minus 40 dB.
    let peakIndex = samples.firstIndex { abs($0) == peak } ?? 0
    let lastLoud = samples.lastIndex { abs($0) > peak * 0.01 } ?? peakIndex
    let ringTime = Float(lastLoud - peakIndex) / sampleRate
    let (brightness, speakerLevel) = spectrum(of: samples, from: max(peakIndex - 64, 0))
    print(
        name.padding(toLength: 14, withPad: " ", startingAt: 0),
        String(
            format: "peak %6.1f dBFS   rms %6.1f dBFS   ring %4.0f ms   centroid %5.0f Hz   above 250 Hz %6.1f dB",
            decibels(peak), decibels(rms), ringTime * 1000, brightness, decibels(speakerLevel)),
        finite ? "" : "  NON-FINITE SAMPLES")

    try writeWAV(samples, to: outputDirectory.appendingPathComponent("\(name).wav"))
}

/// Spectral centroid (how bright it sounds) and RMS above 250 Hz (what a phone speaker can play)
/// over the 170 ms after `start`.
func spectrum(of samples: [Float], from start: Int) -> (centroid: Float, highRMS: Float) {
    let count = 8192
    var frame = [Float](repeating: 0, count: count)
    for index in 0..<min(count, samples.count - start) { frame[index] = samples[start + index] }
    let fft = vDSP.FFT(log2n: 13, radix: .radix2, ofType: DSPSplitComplex.self)!
    var real = [Float](repeating: 0, count: count / 2), imaginary = [Float](repeating: 0, count: count / 2)
    var magnitudes = [Float](repeating: 0, count: count / 2)
    real.withUnsafeMutableBufferPointer { realPointer in
        imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
            var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
            frame.withUnsafeBufferPointer {
                $0.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: count / 2) {
                    vDSP_ctoz($0, 2, &split, 1, vDSP_Length(count / 2))
                }
            }
            fft.forward(input: split, output: &split)
            vDSP.squareMagnitudes(split, result: &magnitudes)
        }
    }
    let binWidth = sampleRate / Float(count)
    var weighted: Float = 0, total: Float = 0, high: Float = 0
    for (bin, power) in magnitudes.enumerated().dropFirst() {
        let frequency = Float(bin) * binWidth
        weighted += frequency * power
        total += power
        if frequency >= 250 { high += power }
    }
    let rmsScale = sqrt(Float(count)) * Float(count) / 2
    return (total > 0 ? weighted / total : 0, sqrt(high * 2) / rmsScale)
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

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

try render(
    "knock", seconds: 1.4,
    cues: [play(.knock, at: 0.05, volume: 0.9), play(.knock, at: 0.33), play(.knock, at: 0.58, volume: 0.85)])
try render("knock-single", seconds: 0.6, cues: [play(.knock, at: 0.05)])
try render("unlatch", seconds: 0.8, cues: [play(.unlatch, at: 0.05)])
try render("airlock-unlatch", seconds: 1, cues: [play(.unlatch, at: 0.05)], profile: .spaceship)
try render(
    "spaceship-creak", seconds: 2.2, cues: swing(from: 0.1, duration: 1.3) { 120 * sin(.pi * $0 / 1.3) },
    profile: .spaceship)
try render("steel-slam", seconds: 1.6, cues: [play(.slam, at: 0.05)], profile: .steel)
try render("steel-latch", seconds: 1.2, cues: [play(.latch, at: 0.05)], profile: .steel)
try render(
    "steel-creak", seconds: 2.2, cues: swing(from: 0.1, duration: 1.3) { 120 * sin(.pi * $0 / 1.3) }, profile: .steel)
try render("latch-gentle", seconds: 0.9, cues: [play(.latch, at: 0.05, volume: 0.6)])
try render("latch-firm", seconds: 0.9, cues: [play(.latch, at: 0.05, volume: 1)])
try render("slam", seconds: 1.4, cues: [play(.slam, at: 0.05)])
try render("open-stop", seconds: 0.9, cues: [play(.openStop, at: 0.05, volume: 0.8)])
try render("creak-slow", seconds: 3, cues: swing(from: 0.1, duration: 2.4) { _ in 22 })
try render(
    "creak-open", seconds: 2.2,
    cues: swing(from: 0.1, duration: 1.3) { 170 * sin(.pi * $0 / 1.3) } + [play(.openStop, at: 1.4, volume: 0.5)])

// Knock, knock. Open slowly, hit the stop, swing it shut fast: slam.
try render(
    "sequence", seconds: 5.5,
    cues: [
        play(.knock, at: 0.1, volume: 0.9), play(.knock, at: 0.36),
        play(.unlatch, at: 1.3),
    ]
        + swing(from: 1.35, duration: 1.2) { 140 * sin(.pi * $0 / 1.2) }
        + [play(.openStop, at: 2.6, volume: 0.6)]
        + swing(from: 3.4, duration: 0.45) { -260 * sin(.pi * $0 / 0.45) }
        + [play(.slam, at: 3.85)])

// Every door type: a knock and the full sequence.
let doors: [(String, SoundProfile)] = [
    ("oak", .oak), ("pine", .pine), ("barn", .barn), ("castle", .castle), ("spaceship", .spaceship), ("steel", .steel),
    ("oak-brass", SoundProfile.oak.with(metal: .brass)), ("oak-chrome", SoundProfile.oak.with(metal: .chrome)),
]
for (name, profile) in doors {
    try render("knock-\(name)", seconds: 1.2, cues: [play(.knock, at: 0.05)], profile: profile)
    try render(
        "door-\(name)", seconds: 5.5,
        cues: [
            play(.knock, at: 0.1, volume: 0.9), play(.knock, at: 0.36),
            play(.unlatch, at: 1.3),
        ]
            + swing(from: 1.35, duration: 1.2) { 140 * sin(.pi * $0 / 1.2) }
            + [play(.openStop, at: 2.6, volume: 0.6)]
            + swing(from: 3.4, duration: 0.45) { -260 * sin(.pi * $0 / 0.45) }
            + [play(.slam, at: 3.85)],
        profile: profile)
}

print("Wrote WAV files to \(outputDirectory.path)")
