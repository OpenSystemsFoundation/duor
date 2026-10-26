// Renders every door sound to a WAV file so the synth can be auditioned and tuned on a Mac.
//
//   make sounds                 # writes build/sounds/*.wav and prints levels
//   afplay build/sounds/sequence.wav
//
// Compiled together with Duor/Audio/DSP/*.swift (no app or AVFoundation code).

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

func render(_ name: String, seconds: Float, cues: [Cue]) throws {
    let synth = DoorSynth(sampleRate: sampleRate, seed: 42)
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
    print(
        name.padding(toLength: 14, withPad: " ", startingAt: 0),
        String(
            format: "peak %6.1f dBFS   rms %6.1f dBFS   ring to -40 dB %4.0f ms", decibels(peak), decibels(rms),
            ringTime * 1000),
        finite ? "" : "  NON-FINITE SAMPLES")

    try writeWAV(samples, to: outputDirectory.appendingPathComponent("\(name).wav"))
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

print("Wrote WAV files to \(outputDirectory.path)")
