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

func knock(_ x: Float, _ y: Float, at time: Float, volume: Float = 1) -> Cue {
    Cue(time: time) { $0.knock(at: KnockSpot(x: x, y: y), volume: volume) }
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

/// `speaker`: voiced for the phone's own speakers, as the app plays on them (see `SpeakerVoicing`).
func render(_ name: String, seconds: Float, cues: [Cue], profile: SoundProfile = .oak, speaker: Bool = false) throws {
    let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: 42, speakerVoicing: speaker)
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
    let onPhone = phoneSpeakerRMS(samples)
    print(
        name.padding(toLength: 20, withPad: " ", startingAt: 0),
        String(
            format:
                "peak %6.1f dBFS   rms %6.1f dBFS   ring %4.0f ms   centroid %5.0f Hz   above 250 Hz %6.1f dB   on phone %6.1f dB",
            decibels(peak), decibels(rms), ringTime * 1000, brightness, decibels(speakerLevel), decibels(onPhone)),
        finite ? "" : "  NON-FINITE SAMPLES")

    try writeWAV(samples, to: outputDirectory.appendingPathComponent("\(name).wav"))
}

/// Roughly what a phone's own speaker gets across: the RMS of the sound through a 200 Hz – 6 kHz band
/// (4th-order high-pass, 2nd-order low-pass), over the loudest 300 ms.
func phoneSpeakerRMS(_ samples: [Float]) -> Float {
    var highPass1 = Biquad(.highPass, frequency: 200, q: 0.541, sampleRate: sampleRate)
    var highPass2 = Biquad(.highPass, frequency: 200, q: 1.307, sampleRate: sampleRate)
    var lowPass = Biquad(.lowPass, frequency: 6_000, q: 0.707, sampleRate: sampleRate)
    let heard = samples.map { lowPass.process(highPass2.process(highPass1.process($0))) }
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
// Where the knock lands: middle of the leaf, near the hinge edge, by the handle, near the top.
try render("knock-middle", seconds: 0.6, cues: [knock(0.5, 0.5, at: 0.05)])
try render("knock-edge", seconds: 0.6, cues: [knock(0.06, 0.5, at: 0.05)])
try render("knock-handle", seconds: 0.6, cues: [knock(0.94, 0.5, at: 0.05)])
try render("knock-top", seconds: 0.6, cues: [knock(0.5, 0.08, at: 0.05)])
// The same spot three times, then walking across the door.
try render(
    "knock-repeat", seconds: 1.4,
    cues: [knock(0.5, 0.4, at: 0.05, volume: 0.9), knock(0.5, 0.4, at: 0.33), knock(0.5, 0.4, at: 0.58, volume: 0.85)])
try render(
    "knock-across", seconds: 1.6,
    cues: [
        knock(0.08, 0.45, at: 0.05), knock(0.3, 0.45, at: 0.33), knock(0.55, 0.45, at: 0.61),
        knock(0.92, 0.5, at: 0.89),
    ])
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

// As played on the phone's own speakers: compare with the flat files above.
for (name, profile) in doors.prefix(6) {
    try render("speaker-knock-\(name)", seconds: 1.2, cues: [play(.knock, at: 0.05)], profile: profile, speaker: true)
}
try render("speaker-slam", seconds: 1.4, cues: [play(.slam, at: 0.05)], speaker: true)
try render(
    "speaker-sequence", seconds: 5.5,
    cues: [
        play(.knock, at: 0.1, volume: 0.9), play(.knock, at: 0.36),
        play(.unlatch, at: 1.3),
    ]
        + swing(from: 1.35, duration: 1.2) { 140 * sin(.pi * $0 / 1.2) }
        + [play(.openStop, at: 2.6, volume: 0.6)]
        + swing(from: 3.4, duration: 0.45) { -260 * sin(.pi * $0 / 0.45) }
        + [play(.slam, at: 3.85)],
    speaker: true)

print("Wrote WAV files to \(outputDirectory.path)")
